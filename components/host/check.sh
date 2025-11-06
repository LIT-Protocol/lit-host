#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
COMMON_BASE_DIR=$(readlink -f "$SCRIPT_DIR/../common")
COMMON_SCRIPT_DIR=$(readlink -f "$COMMON_BASE_DIR/scripts")

. "$COMMON_SCRIPT_DIR/common.sh"
. "$COMMON_SCRIPT_DIR/salt.sh"

main() {
  if is_amd; then
    echo "dmesg | grep -i -e rmp -e sev"
    dmesg | grep -i -e rmp -e sev
    echo ""
    echo_run cat /sys/module/kvm_amd/parameters/sev
    echo_run cat /sys/module/kvm_amd/parameters/sev_es
    echo_run cat /sys/module/kvm_amd/parameters/sev_snp
  else
    die "CPU not supported."
  fi
}

main $@