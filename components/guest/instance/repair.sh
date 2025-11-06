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

PATH=/opt/AMDSEV/usr/local/bin:$PATH

usage() {
  if [ "${LIT_CLI}" = "1" ]; then
    exit 1
  fi

	stderr "$0 [options]"
  stderr
  stderr "Repair a Lit-OS guest instance."
  stderr
	stderr "Options:"
  stderr
	stderr " -path <PATH>        instance install path"
  stderr
	exit 1
}

main() {
	# Check arguments
	if [ -z "${INSTANCE_PATH}" ]; then
		usage
	fi

	init_instance_env true

	highlight "Repairing instance (Id: $INSTANCE_ID)"

  init_logging_facilities
  create_systemd_service

	echo
	highlight "Successfully repaired ${INSTANCE_ID}!"
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
		*) 		
        stderr "ERROR: Invalid option: $1"
        stderr
        usage
				;;
	esac

	shift
done

main $@
