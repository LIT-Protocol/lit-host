#!/bin/bash
#
#

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
COMMON_BASE_DIR="$SCRIPT_DIR/../../common"
COMMON_SCRIPT_DIR="$COMMON_BASE_DIR/scripts"

. "$COMMON_SCRIPT_DIR/common.sh"
. "$COMMON_SCRIPT_DIR/salt.sh"
. "$SCRIPT_DIR/common.sh"

INSTANCE_PATH=""
ADD_IMG_SIZE=""

PATH=/opt/AMDSEV/usr/local/bin:$PATH

usage() {
  if [ "${LIT_CLI}" = "1" ]; then
    exit 1
  fi

	stderr "$0 [options]"
  stderr
  stderr "Resize a Lit-OS guest instance."
  stderr
	stderr "Options:"
  stderr
	stderr " -path <PATH>        instance install path"
	stderr " -add-img-size <STR> extra storage to allocate"
  stderr
	exit 1
}

main() {
  local instance_env="instance.env"

	# Check arguments
	if [ -z "${INSTANCE_PATH}" ] || [ -z "${ADD_IMG_SIZE}" ]; then
		usage
	fi

	init_instance_env true

	highlight "Resizing instance (Id: $INSTANCE_ID, Adding: $ADD_IMG_SIZE)"

  echo_run systemctl stop "${INSTANCE_SERVICE}"
  echo_run qemu-img resize -f qcow2 ./guest-disk.qcow2 "+${ADD_IMG_SIZE}"
  echo_run qemu-nbd -d /dev/nbd8
  echo_run qemu-nbd -c /dev/nbd8 -f qcow2 ./guest-disk.qcow2
  sleep 0.5 # give QEMU some time to register the virtual blockdev
  echo_run sgdisk -e /dev/nbd8
  echo_run qemu-nbd -d /dev/nbd8

  {
    grep -v "INSTANCE_IMG_SIZE" < ./${instance_env}
    echo "INSTANCE_IMG_SIZE=\"$(expr "$(echo "$INSTANCE_IMG_SIZE" | tr -d 'G')" + "$(echo "$ADD_IMG_SIZE" | tr -d 'G')")G\"";
  } > ${instance_env}.tmp
  cp -f ${instance_env} ${instance_env}.bak
  mv ${instance_env}.tmp ${instance_env}

	echo
	highlight "Successfully resized ${INSTANCE_ID}!"
	exit 0
}

if [ `id -u` -ne 0 ]; then
	stderr "Must be run as root!"
	exit 1
fi

while [ -n "$1" ]; do
	case "$1" in
		-path)         INSTANCE_PATH="$2"
				shift
				;;
		-add-img-size) ADD_IMG_SIZE="$2"
				shift
				;;
		*) 		
        stderr "ERROR: Invalid option: $1"
        stderr
        usage
				;;
	esac

	shift
done

modprobe nbd

main $@
