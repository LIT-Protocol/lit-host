#!/bin/bash

set -e

SALT_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

SALT_STATE_DIR=/srv/salt
SALT_PILLAR_DIR=/srv/pillar
SALT_PILLAR_LOCAL=/var/local/salt-local.sls
SALT_PILLAR_LOCAL_DEFAULTS_FILE=/root/.salt-local/defaults.sls

## Files (or directories) that are purged when the salt state is refreshed.
# This is required because the 'watch' condition will not trigger when updating prior to running.
SALT_PURGE_PATHS=("/var/local/lit-cli.install" "/var/local/lit-node.install")

install_salt_on_host() {
  local script="/var/tmp/bootstrap-salt.sh"
  local salt_master=$1

  # NOTE: command -v exits with 0 if the command exists, 1 if it doesn't
  [ -z "${salt_master}" ] && command -v salt-call 2>&1 >/dev/null && return 0   # Salt call already installed (masterless)
  [ -n "${salt_master}" ] && command -v salt-minion 2>&1 >/dev/null && return 0 # Salt minion already installed

  echo ""
  [ -z "${salt_master}" ] && highlight "Installing minionless salt..."
  [ -n "${salt_master}" ] && highlight "Installing mastered salt..."

  # Create salt folders we'll use later
  mkdir -p $SALT_STATE_DIR
  mkdir -p $SALT_PILLAR_DIR

  # the following is needed for the bootstrap script to succeed on updates
  # from older versions that had salt-minion masked instead of uninstalled
  systemctl unmask salt-minion 2>&1 >/dev/null || true # ignore errors
  systemctl enable salt-minion 2>&1 >/dev/null || true # ignore errors
  systemctl daemon-reload
  apt-get remove -y salt-minion salt-common 2>&1 >/dev/null || true # ignore errors

  [ -f $script ] && rm -f $script

  # install salt
  apt-get update
  apt-get install curl rsync -y

  curl -o $script -L https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh
  chmod +x $script
  $script -n -d -U stable latest # -n no colours -d don't check if salt-minion is running
  rm -f $script

  # NOTE: The bootstrap script installs and launches salt-minion by default.
  # For masterless, we don't want that, so we uninstall it right away
  # but keep salt-common as that provides salt-call
  [ -z "${salt_master}" ] &&
    apt-mark manual salt-common &&
    apt-get remove -y salt-minion
}

make_salt_mastered() {
  local bundle_etc_salt_dir="$BUNDLE_DIR/etc/salt"
  local bundle_etc_systemd_dir="$BUNDLE_DIR/etc/systemd/system"

  local salt_master=$1
  if [ -n "${salt_master}" ]; then
    echo ""
    highlight "Configuring mastered salt-minion..."
    local mastered_etc_dir="/etc/salt-mastered"
    mkdir -p "${mastered_etc_dir}"
    cp "${bundle_etc_salt_dir}/minion-mastered.host" ${mastered_etc_dir}/minion
    sed -i "s,master: salt,master: $salt_master,g" ${mastered_etc_dir}/minion
    cp "${bundle_etc_systemd_dir}/salt-mastered.service" /etc/systemd/system/salt-mastered.service
    systemctl daemon-reload
    systemctl enable salt-mastered
    systemctl start salt-mastered
  fi
}

clean_salt_files() {
  local prefix=$1

  echo ""
  highlight "Cleaning existing salt files..."

  echo_run rm -rf "${prefix}${SALT_STATE_DIR}/*"
  echo_run rm -rf "${prefix}${SALT_PILLAR_DIR}/*"

  for p in "${SALT_PURGE_PATHS[@]}"; do
    if [ -e "$p" ]; then
      echo_run rm -rf "$p"
    fi
  done
}

install_salt_files() {
  local dir=$1
  local prefix=$2

  echo ""
  highlight "Installing salt files: $dir"

  if [ -d $dir/state ]; then
    echo_run rsync -a $dir/state/ "${prefix}${SALT_STATE_DIR}/"
  fi
  if [ -d $dir/pillar ]; then
    echo_run rsync -a $dir/pillar/ "${prefix}${SALT_PILLAR_DIR}/"
  fi
}

# Usage: install_salt_local_files <prefix> <files>
# Example: install_salt_local_files "" git.sls secrets.sls
install_salt_local_files() {
  local prefix="$1"

  echo ""
  highlight "Installing local salt files"

  if [ -e "${prefix}${SALT_PILLAR_DIR}/local.sls" ]; then
    rm -f "${prefix}${SALT_PILLAR_DIR}/local.sls"
  fi

  echo_run ln -s "${prefix}${SALT_PILLAR_LOCAL}" "${prefix}${SALT_PILLAR_DIR}/local.sls"

  install_salt_local_files_list "${prefix}" "${@:2}"
}

# Usage: install_salt_local_files_list <prefix> <files>
# Example: install_salt_local_files_list "${luks_mnt}" git.sls secrets.sls
install_salt_local_files_list() {
  local prefix="$1"
  local files_to_copy=("${@:2}")

  echo_run mkdir -p "${prefix}${SALT_PILLAR_DIR}/local"

  for f in "${files_to_copy[@]}"; do
    if [ -e "/root/.salt-local/${f}" ]; then
      echo_run cp -f "/root/.salt-local/${f}" "${prefix}${SALT_PILLAR_DIR}/local/${f}"
    fi
  done
}

install_salt_profile() {
  local profile=$1
  local base=$2

  if [ -z "${profile}" ]; then
    die "profile arg required"
  fi
  if [ "${profile}" != "prov" ] && [ "${profile}" != "node" ]; then
    die "profile arg invalid (valid: prov or node)"
  fi

  if [ -z "${base}" ]; then
    base=$(readlink -f "$COMPONENT_DIR/..")
  fi

  clean_salt_files ""
  install_salt_files "$base/components/common/salt"
  install_salt_files "$base/components/internal/salt"
  install_salt_files "$base/${profile}/salt"
  install_salt_local_files "" git.sls secrets.sls secrets-prov.sls defaults.sls users.sls security.sls logging.sls blockchain.sls
}

generate_pillar_local() {
  local cloud_provider=$1
  local cloud_provider_class=$2
  local net4_ip=$3
  local net4_gw=$4

  if [ -n "${cloud_provider}" ]; then
    {
      echo "include:"
      echo "  - cloud.provider.${cloud_provider}.defaults"
      if [ -n "${cloud_provider_class}" ]; then
        echo "  - cloud.provider.${cloud_provider}.${cloud_provider_class}"
      fi
      echo ""

      if [ -n "${net4_ip}" ] && [ -n "${net4_gw}" ]; then
        echo "net_out_ip4: $net4_ip"
        echo "net_out_gw4: $net4_gw"
      fi
    } >$SALT_PILLAR_LOCAL
  else
    local total_ifaces=$(ip addr show | grep "state UP" | wc | awk '{ print $1 }')
    local net_iface_0=$(ip addr show | grep "state UP" | head -n 1 | awk '{ print $2 }' | sed 's/[:].*//g')
    if [ "$total_ifaces" == "2" ]; then
      local net_iface_1=$(ip route show | grep "default via" | tail -n 1 | awk '{ print $5 }')
    fi

    if [ -z "${net4_ip}" ] && [ -z "${net4_gw}" ]; then
      local net4_gw=$(ip route show | grep "default via" | head -n 1 | awk '{ print $3 }')
      local net4_gw_dev=$(ip route show | grep "default via" | head -n 1 | awk '{ print $5 }')
      local net4_ip=$(ip address show "$net4_gw_dev" | grep "inet " | awk '{ print $2 }')
    fi

    {
      echo "net_iface0: $net_iface_0"
      echo "net_iface1: $net_iface_1"
      echo "net_out_ip4: $net4_ip"
      echo "net_out_gw4: $net4_gw"
    } >$SALT_PILLAR_LOCAL
  fi

  [ -e "$SALT_PILLAR_DIR/local.sls" ] && rm "$SALT_PILLAR_DIR/local.sls"
  echo_run ln -s $SALT_PILLAR_LOCAL "$SALT_PILLAR_DIR/local.sls"
}

salt_call_state_apply() {
  local static_pillar="$1"

  echo ""
  highlight "Applying salt state..."

  # echo_run isn't compatible
  # TODO: Fix echo_run
  echo "salt-call --local --force-color --hard-crash --log-file-level=debug --state-output=mixed state.highstate ${static_pillar}"
  if [ -n "${static_pillar}" ]; then
    salt-call --local --force-color --hard-crash --log-file-level=debug --state-output=mixed state.highstate ${static_pillar}
  else
    salt-call --local --force-color --hard-crash --log-file-level=debug --state-output=mixed state.highstate
  fi
}

salt_call_pillar_item() {
  salt-call --local --out key pillar.item "${1}" | tail -n1 | cut -d : -f 2- | cut -d ' ' -f 3-
}

salt_call_pillar_item_array() {
  salt_call_pillar_item "${1}" | tr "'" '"' | jq -c '.[]' | sed 's_"__g'
}

# Git

salt_call_bootstrap_litos_repo() {
  echo ""
  highlight "Checking out lit-os repo..."

  salt-call --local --state-output=mixed state.sls lit.os.repo
}

salt_call_git_repo_url() {
  local repo_name="${1}"

  salt_call_pillar_item "git_repo:${repo_name}:url"
}

salt_call_git_repo_branch() {
  local repo_name="${1}"
  local env="${2}"

  if [ -z "${env}" ]; then
    env="default"
  fi

  salt_call_pillar_item "git_repo:${repo_name}:branch:${env}"
}

salt_call_git_repo_public() {
  local repo_name="${1}"

  salt_call_pillar_item "git_repo:${repo_name}:public"
}

salt_call_git_repo_branch_with_default() {
  local repo_name="${1}"
  local env="${2}"

  local branch

  branch=$(ensure salt_call_git_repo_branch "${repo_name}" "${env}")
  if [ -z "${branch}" ]; then
    branch=$(ensure salt_call_git_repo_branch "${repo_name}" "default")
  fi

  echo "$branch"
}

salt_call_git_clone() {
  local dir="${1}"
  local repo_name="${2}"
  local env="${3}"

  if [ -z "${dir}" ]; then
    die "dir arg required for salt_call_git_checkout"
  fi
  if [ -z "${repo_name}" ]; then
    die "repo_name arg required for salt_call_git_checkout"
  fi

  local url
  local branch
  local public

  url=$(ensure salt_call_git_repo_url "${repo_name}")
  branch=$(ensure salt_call_git_repo_branch_with_default "${repo_name}" "${env}")
  public=$(ensure salt_call_git_repo_public "${repo_name}")

  if [ -z "${url}" ]; then
    die "failed to determine git url for ${repo_name}"
  fi
  if [ -z "${branch}" ]; then
    die "failed to determine git branch for ${repo_name} (env: ${env})"
  fi

  echo "Checking out git repo: $repo_name (url: $url, branch: $branch)"
  if [ "${public}" == "True" ]; then
    salt-call --local git.clone ${dir} ${url} user=git >/dev/null
  else
    salt-call --local git.clone ${dir} ${url} user=git identity="/home/git/.ssh/id_git_${repo_name}" >/dev/null
  fi
  salt-call --local git.checkout ${dir} ${branch} user=git >/dev/null
}
