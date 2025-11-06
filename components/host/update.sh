#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
COMMON_BASE_DIR=$(readlink -f "$SCRIPT_DIR/../common")
COMMON_SCRIPT_DIR=$(readlink -f "$COMMON_BASE_DIR/scripts")

. "$COMMON_SCRIPT_DIR/common.sh"
. "$COMMON_SCRIPT_DIR/salt.sh"

# If we are not root, re-run with root privileges.
if [ "${UID}" -ne 0 ]; then
  highlight "root priviliges are required. Re-running under sudo..."
  exec sudo ${0} $@
fi

main() {
  local git_local_file="/root/.salt-local/git.sls"
  local git_override_file="/var/local/litos-git.override"

  highlight "Updating LitOS..."

  # Had an issue once with file limits.
  ulimit -n 10000

  # Extra initial step to avoid needing to run `lit os update` twice when you change branches.
  if [ -e "${git_local_file}" ] || [ -e "${git_override_file}" ]; then
    [ ! -e "${LITOS_ASSETS_DIR}" ] && salt_call_bootstrap_litos_repo
    install_salt_profile "$(ensure salt_call_pillar_item "litos_host_type")" "${LITOS_ASSETS_DIR}"

    # Simple optimisation to enable "switching back" (when we delete git.sls).
    if [ -e "${git_local_file}" ]; then
      touch "${git_override_file}"
    else
      rm "${git_override_file}"
    fi
  fi

  salt_call_bootstrap_litos_repo
  install_salt_profile "$(ensure salt_call_pillar_item "litos_host_type")" "${LITOS_ASSETS_DIR}"
  salt_call_state_apply
}

main $@
