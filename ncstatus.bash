#!/bin/bash
# --------------------------------------------------------------------
# LogMatrix / OpenService NerveCenter 'ncstatus'
# Copyright (C) 2017 OpenService, Inc. All Rights Reserved.
#
# LogMatrix NerveCenter 8.2.00
#
#  ncstatus - display status of NerveCenter service.
#
#  You are welcome to adapt this script as you like
#

if [ ! -d /opt/OSInc/nc/bin ]; then
     echo Check NerveCenter installation.
     exit 1
fi

# --------------------------------------------------------------------
# Version  - Display version info
version()
{
   ver=`cat /opt/OSInc/nc/dat/version`
   rel=`cat /opt/OSInc/nc/dat/version-release`
   echo "ncstatus  $ver ($rel)"
}

# --------------------------------------------------------------------
# Help  - Display help info
help()
{
   echo " "
   echo "      ncstatus  [-c|--config] [-p|--process] [-l|--logins]"
   echo "                [-s|--services] [-r|-runtime] [-a|-all]"
   echo " "
   echo "              -c,--config   Configuration"
   echo "              -s,--services Print services status"
   echo "              -p,--process  Print process heirarchy [1]"
   echo "              -r,--runtime  Print runtime summary info [1]"
   echo "              -l,--logins   Print who is logged in to ncserver [1]"
   echo "              -a,--all      Equivalent of -c -l -p -s -r"
   echo " "
   echo "      ncstatus  [-h|--help] [-v|--ver]"
   echo " "
   echo "              -v,--ver      Print version"
   echo "              -h,--help     Print usage"
   echo " "
   echo " "
   echo "      [1] Only if NerveCenter is active."
   echo " "
}

# --------------------------------------------------------------------
# Options
process="no"
services="no"
runtime="no"
logins="no"
config="no"

pollers=0

# --------------------------------------------------------------------
# Process command-line arguments
while [[ $# > 0 ]]; do
  case $1 in
     -c|--config)
        config="yes"
        shift
        ;;
     -p|--process)
        process="yes"
        shift
        ;;
     -s|--services)
        services="yes"
        shift
        ;;
     -r|--runtime)
        runtime="yes"
        shift
        ;;
     -l|--logins)
        logins="yes"
        shift
        ;;
     -a|-all)
        process="yes"
        services="yes"
        runtime="yes"
        logins="yes"
        config="yes"
        shift
        ;;
     -h|--help|-\?)
        version
        help
        exit 0
        ;;
     -v|-i|--ver|--version|-info)
        version
        exit 0
        ;;
     *)
        shift
        ;;
  esac
done

# --------------------------------------------------------------------
# Process Tree printer
indent=2
ncProcInfo()
{
   pid=$*

   if [ $process = "yes" ]; then
      for ((i=1;i<$indent;i++)) ; do echo -n "  " ; done
      cmd=`ps -p $pid -o comm=`
      vss=`ps -p $pid -o vsz=`
      cpu=`ps -p $pid -o %cpu=`
      echo "$cmd (pid $pid) $cpu %cpu, $vss KiB"
   fi

   indent=$((indent+1))
   children=`pgrep -P $*`
   for child in $children; do
      if [ $runtime = "yes" ]; then
         childname=`ps -p $child -o comm=`
         if [ "$childname" = "ncsnmppoller" ]; then
            pollers=$((pollers + 1))
         fi
      fi
      ncProcInfo $child
   done
   indent=$((indent-1))
}

# --------------------------------------------------------------------
# Report current logins to ncserver
ncLogins()
{
   echo " "
   echo "Logins:"

   loginfile="/var/opt/NerveCenter/tables/ncserver-logins.csv"
   if [ -r $loginfile ]; then
      OLDIFS=$IFS
      IFS=","

      row=0
      while read Id Application State Username OriginAddress OriginUser AccessLevel ConnectedAt; do
         row=$((row + 1))
         if [ $row -gt 1 ]; then
            echo "   $Application  $Username ($OriginUser $OriginAddress)  $AccessLevel  $ConnectedAt"
         fi
         # printf "'%s'\n" "$line"
      done < $loginfile

      IFS=$OLDIFS
   fi
}

# --------------------------------------------------------------------
# Report status of ncserver: whether running or not.
ncActive()
{
    result=0
    NCPID=`/bin/ps -e | awk '$4 == "ncserver" {print $1}'`
    if [ -z "$NCPID" ]; then
        echo "nervecenter service stopped."
    else
        result=1
        echo "nervecenter service running (pid $NCPID)"
    fi
    return $result
}

# --------------------------------------------------------------------
# Report the host operating system
ncOperatingSystem()
{
    echo -n "    Version: "
    if [ -f /etc/SuSE-release ]; then
       cat /etc/SuSE-release | head -1
    elif [ -f /etc/centos-release ]; then
       cat /etc/centos-release
    elif [ -f /etc/redhat-release ]; then
       cat /etc/redhat-release
    else
       echo
    fi
}

# --------------------------------------------------------------------
# Report status of a system service, based on a systemd registration
#    usage:
#       ncActiveService serverName mode
#               serviceName = ( nervecenter | mongod | ...
#               mode = ( state | status )
#                  state = ( active | inactive )
#                  status = [not] registered, [not] enabled, [not] active
ncActiveService()
{
    serviceName=$1
    mode=$2    # ( state | status )
    report="inactive"

    # This is a RHEL7/CentOS7/OracleLinux7 'systemd' environment
    echo -n "    Service: systemd ($serviceName.service): "
    # Is the service unit added to systemd(1) ?
    if [ -f "/usr/lib/systemd/system/$serviceName.service" ]; then
        # Is the service enabled for use?
        /usr/bin/systemctl is-enabled $serviceName >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            # Is the service currently running?
            /usr/bin/systemctl is-active $serviceName >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                if [ $mode = "status" ]; then
                    report="active"
                fi
                if [ $mode = "state" ]; then 
                    report="registered, enabled and active"
                fi
            else
                if [ $mode = "state" ]; then
                    report="registered, enabled, but not active"
                fi
            fi
         else
            if [ $mode = "state" ]; then
                report="registered, but not enabled"
            fi
         fi
    else
        if [ $mode = "state" ]; then
            report="not registered"
        fi
    fi

    echo $report
}

# --------------------------------------------------------------------
# Report status of a system service, based on a process
ncActiveProcess()
{
    processName=$1
    serviceName=$2

    echo -n "    Service: process ($serviceName): "

    ps -ef | grep "$processName" | grep -v grep > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo active
    else
        echo inactive
    fi
}

# --------------------------------------------------------------------
# Report runtime status of running ncserver.
ncRuntime()
{
   echo " "
   echo "Runtime:"
   if [ -r /var/opt/NerveCenter/proc/ncserver.0/ncserver.starttime ]; then
      echo "  Started: `cat /var/opt/NerveCenter/proc/ncserver.0/ncserver.starttime`"
   fi
   echo "  Operator Account: $username"
   echo "  SNMP Pollers: $pollers"
}

# --------------------------------------------------------------------
# Report config for NerveCenter Service.
ncConfig()
{
   echo " "
   echo "Configuration:"
   echo "  Host Operating System:"
   echo "    Hostname:" `hostname`
   ncOperatingSystem
   echo "  NerveCenter:"
   if [ -r /opt/OSInc/conf/nervecenter-application.txt ]; then
      echo "    Application:" `cat /opt/OSInc/conf/nervecenter-application.txt`
   fi
   ver=`cat /opt/OSInc/nc/dat/version`
   rel=`cat /opt/OSInc/nc/dat/version-release`
   echo "    Version: $ver ($rel)"
   licfile="/opt/OSInc/conf/`hostname`.dat"
   echo -n "    License ("$licfile"): "
   if [ -f $licfile ]; then
      echo "present"
   else
      echo "missing"
   fi
   if [ -r /opt/OSInc/conf/ncstart-user ]; then
      echo "    Operating Account:" `cat /opt/OSInc/conf/ncstart-user`
   elif [ -r /opt/OSInc/conf/ncstart-authorized ]; then
      echo "    Authorized Accounts:" `cat /opt/OSInc/conf/ncstart-authorized`
   fi
   ncActiveService nervecenter state
   ncActiveService nginx state
   ncActiveService mongod state
   if [ -r /opt/OSInc/conf/snmpEngineID.txt ]; then
      echo "    SNMP EngineID: " `cat /opt/OSInc/conf/snmpEngineID.txt`
   fi
}

# --------------------------------------------------------------------
# main processing
ncActive
isActive=$?

if [ $services = "yes" ]; then
   echo " "
   echo "Services:"
   ncActiveService nervecenter status
   ncActiveService nginx status
   ncActiveService mongod status
   ncActiveProcess "node app.js" node.js
fi

if [ $isActive -eq 1 ]; then
   ncservers=`/bin/ps -e | awk '$4 == "ncserver" {print $1}'`

   # If user wants parent/child listing, display it.
   if [ $process = "yes" -o $logins = "yes" -o $runtime = "yes" ]; then
      if [ $process = "yes" ]; then
         echo " "
         echo "Processes:"
      fi
      for ncserver in $ncservers; do
         username=`ps -p $ncserver -o user=`
         ncProcInfo $ncserver
         if [ $logins = "yes" ]; then
            ncLogins
         fi
      done
      if [ $runtime = "yes" ]; then
         ncRuntime
      fi
   fi
fi

if [ $config = "yes" ]; then
   ncConfig
fi

exit 0

# --------------------------------------------------------------------
# ###

