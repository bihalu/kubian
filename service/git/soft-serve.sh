#!/bin/bash

NAME="soft-serve"
VERSION="0.1.0"
SUPRESS_OUTPUT="2>&1>/dev/null"
SUPRESS_STDOUT="1>/dev/null"
SUPRESS_STDERR="2>/dev/null"

############################################################
# status service
if [ "$1" = "status" ] ; then
  TASK=$(/usr/bin/ctr task list | grep soft-serve)
  if [ -z "$TASK" ] ; then
    echo "no soft-serve"
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
  /usr/bin/ctr container list --quiet | grep soft-serve
  if [ $? -eq 0 ] ; then
    /usr/bin/ctr task kill soft-serve
    /usr/bin/ctr container remove soft-serve
  fi
  /usr/bin/ctr run \
    --net-host \
    --detach \
    --env "SOFT_SERVE_INITIAL_ADMIN_KEYS=$(cat ~/.ssh/id_ed25519.pub)" \
    --mount type=bind,src=/usr/local/soft-serve,dst=/soft-serve,options=rbind:rw \
    docker.io/charmcli/soft-serve:v0.7.4 soft-serve

  if [ $? -ne 0 ] ; then
    exit $?
  fi
  TASK=$(/usr/bin/ctr task list | grep soft-serve)
  if [ -z "$TASK" ] ; then
    exit 1
  else
    TASK_DATA=($TASK)
    TASK_PID="${TASK_DATA[1]}"
    echo $TASK_PID > /run/soft-serve.pid
  fi
  exit 0
fi

############################################################
# stop service
if [ "$1" = "stop" ] ; then
  /usr/bin/ctr task kill soft-serve
  /usr/bin/ctr task delete soft-serve
  /usr/bin/ctr container delete soft-serve
fi

############################################################
# add service
if [ "$1" = "add" ] ; then
  tee << "  EOL_SOFT_SERVE_SERVICE" | sed 's/^    //' > /etc/systemd/system/soft-serve.service
    [Unit]
    Description=soft-serve git service
    After=network.target
    [Service]
    Type=forking
    Restart=on-failure
    RestartSec=3
    PIDFile=/run/soft-serve.pid
    ExecStart=/etc/systemd/system/soft-serve.sh start
    ExecStop=/etc/systemd/system/soft-serve.sh stop
    [Install]
    WantedBy=multi-user.target
  EOL_SOFT_SERVE_SERVICE

  sed '1,/^# EOF/!d' $0 > /etc/systemd/system/$0
  chmod +x /etc/systemd/system/$0
  mkdir -p /usr/local/soft-serve
  systemctl daemon-reload
fi

############################################################
# remove service
if [ "$1" = "remove" ] ; then
  systemctl stop soft-serve
  systemctl disable soft-serve
  rm -f /etc/systemd/system/soft-serve.service
  rm -f /etc/systemd/system/soft-serve.sh
  systemctl daemon-reload
fi

# EOF
############################################################
# build package
if [ "$1" = "build" ] ; then

  apt install -y aptitude apt-transport-https containerd

  # configure containerd
  containerd config default | tee /etc/containerd/config.toml

  readarray -t PACKAGES <<"  EOL_PACKAGES"
  # containerd
  containerd 1.6.20~ds1-1+b1 amd64
  criu 3.17.1-2 amd64
  libnet1:amd64 1.1.6+dfsg-3.2 amd64
  libnl-3-200:amd64 3.7.0-0.2+b1 amd64
  libprotobuf32:amd64 3.21.12-3 amd64
  python3-protobuf 3.21.12-3 amd64
  runc 1.1.5+ds1-1+deb12u1 amd64
  sgml-base 1.31 all
  EOL_PACKAGES

  mkdir -p deb

  aptitude clean

  for PACKAGE in "${PACKAGES[@]}" ; do
    # don't process commented out packages
    [ ${PACKAGE:2:1} = \# ] && continue

    # parse package data
    PACKAGE_DATA=($PACKAGE)
    PACKAGE_NAME="${PACKAGE_DATA[0]%:amd64}"
    PACKAGE_VERSION="${PACKAGE_DATA[1]}"
    PACKAGE_ARCH="${PACKAGE_DATA[2]}"
    PACKAGE_VERSION_FILE=$(echo $PACKAGE_VERSION |sed 's/:/%3a/')
    PACKAGE_FILE="${PACKAGE_NAME}_${PACKAGE_VERSION_FILE}_${PACKAGE_ARCH}.deb"

    # skip download if already available
    [ -f deb/$PACKAGE_FILE ] && continue

    # download package
    aptitude --download-only install -y $PACKAGE_NAME=$PACKAGE_VERSION
    cp /var/cache/apt/archives/$PACKAGE_FILE deb/
    if [ $? != 0 ] ; then
      # aptitude will not download if package is installed, try download reinstall
      aptitude --download-only reinstall $PACKAGE_NAME
      cp /var/cache/apt/archives/$PACKAGE_FILE deb/
      [ $? != 0 ] && exit 1
    fi 
  done

  mkdir -p container

  ctr image pull docker.io/charmcli/soft-serve:v0.7.4 
  ctr images export container/images.tar docker.io/charmcli/soft-serve:v0.7.4 
  
  TAR_FILE="$NAME-$VERSION.tgz"
  SELF_EXTRACTABLE="$TAR_FILE.self"

  echo "Be patient creating self extracting archive ..."
  # pack and create self extracting archive
  tar -czf $TAR_FILE  soft-serve.sh deb/ container/

  echo '#!/bin/bash' > $SELF_EXTRACTABLE
  echo 'echo Extract archive ...' >> $SELF_EXTRACTABLE
  echo -n 'dd bs=`head -5 $0 | wc -c` skip=1 if=$0 ' >> $SELF_EXTRACTABLE
  echo -n "$SUPRESS_STDERR" >> $SELF_EXTRACTABLE
  echo ' | gunzip -c | tar -x' >> $SELF_EXTRACTABLE
  echo 'exec ./soft-serve.sh setup' >> $SELF_EXTRACTABLE
  echo '######################################################################' >> $SELF_EXTRACTABLE

  cat $TAR_FILE >> $SELF_EXTRACTABLE
  chmod a+x $SELF_EXTRACTABLE
  rm -rf $TAR_FILE deb/ container/
fi

############################################################
# setup package
if [ "$1" = "setup" ] ; then

  # install containerd
  PACKAGES=$(find deb -name "*.deb")
  dpkg --install $PACKAGES $SUPRESS_OUTPUT

  containerd config default | tee /etc/containerd/config.toml $SUPRESS_OUTPUT
  sed -i 's/pause:3../pause:3.9/' /etc/containerd/config.toml $SUPRESS_OUTPUT
  systemctl restart containerd $SUPRESS_OUTPUT

  # import container image
  ctr images import container/images.tar

  # cleanup
  rm -rf deb/ container/
fi