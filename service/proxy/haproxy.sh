#!/bin/bash

NAME="haproxy"
VERSION="0.1.0"

############################################################
# status service
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
# start service
if [ "$1" = "start" ] ; then
  /usr/bin/ctr container list --quiet | grep haproxy
  if [ $? -eq 0 ] ; then
    /usr/bin/ctr task kill haproxy
    /usr/bin/ctr container remove haproxy
  fi
  /usr/bin/ctr run \
    --net-host \
    --detach \
    --mount type=bind,src=/usr/local/etc/haproxy,dst=/usr/local/etc/haproxy,options=rbind:ro \
    docker.io/library/haproxy:2.9-alpine haproxy
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
    Description=haproxy service
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
  EOL_HAPROXY_CONFIG

  COUNT=1
  echo "Enter IP Addresses for all registries (empty input when done):"
  while : ; do
    IP_ADDRESS=$(gum input --placeholder "IP Address")
    [[ -z "$IP_ADDRESS" ]] && break
    echo "  server controlplane$COUNT $IP_ADDRESS:5000 check  inter 10s  fall 5  rise 5" >> /usr/local/etc/haproxy/haproxy.cfg
    COUNT+=1
  done

  cp $0 /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable haproxy --now
fi

############################################################
# remove service
if [ "$1" = "remove" ] ; then
  systemctl disable haproxy --now
  rm -f /etc/systemd/system/haproxy.service
  rm -f /etc/systemd/system/haproxy.sh
  systemctl daemon-reload
fi

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

  wget https://github.com/charmbracelet/gum/releases/download/v0.11.0/gum_0.11.0_amd64.deb -P deb

  mkdir -p container

  ctr image pull docker.io/library/haproxy:2.9-alpine --platform amd64
  ctr images export container/images.tar docker.io/library/haproxy:2.9-alpine --platform amd64
  
  TAR_FILE="$NAME-$VERSION.tgz"
  SELF_EXTRACTABLE="$TAR_FILE.self"

  echo "Be patient creating self extracting archive ..."
  # pack and create self extracting archive
  tar -czf $TAR_FILE  haproxy.sh deb/ container/

  echo '#!/bin/bash' > $SELF_EXTRACTABLE
  echo 'echo Extract archive ...' >> $SELF_EXTRACTABLE
  echo -n 'dd bs=`head -5 $0 | wc -c` skip=1 if=$0 ' >> $SELF_EXTRACTABLE
  echo -n "2>/dev/null" >> $SELF_EXTRACTABLE
  echo ' | gunzip -c | tar -x' >> $SELF_EXTRACTABLE
  echo 'exec ./haproxy.sh setup' >> $SELF_EXTRACTABLE
  echo '######################################################################' >> $SELF_EXTRACTABLE

  cat $TAR_FILE >> $SELF_EXTRACTABLE
  chmod a+x $SELF_EXTRACTABLE
  rm -rf $TAR_FILE deb/ container/
fi

############################################################
# setup package
if [ "$1" = "setup" ] ; then

  dpkg --install deb/gum_0.11.0_amd64.deb 2>&1>/dev/null

  # install containerd
  PACKAGES=$(find deb -name "*.deb")
  gum spin --title "Install packages ..." -- dpkg --install $PACKAGES
  echo "Install packages ..."

  containerd config default | tee /etc/containerd/config.toml 2>&1>/dev/null
  sed -i 's/pause:3../pause:3.9/' /etc/containerd/config.toml 2>&1>/dev/null
  systemctl restart containerd 2>&1>/dev/null

  # import container image
  gum spin --title "Import container images ..." -- ctr images import container/images.tar --platform amd64
  echo "Import container images ..."

  # add haproxy service
  echo "Add service haproxy ..."
  ./haproxy.sh add

  # cleanup
  rm -rf deb/ container/ haproxy.sh
fi