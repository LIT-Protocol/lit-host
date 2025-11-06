#!/bin/sh
PREREQ=""
prereqs() {
    echo "$PREREQ"
}

case $1 in
    prereqs)
        prereqs
        exit 0
    ;;
esac

. /scripts/functions # from initramfs-tools/scripts/functions

# Internal netif is always dhcp, bring it up
export DEVICE="enp0s2"
export IP="dhcp"

# this fn is provided by initramfs-tools and takes the following args:
# https://salsa.debian.org/kernel-team/initramfs-tools/-/blob/debian/latest/scripts/functions#L281
configure_networking 

/opt/lit/os/init/lit-os-init