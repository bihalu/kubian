#!/bin/bash

NAME="scan"
VERSION="0.50.1"
RESULT="scan-"`date +"%Y-%m-%d-%H%M"`".txt"

# Download trivy scanner
wget https://github.com/aquasecurity/trivy/releases/download/v$VERSION/trivy_${VERSION}_Linux-64bit.tar.gz -O trivy && mv trivy /usr/local/bin/

# Get all cluster images
IMAGES=$(kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec['initContainers', 'containers'][*].image}" | tr -s '[[:space:]]' '\n' | sort -u)

for IMAGE in $IMAGES ; do
  gum spin --title "Scanning image $IMAGE" -- trivy image --quiet --severity CRITICAL --output /tmp/$RESULT $IMAGE 
  cat /tmp/$RESULT >> $RESULT
done
