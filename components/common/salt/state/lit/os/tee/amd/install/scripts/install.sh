#!/bin/bash

set -e

## Environment

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SRC_DIR=/usr/local/src/amd
PKG_DIR=$SRC_DIR/packages
PKG_SNP_DIR=$PKG_DIR/snp-release-current
PKG_FW_DIR=$PKG_DIR/firmware
INSTALL_DIR=/opt/AMDSEV

## Functions

highlight() {
  echo -e "\e[1;33m${@}\e[0m"
}

install_deps() {
  echo ""
  highlight "Installing deps..."

  apt-get update
  apt-get install git xz-utils python-is-python3 equivs rsync zip cloud-image-utils bridge-utils uml-utilities -y

  for d in $PKG_SNP_DIR $PKG_FW_DIR; do
    if [ ! -d $d ]; then
      echo "Missing package dir: $d"
      exit 2
    fi
  done

  dpkg -i $PKG_SNP_DIR/linux/host/*.deb

  mkdir -p /lib/firmware/amd
  cp $PKG_FW_DIR/*.sbin /lib/firmware/amd
}

install_bins() {
  echo ""
  highlight "Installing bins..."

  if [ -d $INSTALL_DIR ]; then
    rm -rf $INSTALL_DIR
  fi

  mkdir -p $INSTALL_DIR
  cp -rf $PKG_SNP_DIR/{launch-qemu.sh,usr} $INSTALL_DIR/
}

main() {
  install_deps
  install_bins
}

main $@
