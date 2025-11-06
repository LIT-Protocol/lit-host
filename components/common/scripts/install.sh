#!/bin/bash

set -e

. /etc/os-release

export OS_RELEASE="${ID}-${VERSION_ID}"

COMMON_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

COMPONENT_DIR=$(readlink -f "$COMMON_SCRIPT_DIR/../..")
BASE_DIR=$(readlink -f "$COMPONENT_DIR/..")

. $COMMON_SCRIPT_DIR/common.sh
. $COMMON_SCRIPT_DIR/salt.sh

if is_amd; then
  export TEE_SRC_DIR="/usr/local/src/amd"
  export TEE_BUILD_DIR="$TEE_SRC_DIR/build"
  export TEE_PACKAGE_DIR="$TEE_SRC_DIR/packages"
  export TEE_PACKAGE_GZ="$TEE_SRC_DIR/amd-tee-packages_${OS_RELEASE}.tar.gz"
  export TEE_SALT_TOUCH_FILE="/var/local/litos-tee-amd.install"
  export AMD_SEV_FW_MILAN="amd_sev_fam19h_model0xh_1.55.29" # https://github.com/LIT-Protocol/linux-sev/blob/e164cca955742b87d59e7dcd024c200c7a348ff1/drivers/crypto/ccp/sev-dev.c#L69
  export AMD_SEV_FW_MILAN_TARGET="amd_sev_fam19h_model0xh.sbin"
  export AMD_SEV_FW_GENOA="amd_sev_fam19h_model1xh_1.55.39"
  export AMD_SEV_FW_GENOA_TARGET="amd_sev_fam19h_model1xh.sbin"
else
  die "TEE not supported (AMD required)."
fi

## User defined
ARG_ENV=""
ARG_SUBNET_ID=""
ARG_CLOUD_PROVIDER=""
ARG_CLOUD_PROVIDER_CLASS=""
ARG_NET4_IP=""
ARG_NET4_GW=""
ARG_NET_CUSTOMS=()
ARG_IPFS_BOOTSTRAP=()
ARG_IPFS_STORAGE_MAX=""
ARG_ROOT_EMAIL=""
ARG_TIMEZONE=""

## Checks

ensure_root_via_su

## Functions

install_deps() {
	echo ""
	highlight "Installing deps..."

	apt-get update
	apt-get install git python-is-python3 rsync zip cloud-image-utils bridge-utils uml-utilities wget uuid-dev socat python3-git jq -y

	if [ ! -e "/root/.gitconfig" ]; then
		git config --global safe.directory '*'
	fi
}

check_deploy_tee_packages() {
	# Force reinstall (for prior installs)
	rm -f "$TEE_SALT_TOUCH_FILE"

	if [ ! -d $TEE_PACKAGE_DIR ]; then
		if is_amd; then
			if [ -f $TEE_PACKAGE_GZ ]; then
				cd $TEE_SRC_DIR
				echo_run tar -xzf $TEE_PACKAGE_GZ
			else
				if [ "${INSTALL_TYPE}" == "prov" ]; then
					build_tee_amd_packages
				else
					die "Missing file: $TEE_PACKAGE_GZ"
				fi
			fi
		fi
	fi
}

build_tee_amd_packages() {
	echo ""
	highlight "Building AMD TEE packages..."

	apt-get install xz-utils equivs libncurses-dev ninja-build libglib2.0-dev libpixman-1-dev acpica-tools build-essential gcc bc bison flex nasm libssl-dev libncurses5-dev libelf-dev -y

	if [ -d $TEE_BUILD_DIR ]; then
		rm -rf $TEE_BUILD_DIR
	fi

	mkdir -p $TEE_BUILD_DIR

	echo ""
	highlight "AMD TEE build: Building AMDSEV"

	cd $TEE_BUILD_DIR

	git clone https://github.com/LIT-Protocol/amdsev.git --single-branch --depth 1 --branch lit # this branch tracks upstream `snp-latest``
	cd amdsev

	# Cleanup old/stale submodules
	rm -rf ovmf qemu linux

	# Build (build.sh initializes the repos to what's in stable-commits)
	./build.sh --package

	# Package
	echo ""
	highlight "AMD TEE build: Packaging..."

	mkdir -p $TEE_PACKAGE_DIR
	cd $TEE_PACKAGE_DIR
	tar -xzvf $TEE_BUILD_DIR/amdsev/snp-release-*.tar.gz
	mv snp-release-* snp-release-current

  # RAD/TODO: In case it's needed directly in this script
  apt-get install openssl -y

  # SEV Firmware taken from https://www.amd.com/en/developer/sev.html
  # Need to rename for when its copied to /lib/firmware/amd
  highlight "AMD TEE FW: Packaging..."
  if ! (is_milan || is_genoa); then
    die "Only AMD Milan and Genoa-class EPYC CPUs are supported"
  fi
  mkdir firmware
  cd firmware
  for cpu in "MILAN" "GENOA"; do
    FW_BUNDLE="AMD_SEV_FW_$cpu"
    FW_BUNDLE="${!FW_BUNDLE}"
    FW_TARGET="AMD_SEV_FW_${cpu}_TARGET"
    FW_TARGET="${!FW_TARGET}"
    echo_run wget https://download.amd.com/developer/eula/sev/${FW_BUNDLE}.zip
    echo_run unzip ${FW_BUNDLE}.zip
    # Expected Firmware location https://github.com/LIT-Protocol/linux-sev/blob/e164cca955742b87d59e7dcd024c200c7a348ff1/drivers/crypto/ccp/sev-dev.c#L69 
    echo_run mv ${FW_BUNDLE}.sbin ${FW_TARGET}
    rm -f *.zip
  done

  cd $TEE_SRC_DIR
  tar -czvf $TEE_PACKAGE_GZ packages
}

main() {
	local env="$ARG_ENV"

	if [ -z "$env" ]; then
		env="dev"
	fi

	[ -z "$INSTALL_TYPE" ] && die "INSTALL_TYPE not set"

	# Check requirements.
	if [ ! -e "/root/.salt-local/secrets.sls" ]; then
		die "Missing file: /root/.salt-local/secrets.sls"
	fi

	highlight "Installing (type: $INSTALL_TYPE, env: $env)"

	# Had an issue once with file limits.
	ulimit -n 10000

	# Install deps
	install_deps

	# Deploy packages
	check_deploy_tee_packages

	# Install salt
	mkdir -p /root/.salt-local
	{
		echo "env: ${env}"
		echo "litos_host_type: $INSTALL_TYPE"
		if [ -n "${ARG_SUBNET_ID}" ]; then
			echo "subnet_id: ${ARG_SUBNET_ID}"
		fi
		if [ -n "${ARG_ROOT_EMAIL}" ]; then
			echo "cron_email: ${ARG_ROOT_EMAIL}"
			echo "root_email: ${ARG_ROOT_EMAIL}"
		fi
		if [ -n "${ARG_TIMEZONE}" ]; then
			echo "timezone: ${ARG_TIMEZONE}"
		fi
		if ((${#ARG_NET_CUSTOMS[@]} != 0)); then
			echo "net_iface_custom_files:"
			for val in "${ARG_NET_CUSTOMS[@]}"; do
				echo "  - ${val}"
			done
		fi
		if ((${#ARG_IPFS_BOOTSTRAP[@]} != 0)); then
			echo "ipfs_bootstrap:"
			for val in "${ARG_IPFS_BOOTSTRAP[@]}"; do
				echo "  - ${val}"
			done
		fi
		if [ -n "${ARG_IPFS_STORAGE_MAX}" ]; then
			echo "ipfs_datastore_storage_max: ${ARG_IPFS_STORAGE_MAX}"
		fi
	} >"${SALT_PILLAR_LOCAL_DEFAULTS_FILE}"

	install_salt_on_host "$ARG_SALT_MASTER_HOST"
	make_salt_mastered "$ARG_SALT_MASTER_HOST"
	generate_pillar_local "$ARG_CLOUD_PROVIDER" "$ARG_CLOUD_PROVIDER_CLASS" "$ARG_NET4_IP" "$ARG_NET4_GW"

	# Install salt state
	install_salt_profile "$INSTALL_TYPE"

	# Bootstrap repo
	salt_call_bootstrap_litos_repo

	# Install salt state (again, from repo)
	install_salt_profile "$INSTALL_TYPE" /opt/assets/lit-os

	# Run salt
	salt_call_state_apply 'pillar={"is_init_install": True}'

	echo ""
	highlight "Installation complete"

	echo ""
	echo "Lit CLI has been installed, to use in current shell:"
	echo ""
	echo ". /opt/lit/env"
	echo ""
	echo "lit -h"
	echo ""

	echo ""
	highlight "Please reboot this system before use."
	echo ""
	echo "sudo reboot"
	echo ""
}

usage() {
	stderr "$0 [options]"
	stderr
	stderr "Install a Lit Os $INSTALL_TYPE host"
	stderr
	stderr "Options:"
	stderr
	stderr " --env <ENV>                   environment (default: $ARG_ENV)"
	stderr " --subnet-id <STR>             configure default subnet id"
	stderr " --net4-ip <STR>               IPv4 IP address"
	stderr " --net4-gw <STR>               IPv4 IP gateway"
	stderr " [--net-custom <FILE>]         files in /etc/network/interfaces.d to preserve (i.e. custom01)"
	stderr " [--ipfs-bootstrap <STR>]      IPFS peers to bootstrap from "
	stderr "          (i.e. 107.178.100.154:12D3KooWS3YeDTwqNrCfvQuHB94Xyhwbk8jg1MjQvBEJvd5wwtWC)"
	stderr " --ipfs-storage-max <STR>      IPFS max storage (i.e. 50G)"
	stderr " --root-email <STR>            email to send system alerts to"
	stderr " --timezone <STR>              system timezone (i.e. America/New_York)"
	stderr " --cloud-provider <STR>        cloud provider (i.e. ovh)"
	stderr " --cloud-provider-class <STR>  cloud provider class (i.e. scale)"
	stderr " --salt-master <HOST>          salt minion to connect to salt master"
	stderr " --update                      update only using the current configuration"
	stderr " --help | -h                   show this message"
	stderr
	exit 1
}

while [ -n "$1" ]; do
	case "$1" in
	--env)
		ARG_ENV="$2"
		shift
		;;
	--subnet-id)
		ARG_SUBNET_ID="$2"
		shift
		;;
	--net4-ip)
		ARG_NET4_IP="$2"
		shift
		;;
	--net4-gw)
		ARG_NET4_GW="$2"
		shift
		;;
	--net-custom)
		ARG_NET_CUSTOMS+=("$2")
		shift
		;;
	--ipfs-bootstrap)
		ARG_IPFS_BOOTSTRAP+=("$2")
		shift
		;;
	--ipfs-storage-max)
		ARG_IPFS_STORAGE_MAX="$2"
		shift
		;;
	--root-email)
		ARG_ROOT_EMAIL="$2"
		shift
		;;
	--timezone)
		ARG_TIMEZONE="$2"
		shift
		;;
	--cloud-provider)
		ARG_CLOUD_PROVIDER="$2"
		shift
		;;
	--cloud-provider-class)
		ARG_CLOUD_PROVIDER_CLASS="$2"
		shift
		;;
	--salt-master)
		ARG_SALT_MASTER_HOST="$2"
		shift
		;;
	--update)
		ARG_UPDATE="1"
		;;
	--help | -h)
		usage
		exit 0
		;;
	*)
		stderr "ERROR: Invalid option: $1"
		stderr
		usage
		;;
	esac

	shift
done

if [ "${ARG_UPDATE}" == "1" ]; then
	if [ ! -f "${SALT_PILLAR_LOCAL_DEFAULTS_FILE}" ]; then
		die "Missing file: ${SALT_PILLAR_LOCAL_DEFAULTS_FILE}, update not supported"
	fi
	if [ -n "${ARG_SUBNET_ID}" ]; then
		die "Argument --subnet-id specified, update not supported."
	fi
	if [ -n "${ARG_ENV}" ]; then
		die "Argument --env specified, update not supported."
	fi
	if [ -n "${ARG_ROOT_EMAIL}" ]; then
		die "Argument -root-email specified, update not supported."
	fi
	if [ -n "${ARG_TIMEZONE}" ]; then
		die "Argument --timezone specified, update not supported."
	fi
	if [ -n "${ARG_IPFS_BOOTSTRAP}" ]; then
		die "Argument --ipfs-bootstrap specified, update not supported."
	fi
	if [ -n "${ARG_IPFS_STORAGE_MAX}" ]; then
		die "Argument --ipfs-storage-max specified, update not supported."
	fi

	ARG_ENV="$(ensure salt_call_pillar_item env)"
	ARG_SUBNET_ID="$(ensure salt_call_pillar_item subnet_id)"
	ARG_ROOT_EMAIL="$(ensure salt_call_pillar_item root_email)"
	ARG_TIMEZONE="$(ensure salt_call_pillar_item timezone)"
	ARG_IPFS_STORAGE_MAX="$(ensure salt_call_pillar_item ipfs_datastore_storage_max)"
	ARG_IPFS_BOOTSTRAP=($(salt_call_pillar_item_array ipfs_bootstrap))
else
	if [ "$ARG_ENV" != "dev" ] && [ "$ARG_ENV" != "staging" ] && [ "$ARG_ENV" != "prod" ]; then
		stderr "ERROR: Invalid --env $ARG_ENV (valid: dev, staging, prod)"
		stderr
		usage
	fi

	if [ -n "${ARG_CLOUD_PROVIDER}" ]; then
		if [ "${ARG_CLOUD_PROVIDER}" != "ovh" ]; then
			stderr "ERROR: Invalid --cloud-provider ${ARG_CLOUD_PROVIDER} (valid: ovh)"
			stderr
			usage
		fi
	fi

	if [ -z "${ARG_SUBNET_ID}" ]; then
		stderr "ERROR: --subnet-id is a required parameter"
		stderr
		usage
	fi

	if [ -n "${ARG_CLOUD_PROVIDER_CLASS}" ]; then
		if [ "${ARG_CLOUD_PROVIDER_CLASS}" != "scale" ] && [ "${ARG_CLOUD_PROVIDER_CLASS}" != "advance" ]; then
			stderr "ERROR: Invalid --cloud-provider-class ${ARG_CLOUD_PROVIDER_CLASS} (valid: scale, advance)"
			stderr
			usage
		fi
	fi
fi

main $@
