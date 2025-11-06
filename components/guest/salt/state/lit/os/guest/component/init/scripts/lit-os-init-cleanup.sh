#!/bin/bash
#
#

set -e

## Environment

PATH=/usr/sbin:/usr/local/bin:/usr/bin:/bin:$PATH

MSG_PREFIX="[lit-os-init > CLEANUP]"

# ARGS
NET_INTERNAL_IFACE=""

# Already run?
if [ -e "${STATE_FILE}" ]; then
  exit 0;
fi

usage() {
	stderr "$0 [options]"
  stderr
  stderr "Clean up after performing the initrd on a Lit OS Guest"
  stderr
	stderr "Options:"
  stderr
	stderr " --net-internal-iface <STR>  internal network interface."
  stderr
	exit 1
}

ensure() {
    if ! "$@"; then die "command failed: $*"; fi
}

stderr() {
	echo "${@}" >&2
}

die() {
  stderr "${MSG_PREFIX} ERROR: ${FUNCNAME[1]}: ${@}"
  exit 1
}

info() {
  echo "${MSG_PREFIX} ${@}"
}

echo_run() {
  echo "${MSG_PREFIX} $@"
  $@
}

main() {
  if [ -n "${NET_INTERNAL_IFACE}" ]; then
    info "Taking down network interface..."

    # Obtain the IP
    local net_ip=$(ip address show "$NET_INTERNAL_IFACE" | grep "inet " | awk '{ print $2 }')
    if [ -n "${net_ip}" ]; then
      # ipconfig doesn't remove the IP.
     ip addr del "${net_ip}" dev "$NET_INTERNAL_IFACE"
    fi

    # Busybox down it.
    ipconfig -t 30 -c "off" -d "${NET_INTERNAL_IFACE}"

  fi
}

# Run

while [ -n "$1" ]; do
	case "$1" in
		--net-internal-iface)  NET_INTERNAL_IFACE="$2"
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

main "$@"