#!/bin/bash
#
#

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
  stderr "Destroy a Lit-OS guest instance."
  stderr
	stderr "Options:"
  stderr
	stderr " -path <PATH>       instance install path"
  stderr
	exit 1
}

main() {
  local instance_env="instance.env"

	# Check arguments
	if [ -z "${INSTANCE_PATH}" ]; then
		usage
	fi

	init_instance_env

	highlight "Destroying instance ($INSTANCE_ID)"

  purge_logging_facilities restart

  systemctl stop ${INSTANCE_SERVICE} || true
  systemctl disable ${INSTANCE_SERVICE} || true
  if [ -f "${INSTANCE_SERVICE_FILE}" ]; then
    rm -f ${INSTANCE_SERVICE_FILE}
  fi
  systemctl daemon-reload

  rm -rf ${INSTANCE_PATH}

	echo
	highlight "Successfully destroyed ${INSTANCE_ID}!"
	exit 0
}

if [ `id -u` -ne 0 ]; then
	stderr "Must be run as root!"
	exit 1
fi

while [ -n "$1" ]; do
	case "$1" in
		-path)        INSTANCE_PATH="$2"
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
