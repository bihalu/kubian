#!/bin/bash

NAME="kubian-minio"
VERSION="2023.7.18"
BUILD_START=$(date +%s)

################################################################################
# container images for airgap installation
readarray -t IMAGES <<EOL_IMAGES
################################################################################
# minio 2023.7.18 -> https://artifacthub.io/packages/helm/bitnami/minio/12.8.1
docker.io/bitnami/minio:2023.7.18-debian-11-r0
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
https://charts.bitnami.com/bitnami bitnami minio 12.8.1
EOL_HELM_CHARTS

mkdir -p helm/

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
# create app.sh
cat - > app.sh <<EOF_APP
#!/bin/bash

SETUP_START=\$(date +%s)

################################################################################
# specific routines for:
# - install
# - uninstall
echo "app \$1 \$2"

INSTALL=false
UNINSTALL=false

[ "\$1" = install ] && INSTALL=true
[ "\$1" = uninstall ] && UNINSTALL=true

################################################################################
# import container images
echo "Be patient import container images ..."
ctr -n=k8s.io image import container/images.tar

################################################################################
# install minio
if [ \$INSTALL = true ] ; then
  helm upgrade --install minio helm/minio-12.8.1.tgz \
    --create-namespace \
    --namespace minio \
    --version 12.8.1 \
    --set service.type=NodePort \
    --set service.nodePorts.console=30001 \
    --set service.nodePorts.api=30002
fi

################################################################################
# uninstall minio
if [ \$UNINSTALL = true ] ; then
  helm uninstall minio --namespace minio
fi

################################################################################
# cleanup
rm -rf app.sh container/ helm/ 

################################################################################
# finish
SETUP_END=\$(date +%s)
SETUP_MINUTES=\$(((\$SETUP_END - \$SETUP_START) / 60))
SETUP_SECONDS=\$((\$SETUP_END - \$SETUP_START - (\$SETUP_MINUTES * 60)))

echo "app $NAME $VERSION took \$SETUP_MINUTES minutes \$SETUP_SECONDS seconds"
EOF_APP

chmod +x app.sh

################################################################################
# create self extracting archive
TAR_FILE="${NAME}-${VERSION}.tgz"
SELF_EXTRACTABLE="$TAR_FILE.self"

echo "Be patient creating self extracting archive ..."
# pack and create self extracting archive
tar -czf ${TAR_FILE} app.sh container/ helm/

echo '#!/bin/bash' > $SELF_EXTRACTABLE
echo 'echo Be patient extracting archive ...' >> $SELF_EXTRACTABLE
echo 'dd bs=`head -5 $0 | wc -c` skip=1 if=$0 | gunzip -c | tar -x' >> $SELF_EXTRACTABLE
echo 'exec ./app.sh $1 $2' >> $SELF_EXTRACTABLE
echo '######################################################################' >> $SELF_EXTRACTABLE

cat $TAR_FILE >> $SELF_EXTRACTABLE
chmod a+x $SELF_EXTRACTABLE

################################################################################
# cleanup
 rm -rf $TAR_FILE app.sh container/ helm/

################################################################################
# finish
BUILD_END=$(date +%s)
BUILD_MINUTES=$((($BUILD_END - $BUILD_START) / 60))
BUILD_SECONDS=$(($BUILD_END - $BUILD_START - ($BUILD_MINUTES * 60)))

echo "build $SELF_EXTRACTABLE took $BUILD_MINUTES minutes $BUILD_SECONDS seconds"
