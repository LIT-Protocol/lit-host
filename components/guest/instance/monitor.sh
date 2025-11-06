#!/bin/bash
#
#

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
COMMON_BASE_DIR="$SCRIPT_DIR/../../common"
COMMON_SCRIPT_DIR="$COMMON_BASE_DIR/scripts"

. "$COMMON_SCRIPT_DIR/common.sh"
. "$COMMON_SCRIPT_DIR/salt.sh"
. "$SCRIPT_DIR/common.sh"

MONITOR_SOCK="monitor.sock"
TIMEOUT=30

INSTANCE_PATH=""
ACTION=""

usage() {
  stderr "$0 [options]"
  stderr
  stderr "QEMU monitor actions for a running Lit-OS guest instance."
  stderr
  stderr "Options:"
  stderr
  stderr " -path <PATH>       instance path"
  stderr " -shutdown          send system power down event"
  stderr " -reset             reset the system"
  stderr
  exit 1
}

send_monitor_cmd() {
  local cmd="$1"

  echo $cmd | sudo socat - unix-connect:$INSTANCE_PATH/$MONITOR_SOCK 2>&1 | tail --lines=+2 | grep -v '^(qemu)'
}

is_running() {
  local status=$(send_monitor_cmd "info status" | tr -d "\n\r")
  if [ "$?" != "0" ] || [ "$status" != "VM status: running" ]; then
    return 1
  fi

  return 0
}

do_shutdown() {
  highlight "Attempting shutdown of $INSTANCE_ID"
  echo ""

  if ! is_running; then
    echo "Already shutdown"
    return 0
  fi

  # Can not check $? as it will be 1 (socket closes).
  send_monitor_cmd "system_powerdown" >/dev/null

  for i in $(seq $TIMEOUT); do
    if ! is_running; then
      echo "Shutdown complete!"
      return 0
    fi

    echo "[$i] Waiting on shutdown ..."
    sleep 1
  done

  die "Failed to shutdown"
}

do_reset() {
  highlight "Attempting shutdown of $INSTANCE_ID"
  echo ""

  if ! is_running; then
    die "Instance not running"
  fi

  send_monitor_cmd "system_reset" >/dev/null
}

main() {
  # Check arguments
  if [ -z "${INSTANCE_PATH}" ] || [ -z "${ACTION}" ]; then
    usage
  fi

  init_instance_env true

  if [ ! -e "${INSTANCE_PATH}/${MONITOR_SOCK}" ]; then
    local err_msg="Instance monitor socket file not found: $INSTANCE_PATH/$MONITOR_SOCK"
    if [ "${ACTION}" == "shutdown" ]; then
      echo "$err_msg (must be already shutdown)"
      return 0
    else
      die $err_msg
    fi
  fi

  case "$ACTION" in
  shutdown)
    do_shutdown
    ;;
  reset)
    do_reset
    ;;
  *)
    stderr "ERROR: Invalid action: $ACTION"
    stderr
    usage
    ;;
  esac
}

if [ $(id -u) -ne 0 ]; then
  stderr "Must be run as root!"
  exit 1
fi

while [ -n "$1" ]; do
  case "$1" in
  -path)
    INSTANCE_PATH="$2"
    shift
    ;;
  -shutdown)
    ACTION="shutdown"
    ;;
  -reset)
    ACTION="reset"
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
