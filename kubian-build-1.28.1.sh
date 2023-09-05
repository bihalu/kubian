#!/bin/bash

INSTALLED_PACKAGES=$(dpkg -l | sed '/^ii/!d' | tr -s ' ' | cut -d ' ' -f 2,3,4)

################################################################################
# deb packages for airgap installation
readarray -t PACKAGES <<EOL_PACKAGES
# aptitude
aptitude 0.8.13-5 amd64
aptitude-common 0.8.13-5 all
libboost-iostreams1.74.0:amd64 1.74.0+ds1-21 amd64
libcwidget4:amd64 0.5.18-6 amd64
libdpkg-perl 1.21.22 all
libfile-fcntllock-perl 0.22-4+b1 amd64
libsigc++-2.0-0v5:amd64 2.12.0-1 amd64
libxapian30:amd64 1.4.22-1 amd64
# jq
jq 1.6-2.1 amd64
libjq1:amd64 1.6-2.1 amd64
libonig5:amd64 6.9.8-1 amd64
# curl
curl 7.88.1-10+deb12u1 amd64
libcurl4:amd64 7.88.1-10+deb12u1 amd64
EOL_PACKAGES

mkdir -p deb/

aptitude clean

for PACKAGE in "${PACKAGES[@]}" ; do
  # don't process commented out packages
  [[ ${PACKAGE:0:1} = \# ]] && continue

  # skip packages
  [[ ${SKIP_PACKAGES} -gt 0 ]] && ((SKIP_PACKAGES--)) && continue

  # parse package data
  PACKAGE_DATA=($PACKAGE)
  PACKAGE_NAME="${PACKAGE_DATA[0]}"
  PACKAGE_VERSION="${PACKAGE_DATA[1]}"
  PACKAGE_ARCH="${PACKAGE_DATA[2]}"

  aptitude --download-only reinstall -y $PACKAGE_NAME
  PACKAGE_FILE="${PACKAGE_NAME}_${PACKAGE_VERSION}_${PACKAGE_ARCH}.deb"
  cp /var/cache/apt/archives/${PACKAGE_FILE} deb/
done

