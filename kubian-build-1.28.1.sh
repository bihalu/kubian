#!/bin/bash

NAME="kubian-setup"
VERSION="1.28.1"
POD_NETWORK_CIDR="10.244.0.0/16"
SVC_NETWORK_CIDR="10.96.0.0/12"
EMAIL="john.doe@inter.net"
BUILD_START=$(date +%s)
INSTALLED_PACKAGES=$(dpkg -l | sed '/^ii/!d' | tr -s ' ' | cut -d ' ' -f 2,3,4)

# install aptitude apt-transport-https curl gpg
apt install -y aptitude apt-transport-https curl gpg

# add kubernetes repository and import google gpg key
tee /etc/apt/sources.list.d/kubernetes.list <<KUBERNETES_REPO_EOF
deb http://apt.kubernetes.io/ kubernetes-xenial main
# deb-src http://apt.kubernetes.io/ kubernetes-xenial main
KUBERNETES_REPO_EOF

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmour -o /etc/apt/trusted.gpg.d/cgoogle.gpg

# install nerdctl full (with containerd)
nerdctl version 2>&1 > /dev/null
if [[ $? != 0 ]] ; then
  wget https://github.com/containerd/nerdctl/releases/download/v1.5.0/nerdctl-full-1.5.0-linux-amd64.tar.gz -O - | tar xzf - -C /usr/local
  systemctl enable containerd --now
fi

# install helm
helm version 2>&1 > /dev/null
if [[ $? != 0 ]] ; then
  wget https://get.helm.sh/helm-v3.12.3-linux-amd64.tar.gz -O - | tar xzf - && cp linux-amd64/helm /usr/local/bin/
fi

################################################################################
# deb packages for airgap installation -> https://packages.debian.org
readarray -t PACKAGES <<EOL_PACKAGES
# iptables
iptables 1.8.9-2 amd64
libip6tc2:amd64 1.8.9-2 amd64
libnetfilter-conntrack3:amd64 1.0.9-3 amd64
libnfnetlink0:amd64 1.0.2-2 amd64
# ebtables 
ebtables 2.0.11-5 amd64
# jq
jq 1.6-2.1 amd64
libjq1:amd64 1.6-2.1 amd64
libonig5:amd64 6.9.8-1 amd64
# curl
curl 7.88.1-10+deb12u1 amd64
libcurl4:amd64 7.88.1-10+deb12u1 amd64
# ethtool (replace colon with %3a in filename)
ethtool 1%3a6.1-1 amd64
# socat
socat 1.7.4.4-2 amd64
# conntrack (replace colon with %3a in filename)
conntrack 1%3a1.4.7-1+b2 amd64
# cri-tools
cri-tools 1.26.0-00 amd64
# kubernetes
kubeadm 1.28.1-00 amd64
kubectl 1.28.1-00 amd64
kubelet 1.28.1-00 amd64
kubernetes-cni 1.2.0-00 amd64
EOL_PACKAGES

mkdir -p deb/

aptitude clean

SKIP_PACKAGES=0

for PACKAGE in "${PACKAGES[@]}" ; do
  # don't process commented out packages
  [[ ${PACKAGE:0:1} = \# ]] && continue

  # skip packages
  [[ ${SKIP_PACKAGES} -gt 0 ]] && ((SKIP_PACKAGES--)) && continue

  # parse package data
  PACKAGE_DATA=($PACKAGE)
  PACKAGE_NAME="${PACKAGE_DATA[0]%:amd64}"
  PACKAGE_VERSION="${PACKAGE_DATA[1]}"
  PACKAGE_ARCH="${PACKAGE_DATA[2]}"
  PACKAGE_FILE="${PACKAGE_NAME}_${PACKAGE_VERSION}_${PACKAGE_ARCH}.deb"

  # skip download if already available
  [[ -f deb/${PACKAGE_FILE} ]] && continue

  # download package
  aptitude --download-only install -y $PACKAGE_NAME
  cp /var/cache/apt/archives/${PACKAGE_FILE} deb/
  if [[ $? != 0 ]] ; then
    # aptitude will not download if package is installed, try download reinstall
    aptitude --download-only reinstall $PACKAGE_NAME
    cp /var/cache/apt/archives/${PACKAGE_FILE} deb/
    [[ $? != 0 ]] && exit 1
  fi 
done

################################################################################
# container images for airgap installation
readarray -t IMAGES <<EOL_IMAGES
################################################################################
# kube-prometheus-stack v0.67.1 -> https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack/50.3.1
quay.io/prometheus/node-exporter:v1.6.1
quay.io/kiwigrid/k8s-sidecar:1.24.6
docker.io/grafana/grafana:10.1.1
registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.0
quay.io/prometheus-operator/prometheus-operator:v0.67.1
quay.io/prometheus/alertmanager:v0.26.0
quay.io/prometheus/prometheus:v2.46.0
################################################################################
# openebs 3.9.0 -> https://artifacthub.io/packages/helm/openebs/openebs/3.9.0
docker.io/openebs/node-disk-manager:2.1.0
docker.io/openebs/provisioner-localpv:3.4.0
docker.io/openebs/node-disk-operator:2.1.0
docker.io/openebs/node-disk-exporter:2.1.0
docker.io/openebs/linux-utils:3.4.0
################################################################################
# cert-manager 1.12.4 -> https://artifacthub.io/packages/helm/cert-manager/cert-manager/1.12.4
quay.io/jetstack/cert-manager-cainjector:v1.12.4
quay.io/jetstack/cert-manager-controller:v1.12.4
quay.io/jetstack/cert-manager-webhook:v1.12.4
quay.io/jetstack/cert-manager-acmesolver:v1.12.4
quay.io/jetstack/cert-manager-ctl:v1.12.4
quay.io/jetstack/cert-manager-webhook:v1.12.4
################################################################################
# ingress-nginx v1.8.1 -> https://github.com/kubernetes/ingress-nginx/blob/helm-chart-4.7.1/charts/ingress-nginx/values.yaml#L26
registry.k8s.io/ingress-nginx/controller:v1.8.1
registry.k8s.io/ingress-nginx/opentelemetry:v20230527
registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20230407
registry.k8s.io/defaultbackend-amd64:1.5
################################################################################
# calico v3.26.1 -> https://artifacthub.io/packages/helm/projectcalico/tigera-operator/3.26.1
quay.io/tigera/operator:v1.30.4
docker.io/calico/apiserver:v3.26.1
docker.io/calico/cni:v3.26.1
docker.io/calico/csi:v3.26.1
docker.io/calico/kube-controllers:v3.26.1
docker.io/calico/node-driver-registrar:v3.26.1
docker.io/calico/node:v3.26.1
docker.io/calico/pod2daemon-flexvol:v3.26.1
docker.io/calico/typha:v3.26.1
################################################################################
# k8s 1.28.1 -> https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.28.md#container-images
registry.k8s.io/kube-apiserver:v1.28.1
registry.k8s.io/kube-controller-manager:v1.28.1
registry.k8s.io/kube-proxy:v1.28.1
registry.k8s.io/kube-scheduler:v1.28.1
registry.k8s.io/coredns/coredns:v1.10.1
registry.k8s.io/etcd:3.5.9-0
registry.k8s.io/pause:3.9
EOL_IMAGES

SKIP_IMAGES=0
PULL=true
CONTAINER_IMAGES=""

for IMAGE in "${IMAGES[@]}" ; do
  # don't process commented out images
  [[ ${IMAGE:0:1} = \# ]] && continue

  # skip images
  [[ ${SKIP_IMAGES} -gt 0 ]] && ((SKIP_IMAGES--)) && continue

  # pull image
  if [[ ${PULL} = true ]] ; then
    ctr image pull ${IMAGE}

    # exit on install error
    [[ $? != 0 ]] && echo "can't pull image with nerdctl" && exit 1

  fi

  CONTAINER_IMAGES+=" "
  CONTAINER_IMAGES+=${IMAGE}
done

SAVE=true

if [[ ${SAVE} = true ]] ; then
  # save images as tar file
  mkdir -p container

  # cleanup container images tar file
  [[ -f container/images.tar ]] && rm -f container/images.tar

  # save all images in container images tar file
  echo "Be patient saving container images ..."
  nerdctl save --output container/images.tar ${CONTAINER_IMAGES}
fi

################################################################################
# helm charts -> chart_url chart_repo chart_name chart_version
readarray -t HELM_CHARTS <<EOL_HELM_CHARTS
https://prometheus-community.github.io/helm-charts prometheus-community kube-prometheus-stack 50.3.1
https://openebs.github.io/charts openebs openebs 3.9.0
https://charts.jetstack.io jetstack cert-manager v1.12.4
https://kubernetes.github.io/ingress-nginx ingress-nginx ingress-nginx 4.7.1
https://projectcalico.docs.tigera.io/charts projectcalico tigera-operator v3.26.1
EOL_HELM_CHARTS

SKIP_CHARTS=0

mkdir -p helm/

for CHART in "${HELM_CHARTS[@]}" ; do
  # don't process commented out helm charts
  [[ ${CHART:0:1} = \# ]] && continue

  # skip helm charts
  [[ ${SKIP_CHARTS} -gt 0 ]] && ((SKIP_CHARTS--)) && continue

  # parse chart data
  CHART_DATA=($CHART)
  CHART_URL="${CHART_DATA[0]}"
  CHART_REPO="${CHART_DATA[1]}"
  CHART_NAME="${CHART_DATA[2]}"
  CHART_VERSION="${CHART_DATA[3]}"

  # continue if helmchart exists
  [[ -f helm/${CHART_NAME}/${CHART_NAME}-${CHART_VERSION}.tgz ]] && continue

  # add helm repo
  helm repo add ${CHART_REPO} ${CHART_URL} 

  # create folder for helm chart
  mkdir -p helm/${CHART_NAME}/

  # pull helm chart
  helm pull ${CHART_REPO}/${CHART_NAME} --version ${CHART_VERSION}

  # exit on pull error
  [[ $? != 0 ]] && exit 1

  # move helmchart to folder
  mv ${CHART_NAME}-${CHART_VERSION}.tgz helm/${CHART_NAME}/
done

################################################################################
# additional artefacts
mkdir -p artefact

# download kubeadm, kubectl and kubelet v1.28.1 -> https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.28.md#client-binaries
# if [[ -f artefact/kubernetes-node-linux-amd64.tar.gz ]] ; then
#   echo "file exists artefact/kubernetes-node-linux-amd64.tar.gz" 
# else
#   wget https://dl.k8s.io/v1.28.1/kubernetes-node-linux-amd64.tar.gz -P artefact
# fi

# download nerdctl-full v1.5.0 -> https://github.com/containerd/nerdctl/releases/tag/v1.5.0
if [[ -f artefact/nerdctl-full-1.5.0-linux-amd64.tar.gz ]] ; then
  echo "file exists artefact/nerdctl-full-1.5.0-linux-amd64.tar.gz" 
else
  wget https://github.com/containerd/nerdctl/releases/download/v1.5.0/nerdctl-full-1.5.0-linux-amd64.tar.gz -P artefact
fi
 
# download helm v3.12.3 -> https://github.com/helm/helm/releases/tag/v3.12.3
if [[ -f artefact/helm-v3.12.3-linux-amd64.tar.gz ]] ; then
  echo "file exists artefact/helm-v3.12.3-linux-amd64.tar.gz" 
else
  wget https://get.helm.sh/helm-v3.12.3-linux-amd64.tar.gz -P artefact
fi

# download calico cni-plugin v3.20.6 -> calico
if [[ -f artefact/calico ]] ; then
  echo "file exists artefact/calico" 
else
  wget https://github.com/projectcalico/cni-plugin/releases/download/v3.20.6/calico-amd64 -O artefact/calico
fi

if [[ -f artefact/calico-ipam ]] ; then
  echo "file exists artefact/calico-ipam" 
else
  wget https://github.com/projectcalico/cni-plugin/releases/download/v3.20.6/calico-ipam-amd64 -O artefact/calico-ipam
fi

# issuer for cert-manager (letsencrypt) -> issuer-letsencrypt.yaml
tee artefact/issuer-letsencrypt.yaml <<EOF_ISSUER
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
  namespace: cert-manager
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - http01:
          ingress:
            class: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
       ingress:
         class: nginx
EOF_ISSUER

# prometheus values -> prom_values.yaml
tee artefact/prom_values.yaml <<EOF_PROM_VALUES
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
EOF_PROM_VALUES

################################################################################
# create setup.sh
tee setup.sh <<EOF_SETUP
#!/bin/bash

SETUP_START=\$(date +%s)

################################################################################
# specific setup routines for:
# - init cluster
# - init single
# - join controlplane
# - join worker
# - upgrade 
# - delete
echo "setup \$1 \$2 \$3"

INIT=false
JOIN=false
UPGRADE=false
DELETE=false

[ "\$1" = init ] && INIT=true
[ "\$1" = join ] && JOIN=true
[ "\$1" = upgrade ] && UPGRADE=true
[ "\$1" = delete ] && DELETE=true

CLUSTER=false
SINGLE=false
CONTROLPLANE=false
WORKER=false

[ "\$2" = cluster ] && CLUSTER=true
[ "\$2" = single ] && SINGLE=true
[ "\$2" = controlplane ] && CONTROLPLANE=true
[ "\$2" = worker ] && WORKER=true

################################################################################
# airgap no repos
#echo "# airgap no repos" > /etc/apk/repositories

################################################################################
# add kernel module for networking stuff
tee /etc/modules-load.d/k8s.conf <<EOF_MODULES
overlay
br_netfilter
EOF_MODULES

modprobe overlay
modprobe br_netfilter

tee /etc/sysctl.d/kubernetes.conf <<EOF_SYSCTL
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF_SYSCTL

sysctl --system

################################################################################
# disable swap
sed -ie '/swap/ s/^/#/' /etc/fstab
swapoff -a

################################################################################
# install packages
PACKAGES=\$(find deb -name "*.deb")
dpkg --install \$PACKAGES

################################################################################
# install nerdctl and containerd
tar Cxzvf /usr/local artefact/nerdctl-full-1.5.0-linux-amd64.tar.gz

################################################################################
# install kubeadm, kubectl and kubelet
#tar Cxzvf /tmp artefact/kubernetes-node-linux-amd64.tar.gz && mv /tmp/kubernetes/node/bin/* /usr/local/bin/

################################################################################
# install helm
tar Cxzvf /tmp artefact/helm-v3.12.3-linux-amd64.tar.gz && cp /tmp/kubernetes/node/bin/* /usr/local/bin/

################################################################################
# install calico cni-plugins
cp artefact/calico /usr/local/libexec/cni/ && chmod 755 /usr/local/libexec/cni/calico
cp artefact/calico-ipam /usr/local/libexec/cni/ && chmod 755 /usr/local/libexec/cni/calico-ipam

################################################################################
# enable services and start container runtime
systemctl enable kubelet
systemctl enable containerd --now

# fix pause container use same version as kubernetes
#sed -i 's/pause:3.8/pause:3.9/' /etc/containerd/config.toml
#/etc/init.d/containerd start && sleep 5

################################################################################
# import container images
echo "Be patient import container images ..."
nerdctl load --namespace k8s.io --input container/images.tar

################################################################################
# init
if [ \$INIT = true ] ; then
  echo "init kubernetes cluster ..."

  ################################################################################
  # init cluster
  CONTROL_PLANE_ENDPOINT=\$(ip -brief address show eth0 | awk '{print \$3}' | awk -F/ '{print \$1}')
  kubeadm init \
    --upload-certs \
    --node-name=\$HOSTNAME \
    --pod-network-cidr=$POD_NETWORK_CIDR \
    --service-cidr=$SVC_NETWORK_CIDR \
    --kubernetes-version=$VERSION \
    --control-plane-endpoint=\$CONTROL_PLANE_ENDPOINT
  [ \$? != 0 ] && echo "error: can't initialize cluster" && exit 1


  ################################################################################
  # copy kube config
  mkdir ~/.kube
  ln -s /etc/kubernetes/admin.conf ~/.kube/config
fi

################################################################################
# cluster
if [ \$CLUSTER = true ] ; then
  echo "init cluster settings"

  ################################################################################
  # install projectcalico tigera-operator v3.26.1
  helm upgrade --install tigera-operator helm/tigera-operator/tigera-operator-v3.26.1.tgz \
    --create-namespace \
    --namespace tigera-operator \
    --version v3.26.1
  if [ \$? != 0 ] ; then
    # give grace period of 2 minutes to get node ready
    kubectl wait --timeout=2m --for=condition=Ready node/\$HOSTNAME
    [ \$? != 0 ] && echo "error: can't initialize cluster" && exit 1
  fi
fi

################################################################################
# single
if [ \$SINGLE = true ] ; then
  echo "single node cluster settings"

  ################################################################################
  # remove no schedule taint for control plane
  kubectl taint nodes \$HOSTNAME node-role.kubernetes.io/control-plane=:NoSchedule-

  ################################################################################
  # install projectcalico tigera-operator v3.26.1
  helm upgrade --install tigera-operator helm/tigera-operator/tigera-operator-v3.26.1.tgz \
    --create-namespace \
    --namespace tigera-operator \
    --version v3.26.1
  if [ \$? != 0 ] ; then
    # give grace period of 2 minutes to get node ready
    kubectl wait --timeout=2m --for=condition=Ready node/\$HOSTNAME
    [ \$? != 0 ] && echo "error: can't initialize cluster" && exit 1
  fi

  ################################################################################
  # install openebs openebs 3.9.0
  helm upgrade --install openebs helm/openebs/openebs-3.9.0.tgz \
    --create-namespace \
    --namespace openebs \
    --version 3.9.0

  # set default storage class
  kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

  ################################################################################
  # install ingress-nginx controller
  helm upgrade --install ingress-nginx helm/ingress-nginx/ingress-nginx-4.7.1.tgz \
    --create-namespace \
    --namespace ingress-nginx \
    --version 4.7.1 \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=30080 \
    --set controller.service.nodePorts.https=30443

  ################################################################################
  # install cert-manager
  helm upgrade --install cert-manager helm/cert-manager/cert-manager-v1.12.4.tgz \
    --create-namespace \
    --namespace cert-manager \
    --version v1.12.4 \
    --set installCRDs=true

  kubectl apply -f artefact/issuer-letsencrypt.yaml

  ################################################################################
  # alertmanager, prometheus and grafana 
  helm upgrade --install kube-prometheus-stack helm/kube-prometheus-stack/kube-prometheus-stack-50.3.1.tgz \
    --create-namespace \
    --namespace kube-prometheus-stack \
    --version 50.3.1 \
    --set alertmanager.service.type=NodePort \
    --set prometheus.service.type=NodePort \
    --set grafana.service.type=NodePort \
    --set grafana.service.nodePort=30303 \
    --values artefact/prom_values.yaml

  ################################################################################
  # patch metrics endpoints for controller-manager, scheduler and etcd
  sed -e "s/- --bind-address=127.0.0.1/- --bind-address=0.0.0.0/" -i /etc/kubernetes/manifests/kube-controller-manager.yaml
  sed -e "s/- --bind-address=127.0.0.1/- --bind-address=0.0.0.0/" -i /etc/kubernetes/manifests/kube-scheduler.yaml
  sed -e "s/- --listen-metrics-urls=http:\/\/127.0.0.1/- --listen-metrics-urls=http:\/\/0.0.0.0/" -i /etc/kubernetes/manifests/etcd.yaml
fi

################################################################################
# join worker
if [ \$JOIN = true ] && [ \$WORKER = true ] ; then
  ssh -oBatchMode=yes -q \$3 exit
  if [ \$? = 0 ] ; then
    mkdir -p ~/.kube
    scp \$3:~/.kube/config ~/.kube/config
    JOIN_WORKER=\$(ssh -oBatchMode=yes \$3 kubeadm token create --print-join-command)
    eval \$JOIN_WORKER
  else
    echo "error: can't connect to \$3 via ssh"
    exit 1
  fi

  ################################################################################
  # TODO storage openebs mayastore

  ################################################################################
  # install ingress-nginx controller
  helm upgrade --install ingress-nginx helm/ingress-nginx/ingress-nginx-4.7.1.tgz \
    --create-namespace \
    --namespace ingress-nginx \
    --version 4.7.1 \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=30080 \
    --set controller.service.nodePorts.https=30443

  ################################################################################
  # install cert-manager
  helm upgrade --install cert-manager helm/cert-manager/cert-manager-v1.12.4.tgz \
    --create-namespace \
    --namespace cert-manager \
    --version v1.12.4 \
    --set installCRDs=true

  kubectl apply -f artefact/issuer-letsencrypt.yaml
fi

################################################################################
# join controlplane
if [ \$JOIN = true ] && [ \$CONTROLPLANE = true ] ; then
  ssh -oBatchMode=yes -q \$3 exit
  if [ \$? = 0 ] ; then
    mkdir -p ~/.kube
    scp \$3:~/.kube/config ~/.kube/config
    CERTIFICATE_KEY=\$(ssh -oBatchMode=yes \$3 kubeadm init phase upload-certs --upload-certs | tail -1)
    JOIN_CONTROLPLANE=\$(ssh -oBatchMode=yes \$3 kubeadm token create --print-join-command --certificate-key \$CERTIFICATE_KEY)
    eval \$JOIN_CONTROLPLANE
  else
    echo "error: can't connect to \$3 via ssh"
    exit 1
  fi
fi

################################################################################
# upgrade
if [ \$UPGRADE = true ] ; then
  echo "upgrade not implemented"
fi

################################################################################
# delete
if [ \$DELETE = true ] ; then
  echo "delete not implemented"
fi

################################################################################
# cleanup
#rm -rf setup.sh deb/ container/ artefact/ helm/  

################################################################################
# finish
SETUP_END=\$(date +%s)
SETUP_MINUTES=\$(((\$SETUP_END - \$SETUP_START) / 60))
SETUP_SECONDS=\$((\$SETUP_END - \$SETUP_START - (\$SETUP_MINUTES * 60)))

echo "setup took \$SETUP_MINUTES minutes \$SETUP_SECONDS seconds"
EOF_SETUP

chmod +x setup.sh

################################################################################
# create self extracting archive
TAR_FILE="${NAME}-${VERSION}.tgz"
SELF_EXTRACTABLE="$TAR_FILE.self"
PACK=true

if [[ ${PACK} = true ]] ; then
  echo "Be patient creating self extracting archive ..."
  # pack and create self extracting archive
  tar -czf ${TAR_FILE}  setup.sh deb/ container/ artefact/ helm/

  echo '#!/bin/sh' > $SELF_EXTRACTABLE
  echo 'echo Be patient extracting archive ...' >> $SELF_EXTRACTABLE
  echo 'dd bs=`head -5 $0 | wc -c` skip=1 if=$0 | gunzip -c | tar -x' >> $SELF_EXTRACTABLE
  echo 'exec ./setup.sh $1 $2 $3' >> $SELF_EXTRACTABLE
  echo '######################################################################' >> $SELF_EXTRACTABLE

  cat $TAR_FILE >> $SELF_EXTRACTABLE
  chmod a+x $SELF_EXTRACTABLE
fi

################################################################################
# cleanup
CLEANUP=false

if [[ ${CLEANUP} = true ]] ; then
  rm -rf $TAR_FILE setup.sh deb/ container/ artefact/ helm/
fi

################################################################################
# finish
BUILD_END=$(date +%s)
BUILD_MINUTES=$((($BUILD_END - $BUILD_START) / 60))
BUILD_SECONDS=$(($BUILD_END - $BUILD_START - ($BUILD_MINUTES * 60)))

echo "build $SELF_EXTRACTABLE took $BUILD_MINUTES minutes $BUILD_SECONDS seconds"
