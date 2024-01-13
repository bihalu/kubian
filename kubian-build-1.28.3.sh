#!/bin/bash

NAME="kubian-setup"
VERSION="1.28.3"
POD_NETWORK_CIDR="10.79.0.0/16"
SVC_NETWORK_CIDR="10.80.0.0/12"
CLUSTER_NAME="kubian"
EMAIL="john.doe@inter.net"
BUILD_START=$(date +%s)

################################################################################
# install aptitude apt-transport-https gpg wget
apt install -y aptitude apt-transport-https gpg wget

################################################################################
# add kubernetes community package repository and import gpg key
tee /etc/apt/sources.list.d/kubernetes.list <<EOL_KUBERNETES_REPO
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /
EOL_KUBERNETES_REPO

wget https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key -O - | gpg --batch --yes --dearmor --output /etc/apt/keyrings/kubernetes-apt-keyring.gpg

apt update

################################################################################
# install containerd
apt install -y containerd

# configure containerd
containerd config default | tee /etc/containerd/config.toml

# fix config pause container (use same version as kubernetes)
sed -i 's/pause:3../pause:3.9/' /etc/containerd/config.toml

# fix systemd cgroup (use cgroup v1)
#sed -i 's/systemd_cgroup = true/systemd_cgroup = false/' /etc/containerd/config.toml

systemctl restart containerd
if [ $? != 0 ] ; then
  echo "No systemd, I think we are on WSL -> start containerd as background process ..."
  containerd &
fi

################################################################################
# install helm
which helm
if [ $? != 0 ] ; then
  wget https://get.helm.sh/helm-v3.13.3-linux-amd64.tar.gz -O - | tar Cxzf /tmp - && cp /tmp/linux-amd64/helm /usr/local/bin/
fi

################################################################################
# install yq
which yq
if [ $? != 0 ] ; then
  wget https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64 -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq
fi

################################################################################
# deb packages for airgap installation -> https://packages.debian.org
# installed packages -> dpkg -l | sed '/^ii/!d' | tr -s ' ' | cut -d ' ' -f 2,3,4
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
curl 7.88.1-10+deb12u4 amd64
libcurl4:amd64 7.88.1-10+deb12u4 amd64
# ethtool
ethtool 1:6.1-1 amd64
# socat
socat 1.7.4.4-2 amd64
# conntrack
conntrack 1:1.4.7-1+b2 amd64
# cri-tools
cri-tools 1.28.0-1.1 amd64
# kubernetes
kubeadm 1.28.3-1.1 amd64
kubectl 1.28.3-1.1 amd64
kubelet 1.28.3-1.1 amd64
kubernetes-cni 1.2.0-2.1 amd64
# containerd
containerd 1.6.20~ds1-1+b1 amd64
criu 3.17.1-2 amd64
libnet1:amd64 1.1.6+dfsg-3.2 amd64
libnl-3-200:amd64 3.7.0-0.2+b1 amd64
libprotobuf32:amd64 3.21.12-3 amd64
python3-protobuf 3.21.12-3 amd64
runc 1.1.5+ds1-1+b1 amd64
sgml-base 1.31 all
# gpg
dirmngr 2.2.40-1.1 amd64
gnupg 2.2.40-1.1 all
gnupg-l10n 2.2.40-1.1 all
gnupg-utils 2.2.40-1.1 amd64
gpg 2.2.40-1.1 amd64
gpg-agent 2.2.40-1.1 amd64
gpg-wks-client 2.2.40-1.1 amd64
gpg-wks-server 2.2.40-1.1 amd64
gpgconf 2.2.40-1.1 amd64
gpgsm 2.2.40-1.1 amd64
libassuan0:amd64 2.5.5-5 amd64
libksba8:amd64 1.6.3-2 amd64
libnpth0:amd64 1.6-3 amd64
pinentry-curses 1.2.1-1 amd64
# open-iscsi
libisns0:amd64 0.101-0.2+b1 amd64
libopeniscsiusr 2.1.8-1 amd64
open-iscsi 2.1.8-1 amd64
# wireguard
wireguard 1.0.20210914-1 all
wireguard-tools 1.0.20210914-1+b1 amd64
EOL_PACKAGES

mkdir -p deb

aptitude clean

for PACKAGE in "${PACKAGES[@]}" ; do
  # don't process commented out packages
  [ ${PACKAGE:0:1} = \# ] && continue

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

################################################################################
# download gum package -> https://github.com/charmbracelet/gum
wget https://github.com/charmbracelet/gum/releases/download/v0.11.0/gum_0.11.0_amd64.deb -P deb

################################################################################
# container images for airgap installation
# ctr -n k8s.io images list -q
readarray -t IMAGES <<EOL_IMAGES
################################################################################
# kube-prometheus-stack v0.69.1 -> https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack/54.2.2
quay.io/prometheus/node-exporter:v1.7.0
quay.io/kiwigrid/k8s-sidecar:1.25.2
docker.io/grafana/grafana:10.1.5
registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.1
quay.io/prometheus-operator/prometheus-operator:v0.69.1
quay.io/prometheus/alertmanager:v0.26.0
quay.io/prometheus/prometheus:v2.48.0
################################################################################
# openebs 3.9.0 -> https://artifacthub.io/packages/helm/openebs/openebs/3.9.0
docker.io/openebs/node-disk-manager:2.1.0
docker.io/openebs/provisioner-localpv:3.4.0
docker.io/openebs/node-disk-operator:2.1.0
docker.io/openebs/node-disk-exporter:2.1.0
docker.io/openebs/linux-utils:3.4.0
################################################################################
# cert-manager 1.13.2 -> https://artifacthub.io/packages/helm/cert-manager/cert-manager/1.13.2
quay.io/jetstack/cert-manager-cainjector:v1.13.2
quay.io/jetstack/cert-manager-controller:v1.13.2
quay.io/jetstack/cert-manager-webhook:v1.13.2
quay.io/jetstack/cert-manager-acmesolver:v1.13.2
quay.io/jetstack/cert-manager-ctl:v1.13.2
quay.io/jetstack/cert-manager-webhook:v1.13.2
################################################################################
# ingress-nginx v1.9.4 -> https://github.com/kubernetes/ingress-nginx/blob/helm-chart-4.8.3/charts/ingress-nginx/values.yaml#L26
registry.k8s.io/ingress-nginx/controller:v1.9.4
registry.k8s.io/ingress-nginx/opentelemetry:v20230721-3e2062ee5
registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20231011-8b53cabe0
registry.k8s.io/defaultbackend-amd64:1.5
################################################################################
# metrics-server v0.6.4 -> https://artifacthub.io/packages/helm/metrics-server/metrics-server/3.11.0
registry.k8s.io/metrics-server/metrics-server:v0.6.4
################################################################################
# calico v3.26.4 -> https://artifacthub.io/packages/helm/projectcalico/tigera-operator/3.26.4
quay.io/tigera/operator:v1.30.9
docker.io/calico/apiserver:v3.26.4
docker.io/calico/cni:v3.26.4
docker.io/calico/csi:v3.26.4
docker.io/calico/kube-controllers:v3.26.4
docker.io/calico/node-driver-registrar:v3.26.4
docker.io/calico/node:v3.26.4
docker.io/calico/pod2daemon-flexvol:v3.26.4
docker.io/calico/typha:v3.26.4
################################################################################
# k8s 1.28.3 -> https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.28.md#container-images
registry.k8s.io/kube-apiserver:v1.28.3
registry.k8s.io/kube-controller-manager:v1.28.3
registry.k8s.io/kube-proxy:v1.28.3
registry.k8s.io/kube-scheduler:v1.28.3
registry.k8s.io/coredns/coredns:v1.10.1
registry.k8s.io/etcd:3.5.9-0
registry.k8s.io/pause:3.9
################################################################################
# velero -> https://github.com/vmware-tanzu/velero
docker.io/velero/velero:v1.12.0
docker.io/velero/velero-plugin-for-aws:v1.8.0
EOL_IMAGES

CONTAINER_IMAGES=""

for IMAGE in "${IMAGES[@]}" ; do
  # don't process commented out images
  [ ${IMAGE:0:1} = \# ] && continue

  ctr image pull $IMAGE

  # exit on pull error
  [ $? != 0 ] && echo "ERROR: can't pull image" && exit 1

  CONTAINER_IMAGES+=" "
  CONTAINER_IMAGES+=$IMAGE
done

# create folder for container images
mkdir -p container

# cleanup container images tar file
[ -f container/images.tar ] && rm -f container/images.tar

# export all container images to images.tar 
echo "Be patient exporting container images ..."
ctr images export container/images.tar $CONTAINER_IMAGES

################################################################################
# helm charts -> chart_url chart_repo chart_name chart_version
readarray -t HELM_CHARTS <<EOL_HELM_CHARTS
https://prometheus-community.github.io/helm-charts prometheus-community kube-prometheus-stack 54.2.2
https://openebs.github.io/charts openebs openebs 3.9.0
https://charts.jetstack.io jetstack cert-manager v1.13.2
https://kubernetes.github.io/ingress-nginx ingress-nginx ingress-nginx 4.8.3
https://projectcalico.docs.tigera.io/charts projectcalico tigera-operator v3.26.4
https://kubernetes-sigs.github.io/metrics-server metrics-server metrics-server 3.11.0
EOL_HELM_CHARTS

mkdir -p helm

for CHART in "${HELM_CHARTS[@]}" ; do
  # don't process commented out helm charts
  [ ${CHART:0:1} = \# ] && continue

  # parse chart data
  CHART_DATA=($CHART)
  CHART_URL="${CHART_DATA[0]}"
  CHART_REPO="${CHART_DATA[1]}"
  CHART_NAME="${CHART_DATA[2]}"
  CHART_VERSION="${CHART_DATA[3]}"

  # continue if helmchart exists
  [ -f helm/$CHART_NAME-$CHART_VERSION.tgz ] && continue

  # add helm repo
  helm repo add $CHART_REPO $CHART_URL 

  # pull helm chart
  helm pull $CHART_REPO/$CHART_NAME --version $CHART_VERSION --destination helm/

  # exit on pull error
  [ $? != 0 ] && echo "ERROR: can't pull helm chart" && exit 1
done

################################################################################
# additional artefacts
mkdir -p artefact

# download helm v3.13.2 -> https://github.com/helm/helm/releases/tag/v3.13.2
if [ -f artefact/helm-v3.13.3-linux-amd64.tar.gz ] ; then
  echo "file exists artefact/helm-v3.13.3-linux-amd64.tar.gz" 
else
  wget https://get.helm.sh/helm-v3.13.3-linux-amd64.tar.gz -P artefact
fi

# download k9s v0.28.2 -> https://github.com/derailed/k9s/releases/tag/v0.28.2
if [ -f artefact/k9s_Linux_amd64.tar.gz ] ; then
  echo "file exists artefact/k9s_Linux_amd64.tar.gz" 
else
  wget https://github.com/derailed/k9s/releases/download/v0.28.2/k9s_Linux_amd64.tar.gz -P artefact
fi

# download velero -> https://github.com/vmware-tanzu/velero/releases/tag/v1.12.0
if [ -f artefact/velero-v1.12.0-linux-amd64.tar.gz ] ; then
  echo "file exists artefact/velero-v1.12.0-linux-amd64.tar.gz" 
else
  wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz -P artefact
fi

# download calico cni-plugin v3.20.6 -> https://github.com/projectcalico/cni-plugin/releases/
if [ -f artefact/calico ] ; then
  echo "file exists artefact/calico" 
else
  wget https://github.com/projectcalico/cni-plugin/releases/download/v3.20.6/calico-amd64 -O artefact/calico
fi

# download yq -> https://github.com/mikefarah/yq/releases
if [ -f artefact/yq ] ; then
  echo "file exists artefact/yq" 
else
  wget https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64 -O artefact/yq
fi

# issuer for cert-manager (letsencrypt) -> issuer-letsencrypt.yaml
tee artefact/issuer-letsencrypt.yaml <<EOL_ISSUER
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
EOL_ISSUER

# autogenerate grafana admin password -> grafana_secret.yaml
GRAFANA_ADMIN_PASSWORD=$(echo -n `openssl rand -base64 16` | base64)

tee artefact/grafana-secret.yaml <<EOL_GRAFANA_SECRET
apiVersion: v1
kind: Secret
metadata:
  name: "grafana-secret"
  namespace: monitoring
type: Opaque
data:
   admin-password: $GRAFANA_ADMIN_PASSWORD
   admin-user: YWRtaW4=
   ldap-toml: ""
EOL_GRAFANA_SECRET

# prometheus values -> prom-values.yaml
tee artefact/prom-values.yaml <<EOL_PROM_VALUES
grafana:
  admin:
    existingSecret: grafana-secret
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
EOL_PROM_VALUES

# kubeadm-config.yaml -> https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta3/
tee artefact/kubeadm-config.yaml <<EOL_KUBEADM_CONFIG
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
clusterName: $CLUSTER_NAME
kubernetesVersion: $VERSION
networking:
  serviceSubnet: $SVC_NETWORK_CIDR
  podSubnet: $POD_NETWORK_CIDR
controllerManager:
  extraArgs:
    bind-address: "0.0.0.0"
scheduler:
  extraArgs:
    bind-address: "0.0.0.0"
etcd:
  local:
    extraArgs:
      listen-metrics-urls: "http://0.0.0.0:2381"
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd      
EOL_KUBEADM_CONFIG

################################################################################
# create setup.sh
tee setup.sh <<EOL_SETUP
#!/bin/bash

SETUP_START=\$(date +%s)

################################################################################
# install packages
PACKAGES=\$(find deb -name "*.deb")
dpkg --install \$PACKAGES

################################################################################
# specific setup routines: init, join, upgrade or delete
if [ -z "\$1" ] ; then
  gum style \
    --foreground 212 --border-foreground 212 --border rounded \
    --align center --width 30 --margin "1 1" --padding "1 1" \
    'kubian 1.28.2 setup' 'select operation?'
  ARG1=\$(gum choose "init" "join" "upgrade" "delete")
else
  ARG1="\$1"
fi

INIT=false
JOIN=false
UPGRADE=false
DELETE=false

[ "\$ARG1" = init ] && INIT=true
[ "\$ARG1" = join ] && JOIN=true
[ "\$ARG1" = upgrade ] && UPGRADE=true
[ "\$ARG1" = delete ] && DELETE=true

if [ -z "\$2" ] ; then
  # init arguments: single or cluster
  if [ \$INIT = true ] ; then
    gum style \
      --foreground 212 --border-foreground 212 --border rounded \
      --align center --width 30 --margin "1 1" --padding "1 1" \
      'initialize cluster' 'single node or cluster?'
    ARG2=\$(gum choose "single" "cluster")
  fi

  # join arguments: worker or controlplane and primary controlplane ip
  if [ \$JOIN = true ] ; then
    gum style \
      --foreground 212 --border-foreground 212 --border rounded \
      --align center --width 30 --margin "1 1" --padding "1 1" \
      'join node' 'worker or controlplane?'
    ARG2=\$(gum choose "worker" "controlplane")
    ARG3=\$(gum input --placeholder "ip of primary control plane")
  fi
else
  ARG2="\$2"
  ARG3="\$3"
fi

CLUSTER=false
SINGLE=false
CONTROLPLANE=false
WORKER=false

[ "\$ARG2" = cluster ] && CLUSTER=true
[ "\$ARG2" = single ] && SINGLE=true
[ "\$ARG2" = controlplane ] && CONTROLPLANE=true
[ "\$ARG2" = worker ] && WORKER=true

################################################################################
# add kernel module for networking and disk stuff
tee /etc/modules-load.d/k8s.conf <<EOL_MODULES
overlay
br_netfilter
iscsi_tcp
nvme-tcp
EOL_MODULES

modprobe --all overlay br_netfilter iscsi_tcp nvme-tcp

tee /etc/sysctl.d/kubernetes.conf <<EOL_SYSCTL
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.nr_hugepages = 1024
EOL_SYSCTL

sysctl --system

################################################################################
# disable swap
sed -e "/swap/ s/^/#/" -i /etc/fstab
swapoff --all

# prevent swap from being re-enabled via systemd
systemctl mask swap.target

################################################################################
# enable iscsid service
systemctl enable --now iscsid

################################################################################
# containerd config
containerd config default | tee /etc/containerd/config.toml

# fix config pause container (use same version as kubernetes)
sed -i 's/pause:3../pause:3.9/' /etc/containerd/config.toml

# fix systemd cgroup (use cgroup v1)
#sed -i 's/systemd_cgroup = true/systemd_cgroup = false/' /etc/containerd/config.toml

systemctl restart containerd

################################################################################
# install helm
tar Cxzf /tmp artefact/helm-v3.13.3-linux-amd64.tar.gz && cp /tmp/linux-amd64/helm /usr/local/bin/

################################################################################
# install k9s
tar Cxzf /tmp artefact/k9s_Linux_amd64.tar.gz && cp /tmp/k9s /usr/local/bin/

################################################################################
# install velero
tar Cxzf /tmp artefact/velero-v1.12.0-linux-amd64.tar.gz && cp /tmp/velero-v1.12.0-linux-amd64/velero /usr/local/bin/

################################################################################
# install yq
cp artefact/yq /usr/local/bin/yq && chmod 755 /usr/local/bin/yq

################################################################################
# install calico cni-plugins
cp artefact/calico /opt/cni/bin/ && chmod 755 /opt/cni/bin/calico
cp artefact/calico /opt/cni/bin/calico-ipam && chmod 755 /opt/cni/bin/calico-ipam

################################################################################
# enable kubelet services
systemctl enable kubelet

################################################################################
# import container images
echo "Be patient import container images ..."
ctr --namespace k8s.io images import container/images.tar

################################################################################
# init kubernetes cluster -> primary control plane
if [ \$INIT = true ] ; then
  echo "init kubernetes cluster ..."

  ################################################################################
  # init cluster
  NETWORK_INTERFACE=\$(ip route | grep default | awk '{print \$5}')
  IP_ADDRESS=\$(ip -brief address show \$NETWORK_INTERFACE | awk '{print \$3}' | awk -F/ '{print \$1}')
  echo "controlPlaneEndpoint: \$IP_ADDRESS" >> artefact/kubeadm-config.yaml

  kubeadm init --upload-certs --node-name=\$HOSTNAME --config artefact/kubeadm-config.yaml
  [ \$? != 0 ] && echo "ERROR: can't initialize cluster" && exit 1

  ################################################################################
  # copy kube config
  mkdir ~/.kube
  ln -s /etc/kubernetes/admin.conf ~/.kube/config
fi

################################################################################
# cluster settings -> install cni calico 
if [ \$CLUSTER = true ] ; then
  echo "cluster settings"

  ################################################################################
  # install projectcalico tigera-operator v3.26.4
  helm upgrade --install tigera-operator helm/tigera-operator-v3.26.4.tgz \
    --create-namespace \
    --namespace tigera-operator \
    --version v3.26.4
  if [ \$? != 0 ] ; then
    # give grace period of 2 minutes to get node ready
    kubectl wait --timeout=2m --for=condition=Ready node/\$HOSTNAME
    [ \$? != 0 ] && echo "ERROR: can't initialize cluster" && exit 1
  fi
fi

################################################################################
# single node cluster
if [ \$SINGLE = true ] ; then
  echo "single node cluster"

  ################################################################################
  # remove no schedule taint for control plane
  kubectl taint nodes \$HOSTNAME node-role.kubernetes.io/control-plane=:NoSchedule-

  ################################################################################
  # install projectcalico tigera-operator v3.26.4
  helm upgrade --install tigera-operator helm/tigera-operator-v3.26.4.tgz \
    --create-namespace \
    --namespace tigera-operator \
    --version v3.26.4
  if [ \$? != 0 ] ; then
    # give grace period of 2 minutes to get node ready
    kubectl wait --timeout=2m --for=condition=Ready node/\$HOSTNAME
    [ \$? != 0 ] && echo "ERROR: can't initialize cluster" && exit 1
  fi

  ################################################################################
  # install openebs openebs 3.9.0
  helm upgrade --install openebs helm/openebs-3.9.0.tgz \
    --create-namespace \
    --namespace openebs \
    --version 3.9.0

  # set default storage class
  kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

  ################################################################################
  # install ingress-nginx controller
  helm upgrade --install ingress-nginx helm/ingress-nginx-4.8.3.tgz \
    --create-namespace \
    --namespace ingress-nginx \
    --version 4.8.3 \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=30080 \
    --set controller.service.nodePorts.https=30443

  ################################################################################
  # install cert-manager
  helm upgrade --install cert-manager helm/cert-manager-v1.13.2.tgz \
    --create-namespace \
    --namespace cert-manager \
    --version v1.13.2 \
    --set installCRDs=true

  kubectl apply -f artefact/issuer-letsencrypt.yaml

  ################################################################################
  # install metrics-server 3.11.0
  helm upgrade --install metrics-server helm/metrics-server-3.11.0.tgz \
    --create-namespace \
    --namespace monitoring \
    --version 3.11.0 \
    --set args="{--kubelet-insecure-tls}"

  ################################################################################
  # alertmanager, prometheus and grafana 
  helm upgrade --install kube-prometheus-stack helm/kube-prometheus-stack-54.2.2.tgz \
    --create-namespace \
    --namespace monitoring \
    --version 54.2.2 \
    --set alertmanager.service.type=NodePort \
    --set prometheus.service.type=NodePort \
    --set grafana.service.type=NodePort \
    --set grafana.service.nodePort=30303 \
    --values artefact/prom-values.yaml

  kubectl apply -f artefact/grafana-secret.yaml
  
  # patch metrics bind address in configmap kube-proxy
  kubectl get configmap kube-proxy --namespace kube-system -o yaml | \
  sed 's/metricsBindAddress: ""/metricsBindAddress: "0.0.0.0"/' | \
  kubectl apply -f -

  kubectl delete pod --selector k8s-app=kube-proxy --namespace kube-system
fi

################################################################################
# join worker
if [ \$JOIN = true ] && [ \$WORKER = true ] ; then
  ssh -oBatchMode=yes -q \$ARG3 exit
  if [ \$? = 0 ] ; then
    mkdir -p ~/.kube
    scp \$ARG3:~/.kube/config ~/.kube/config
    JOIN_WORKER=\$(ssh -oBatchMode=yes \$ARG3 kubeadm token create --print-join-command)
    eval \$JOIN_WORKER
  else
    echo "ERROR: can't connect to \$ARG3 via ssh"
    exit 1
  fi

  ################################################################################
  # install openebs openebs 3.9.0 (mayastor)
  helm upgrade --install openebs helm/openebs-3.9.0.tgz \
    --create-namespace \
    --namespace openebs \
    --set mayastor.enabled=true \
    --set mayastor.etcd.replicaCount=1 \
    --set mayastor.etcd.persistence.storageClass=mayastor-etcd-localpv \
    --reuse-values \
    --version 3.9.0
  
  # label node for mayastor usage
  kubectl label node \$HOSTNAME openebs.io/engine=mayastor

  # set default storage class
  kubectl patch storageclass openebs-single-replica -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

  ################################################################################
  # install ingress-nginx controller
  helm upgrade --install ingress-nginx helm/ingress-nginx-4.8.3.tgz \
    --create-namespace \
    --namespace ingress-nginx \
    --version 4.8.3 \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=30080 \
    --set controller.service.nodePorts.https=30443

  ################################################################################
  # install cert-manager
  helm upgrade --install cert-manager helm/cert-manager-v1.13.2.tgz \
    --create-namespace \
    --namespace cert-manager \
    --version v1.13.2 \
    --set installCRDs=true

  kubectl apply -f artefact/issuer-letsencrypt.yaml

  ################################################################################
  # install metrics-server 3.11.0
  helm upgrade --install metrics-server helm/metrics-server-3.11.0.tgz \
    --create-namespace \
    --namespace monitoring \
    --version 3.11.0 \
    --set args="{--kubelet-insecure-tls}"
fi

################################################################################
# join controlplane
if [ \$JOIN = true ] && [ \$CONTROLPLANE = true ] ; then
  ssh -oBatchMode=yes -q \$ARG3 exit
  if [ \$? = 0 ] ; then
    mkdir -p ~/.kube
    scp \$ARG3:~/.kube/config ~/.kube/config
    CERTIFICATE_KEY=\$(ssh -oBatchMode=yes \$ARG3 kubeadm init phase upload-certs --upload-certs | tail -1)
    JOIN_CONTROLPLANE=\$(ssh -oBatchMode=yes \$ARG3 kubeadm token create --print-join-command --certificate-key \$CERTIFICATE_KEY)
    eval \$JOIN_CONTROLPLANE
  else
    echo "ERROR: can't connect to \$ARG3 via ssh"
    exit 1
  fi
fi

################################################################################
# upgrade
if [ \$UPGRADE = true ] ; then
  echo "upgrade first contol plane node"
  systemctl restart kubelet

  # give grace period of 1 minute to get node ready
  kubectl wait --timeout=1m --for=condition=Ready node/\$HOSTNAME
  [ \$? != 0 ] && echo "ERROR: can't upgrade control plane" && exit 1

  kubeadm upgrade apply $VERSION --yes

  # TODO check node to upgrade -> primary control plane, additional control plane or worker node 
  # https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/
fi

################################################################################
# delete
if [ \$DELETE = true ] ; then
  echo "delete node \$HOSTNAME"
  kubectl cordon node \$HOSTNAME
  kubectl drain --ignore-daemonsets \$HOSTNAME
  kubectl delete node \$HOSTNAME
  kubeadm reset --force
fi

################################################################################
# cleanup
rm -rf setup.sh deb/ container/ artefact/ helm/  

################################################################################
# finish
SETUP_END=\$(date +%s)
SETUP_MINUTES=\$(((\$SETUP_END - \$SETUP_START) / 60))
SETUP_SECONDS=\$((\$SETUP_END - \$SETUP_START - (\$SETUP_MINUTES * 60)))

echo "setup took \$SETUP_MINUTES minutes \$SETUP_SECONDS seconds"
EOL_SETUP

chmod +x setup.sh

################################################################################
# create self extracting archive
TAR_FILE="$NAME-$VERSION.tgz"
SELF_EXTRACTABLE="$TAR_FILE.self"

echo "Be patient creating self extracting archive ..."
# pack and create self extracting archive
tar -czf $TAR_FILE  setup.sh deb/ container/ artefact/ helm/

echo '#!/bin/bash' > $SELF_EXTRACTABLE
echo 'echo Be patient extracting archive ...' >> $SELF_EXTRACTABLE
echo 'dd bs=`head -5 $0 | wc -c` skip=1 if=$0 | gunzip -c | tar -x' >> $SELF_EXTRACTABLE
echo 'exec ./setup.sh $1 $2 $3' >> $SELF_EXTRACTABLE
echo '######################################################################' >> $SELF_EXTRACTABLE

cat $TAR_FILE >> $SELF_EXTRACTABLE
chmod a+x $SELF_EXTRACTABLE

################################################################################
# cleanup
rm -rf $TAR_FILE setup.sh deb/ container/ artefact/ helm/

################################################################################
# finish
BUILD_END=$(date +%s)
BUILD_MINUTES=$((($BUILD_END - $BUILD_START) / 60))
BUILD_SECONDS=$(($BUILD_END - $BUILD_START - ($BUILD_MINUTES * 60)))

echo "build $SELF_EXTRACTABLE took $BUILD_MINUTES minutes $BUILD_SECONDS seconds"
