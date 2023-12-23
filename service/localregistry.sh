#!/bin/bash

############################################################
# status
if [ "$1" = "status" ] ; then
  TASK=$(/usr/bin/ctr task list | grep localregistry)
  if [ -z "$TASK" ] ; then
    echo "no local registry"
  else
    TASK_DATA=($TASK)
    TASK_NAME="${TASK_DATA[0]}"
    TASK_PID="${TASK_DATA[1]}"
    TASK_STATUS="${TASK_DATA[2]}"
    echo "$TASK_NAME is $TASK_STATUS, PID is $TASK_PID"
  fi
fi

############################################################
# start
if [ "$1" = "start" ] ; then
  /usr/bin/ctr run --net-host --detach docker.io/library/registry:2 localregistry
  if [ $? -ne 0 ] ; then
    exit $?
  fi
  TASK=$(/usr/bin/ctr task list | grep localregistry)
  if [ -z "$TASK" ] ; then
    exit 1
  else
    TASK_DATA=($TASK)
    TASK_PID="${TASK_DATA[1]}"
    echo $TASK_PID > /run/localregistry.pid
  fi
  exit 0
fi

############################################################
# stop service
if [ "$1" = "stop" ] ; then
  /usr/bin/ctr task kill localregistry
  /usr/bin/ctr container remove localregistry
fi

############################################################
# add service
if [ "$1" = "add" ] ; then
  tee << "  EOL_LOCALREGISTRY_SERVICE" | sed 's/^  //' > /etc/systemd/system/localregistry.service
  [Unit]
  Description=local registry service
  After=network.target
  [Service]
  Type=forking
  Restart=on-failure
  RestartSec=3
  ExecStart=/etc/systemd/system/localregistry.sh start
  PIDFile=/run/localregistry.pid
  ExecStop=/etc/systemd/system/localregistry.sh stop

  [Install]
  WantedBy=multi-user.target
  EOL_LOCALREGISTRY_SERVICE

  cp $0 /etc/systemd/system/
  systemctl daemon-reload
fi

############################################################
# remove service
if [ "$1" = "remove" ] ; then
  systemctl stop localregistry
  systemctl disable localregistry
  rm -f /etc/systemd/system/localregistry.service
  rm -f /etc/systemd/system/localregistry.sh
  systemctl daemon-reload
fi

