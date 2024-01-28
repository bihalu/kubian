#!/bin/bash

NAME="softserve"
VERSION="0.1.0"

############################################################
# status service
if [ "$1" = "status" ] ; then
  TASK=$(/usr/bin/ctr task list | grep softserve)
  if [ -z "$TASK" ] ; then
    echo "no softserve"
  else
    TASK_DATA=($TASK)
    TASK_NAME="${TASK_DATA[0]}"
    TASK_PID="${TASK_DATA[1]}"
    TASK_STATUS="${TASK_DATA[2]}"
    echo "$TASK_NAME is $TASK_STATUS, PID is $TASK_PID"
  fi
fi

############################################################
# start service
if [ "$1" = "start" ] ; then
  /usr/bin/ctr run \
    --net-host \
    --detach \
    --mount type=bind,src=/usr/local/soft-serve,dst=/soft-serve,options=rbind:rw \
    docker.io/charmcli/soft-serve:v0.7.4 softserve

  if [ $? -ne 0 ] ; then
    exit $?
  fi
  TASK=$(/usr/bin/ctr task list | grep softserve)
  if [ -z "$TASK" ] ; then
    exit 1
  else
    TASK_DATA=($TASK)
    TASK_PID="${TASK_DATA[1]}"
    echo $TASK_PID > /run/softserve.pid
  fi
  exit 0
fi

############################################################
# stop service
if [ "$1" = "stop" ] ; then
  /usr/bin/ctr task kill softserve
  /usr/bin/ctr task delete softserve
  /usr/bin/ctr container delete softserve
fi

############################################################
# add service
if [ "$1" = "add" ] ; then
  tee << "  EOL_SOFTSERVE_SERVICE" | sed 's/^    //' > /etc/systemd/system/softserve.service
    [Unit]
    Description=local registry service
    After=network.target
    [Service]
    Type=forking
    Restart=on-failure
    RestartSec=3
    PIDFile=/run/softserve.pid
    ExecStart=/etc/systemd/system/softserve.sh start
    ExecStop=/etc/systemd/system/softserve.sh stop
    [Install]
    WantedBy=multi-user.target
  EOL_SOFTSERVE_SERVICE

  cp $0 /etc/systemd/system/
  mkdir -p /usr/local/softserve
  systemctl daemon-reload
fi

############################################################
# remove service
if [ "$1" = "remove" ] ; then
  systemctl stop softserve
  systemctl disable softserve
  rm -f /etc/systemd/system/softserve.service
  rm -f /etc/systemd/system/softserve.sh
  systemctl daemon-reload
fi

############################################################
# build package
if [ "$1" = "build" ] ; then

  mkdir -p container

  ctr image pull docker.io/charmcli/soft-serve:v0.7.4 
  ctr images export container/images.tar docker.io/charmcli/soft-serve:v0.7.4 
  
  TAR_FILE="$NAME-$VERSION.tgz"
  SELF_EXTRACTABLE="$TAR_FILE.self"

  echo "Be patient creating self extracting archive ..."
  # pack and create self extracting archive
  tar -czf $TAR_FILE  softserve.sh deb/ container/

  echo '#!/bin/bash' > $SELF_EXTRACTABLE
  echo 'echo Extract archive ...' >> $SELF_EXTRACTABLE
  echo -n 'dd bs=`head -5 $0 | wc -c` skip=1 if=$0 ' >> $SELF_EXTRACTABLE
  echo -n "$SUPRESS_STDERR" >> $SELF_EXTRACTABLE
  echo ' | gunzip -c | tar -x' >> $SELF_EXTRACTABLE
  echo 'exec ./softserve.sh setup' >> $SELF_EXTRACTABLE
  echo '######################################################################' >> $SELF_EXTRACTABLE

  cat $TAR_FILE >> $SELF_EXTRACTABLE
  chmod a+x $SELF_EXTRACTABLE
  rm -rf $TAR_FILE container/
fi

############################################################
# setup package
if [ "$1" = "setup" ] ; then

  # import container image
  ctr images import container/images.tar

  # cleanup
  rm -rf deb/ container/
fi