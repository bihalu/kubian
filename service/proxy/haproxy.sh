#!/bin/bash

############################################################
# status
if [ "$1" = "status" ] ; then
  TASK=$(/usr/bin/ctr task list | grep haproxy)
  if [ -z "$TASK" ] ; then
    echo "no haproxy"
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
  /usr/bin/ctr run \
    --net-host \
    --detach \
    --mount type=bind,src=/usr/local/etc/haproxy,dst=/usr/local/etc/haproxy,options=rbind:ro \
    docker.io/library/haproxy:bookworm haproxy

  if [ $? -ne 0 ] ; then
    exit $?
  fi
  TASK=$(/usr/bin/ctr task list | grep haproxy)
  if [ -z "$TASK" ] ; then
    exit 1
  else
    TASK_DATA=($TASK)
    TASK_PID="${TASK_DATA[1]}"
    echo $TASK_PID > /run/haproxy.pid
  fi
  exit 0
fi

############################################################
# stop service
if [ "$1" = "stop" ] ; then
  /usr/bin/ctr task kill haproxy
  /usr/bin/ctr task delete haproxy
  /usr/bin/ctr container delete haproxy
fi

############################################################
# add service
if [ "$1" = "add" ] ; then
  tee << "  EOL_HAPROXY_SERVICE" | sed 's/^    //' > /etc/systemd/system/haproxy.service
    [Unit]
    Description=local registry service
    After=network.target
    [Service]
    Type=forking
    Restart=on-failure
    RestartSec=3
    PIDFile=/run/haproxy.pid
    ExecStart=/etc/systemd/system/haproxy.sh start
    ExecStop=/etc/systemd/system/haproxy.sh stop
    [Install]
    WantedBy=multi-user.target
  EOL_HAPROXY_SERVICE

  mkdir -p /usr/local/etc/haproxy

  tee << "  EOL_HAPROXY_CONFIG" | sed 's/^    //' > /usr/local/etc/haproxy/haproxy.cfg
    global

    defaults
      mode http
      timeout client 10s
      timeout connect 5s
      timeout server 10s
      timeout http-request 10s
      log global

    frontend registry
      bind *:5001
      default_backend localregistry

    backend localregistry
      option httpchk
      server controlplane1 192.168.178.195:5000 check  inter 10s  fall 5  rise 5
      server controlplane2 192.168.178.196:5000 check  inter 10s  fall 5  rise 5
      server controlplane3 192.168.178.197:5000 check  inter 10s  fall 5  rise 5
  EOL_HAPROXY_CONFIG

  cp $0 /etc/systemd/system/
  systemctl daemon-reload
fi

############################################################
# remove service
if [ "$1" = "remove" ] ; then
  systemctl stop haproxy
  systemctl disable haproxy
  rm -f /etc/systemd/system/haproxy.service
  rm -f /etc/systemd/system/haproxy.sh
  systemctl daemon-reload
fi

