#!/bin/bash

COMMON_SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

COMPONENT_DIR=$(readlink -f "$COMMON_SCRIPT_DIR/../..")
BASE_DIR=$(readlink -f "$COMPONENT_DIR/..")

BUNDLE_DIR="$(readlink -f "$COMPONENT_DIR/common/bundle")"

LITOS_INSTALL_DIR="/opt/lit/os"
LITOS_ASSETS_DIR="/opt/assets/lit-os"
# Used in create & repair
LITOS_GUEST_LAUNCH_SCRIPT="${LITOS_INSTALL_DIR}/guest/instance/launch.sh"
LITOS_GUEST_MONITOR_SCRIPT="${LITOS_INSTALL_DIR}/guest/instance/monitor.sh"

TEE_SRC_DIR="/usr/local/src/amd"
TEE_PACKAGE_DIR="$TEE_SRC_DIR/packages"

ensure_root() {
  if [ "${UID}" -ne 0 ]; then
    highlight "root priviliges are required. Re-running under sudo..."
    exec sudo ${0} $@
  fi
}

ensure_root_via_su() {
  local old_pwd=$(pwd)
  if [ "${UID}" -ne 0 ]; then
    highlight "root priviliges are required. Re-running under su..."
    exec su - -c "cd $old_pwd && ${0} $@"
  fi
}

ensure() {
    if ! "$@"; then die "command failed: $*"; fi
}

stderr() {
	echo "${@}" >&2
}

die() {
  stderr "ERROR: ${FUNCNAME[1]}: ${@}"
  exit 1
}

highlight() {
  echo -e "\e[1;33m${@}\e[0m"
}

echo_run() {
  echo "$@"
  $@
}

is_amd() {
  cat /proc/cpuinfo | grep 'model name' | uniq | grep  "AMD " > /dev/null
}

is_milan() {
  local family=$(awk '/cpu family/{print $NF;exit}' /proc/cpuinfo)
  local model=$(awk '/model/{print $NF;exit}' /proc/cpuinfo)
  if [[ $family -eq 25 && $model -eq 1 ]]; then # https://en.wikichip.org/wiki/amd/cores/milan
    return 0 # Matched Milan
  else
    return 1 # Not Milan
  fi
}

is_genoa() {
  local family=$(awk '/cpu family/{print $NF;exit}' /proc/cpuinfo)
  local model=$(awk '/model/{print $NF;exit}' /proc/cpuinfo)
  if [[ $family -eq 25 && $model -eq 17 ]]; then # https://en.wikichip.org/wiki/amd/cores/genoa
    return 0 # Matched Genoa
  else
    return 1 # Not Genoa
  fi
}
