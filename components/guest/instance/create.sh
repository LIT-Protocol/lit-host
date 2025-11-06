#!/bin/bash
#
#

set -e
trap cleanup ERR EXIT

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
COMMON_BASE_DIR="$SCRIPT_DIR/../../common"
COMMON_SCRIPT_DIR="$COMMON_BASE_DIR/scripts"

. "$COMMON_SCRIPT_DIR/common.sh"
. "$COMMON_SCRIPT_DIR/salt.sh"
. "$SCRIPT_DIR/common.sh"

INSTANCE_ID=""
INSTANCE_NAME=""
INSTANCE_PATH=""
INSTANCE_LABELS=""
RELEASE="0"
TEMPLATE_PATH=""
FROM_PATH=""

START_INSTANCE=""
FOLLOW_LOGS=""
SELF_SIGNED=""
SAFE_BOOT=""
SUBNET_ID=""
ONESHOT=""
BOOTSTRAP=""

GUEST_VCPUS="4"
GUEST_MEM="4G"
GUEST_IMG_SIZE="80G"
GUEST_NO_IMG_RESIZE="0"

NET4_IP=""
NET4_GW=""
NET6_IP=""
NET6_GW=""

PATH=/opt/AMDSEV/usr/local/bin:$PATH

usage() {
  if [ "${LIT_CLI}" = "1" ]; then
    exit 1
  fi

	stderr "$0 [options]"
  stderr
  stderr "Create a Lit-OS guest instance."
  stderr
	stderr "Options:"
  stderr
	stderr " -id <ID>           instance id"
	stderr " -name <STR>        instance name (default: '<TYPE>-<ENV>-<ID>')"
	stderr " -labels <STR>      instance labels (separated by spaces)"
	stderr " -path <PATH>       instance install path"
	stderr " -from-path <PATH>  instance path to use as a source for create"
	stderr " -template <PATH>   guest template to use (use this OR -release)"
	stderr " -release           installation from a release download"
	stderr " -oneshot           handle oneshot commands"
	stderr " -bootstrap         handle oneshot bootstrap"
	stderr " -self-signed       self signed instance (no prov)"
	stderr " -subnet-id         subnet id (for self-signed)"
	stderr " -safe-boot         safe boot (no network, only with -self-signed)"
	stderr " -start             start the guest"
	stderr " -f | -follow       follow when starting"
	stderr " -vcpus <NUM>       number of VCPUs to allocate (default: $GUEST_VCPUS)"
	stderr " -mem <STR>         memory to allocate (default: $GUEST_MEM)"
	stderr " -img-size <STR>    extra storage to allocate (default: $GUEST_IMG_SIZE)"
	stderr " -no-img-resize     do not resize the guest image"
	stderr " -net4-ip <IP/CIDR> IPv4 network IP (default: dhcp)"
	stderr " -net4-gw <IP>      IPv4 network gateway (default: dhcp)"
	stderr " -net6-dhcp         IPv6 network use DHCP"
	stderr " -net6-ip <IP/CIDR> IPv6 network IP"
	stderr " -net6-gw <IP>      IPv6 network gateway"
  stderr
	exit 1
}

cleanup() {
	echo
	highlight "Cleaning up..."

}

process_oneshot() {
  echo ""
  highlight "Processing oneshot launch"

  echo ""
  $LITOS_GUEST_LAUNCH_SCRIPT -path "$INSTANCE_PATH" -vcpus $GUEST_VCPUS -mem 2G -oneshot

	cd "$INSTANCE_PATH"

  if [ "${BOOTSTRAP}" == "1" ]; then
    echo ""
    highlight "Processing oneshot output for bootstrap"

    local out_dir="./oneshot.output/bootstrap"
    if [ -e "${out_dir}" ]; then
      for r in "id"; do
        local cur_dir="${out_dir}/$r"
        if [ -e "${cur_dir}" ]; then
          if [ -e "./${r}" ]; then
            [ -e "./${r}.bak" ] && rm -rf "./${r}.bak"
            mv "./${r}" "./${r}.bak"
          fi

          install -o root -g root -m 700 -d "./${r}"
          install -o root -g root -m 600 "${cur_dir}"/* ./"${r}"/
        else
          die "Missing: ${cur_dir}"
        fi
      done
    else
      die "Missing: ${out_dir}"
    fi
  else
    die "Unhandled oneshot"
  fi

  # Clean up.
  [ -e "./oneshot.output" ] && rm -rf "./oneshot.output"
}

create_self_signed_id() {
  local id_path="./id"

  echo ""
  highlight "Generating self-signed ID"

  if [ -n "${SUBNET_ID}" ]; then
    # Amend the cmdline to include the subnet id
    echo "$(ensure cat ./guest-vmlinuz.cmdline) litos.subnet_id=${SUBNET_ID}" > ./guest-vmlinuz.cmdline
  fi

  local measurement=$(ensure sev-snp-measure --mode snp --vcpus ${GUEST_VCPUS} --vcpu-type ${BUILD_CPU_TYPE} \
    --ovmf ./amd/OVMF.fd --kernel ./guest-vmlinuz --append "$(ensure cat ./guest-vmlinuz.cmdline)" \
    --initrd ./guest-initrd.img --guest-features 0x1 --vmm-type QEMU)
  if [ -z "${measurement}" ]; then
    die "Failed to get measurement from sev-snp-measure"
  fi

  echo "Measurement: ${measurement}, VCPUs: ${GUEST_VCPUS}, VCPU Type: ${BUILD_CPU_TYPE}"

  mkdir "${id_path}"
  cd "${id_path}"

  echo "${measurement}" > ./measurement
  echo "${BUILD_CPU_TYPE}:${GUEST_VCPUS}" > ./state

  openssl genpkey -algorithm ec -pkeyopt ec_paramgen_curve:"P-384" -out ./author-key.pem

  openssl genpkey -algorithm ec -pkeyopt ec_paramgen_curve:"P-384" -out ./id-key.pem
  openssl pkey -in id-key.pem -pubout -out ./id-key.pub

  sev-host-identity -b -d ${measurement} -a ./auth_info.b64 -i ./id_block.b64 -p 0x30000 ./id-key.pem ./author-key.pem

  cd ..
}

render_rpc_overlay_from_secrets() {
  local ci_dir="$1"
  local secrets_file="/root/.salt-local/secrets.sls"
  local rpc_overlay_file="${ci_dir}/rpc-config.overlay.yaml"

  if [ -f "$secrets_file" ]; then
    if ! command -v yq &>/dev/null; then
      # Using yq to fetch the private chains, hence required.
      echo "yq is not installed. Please install it to proceed." >&2
      exit 1
    fi

    # Checking if the 'private_rpc_chains' key exists in the secrets file
    if yq -e '.private_rpc_chains' "$secrets_file" >/dev/null 2>&1; then
      echo "Found 'private_rpc_chains' in secrets file, creating overlay..."

      # Creating the rpc-config.overlay.yaml file
      yq '{chains: .private_rpc_chains}' "$secrets_file" >"$rpc_overlay_file"

      echo "rpc-config.overlay.yaml created in ${rpc_overlay_file}"
    fi
  fi
}

create_cloud_init() {
  local ci_dir="cloud-init"

  echo ""
  highlight "Creating cloud-init"

  mkdir -p ./${ci_dir}

  render_rpc_overlay_from_secrets ./${ci_dir}

  if [ "${SELF_SIGNED}" == "1" ]; then
    if [ ! -f "./${ci_dir}/.init.pw" ]; then
      cp -f "${TEMPLATE_PATH}/.init.pw" "./${ci_dir}/.init.pw"
      chown root:root "./${ci_dir}/.init.pw"
      chmod 600 "./${ci_dir}/.init.pw"
    fi

    if [ "${SAFE_BOOT}" == "1" ]; then
      echo 1 > "./${ci_dir}/.safe-boot"
    fi
  fi

  cat > "./${ci_dir}/meta-data" <<-EOF
{
  "instance-id": "${INSTANCE_HOSTNAME}.${INSTANCE_DOMAIN}"
}
EOF

  cat > "./${ci_dir}/user-data" <<-EOF
#cloud-config
fqdn: ${INSTANCE_HOSTNAME}.${INSTANCE_DOMAIN}
EOF

  cat > "./${ci_dir}/network-config" <<-EOF
#cloud-config
version: 2
ethernets:
  enp0s2:
    dhcp4: true
    dhcp6: false
  enp0s3:
    optional: true
EOF

  if [ -n "${NET4_IP}" ] && [ -n "${NET4_GW}" ]; then
    cat >> "./${ci_dir}/network-config" <<-EOF
    dhcp4: false
    addresses:
      - $NET4_IP
    gateway4: $NET4_GW
EOF
  else
    cat >> "./${ci_dir}/network-config" <<-EOF
    dhcp4: true
EOF
  fi

  if [ -n "${NET6_IP}" ]; then
    if [ "${NET6_IP}" == "dhcp" ]; then
      cat >> "./${ci_dir}/network-config" <<-EOF
    dhcp6: true
EOF
    else
      if [ -n "${NET6_IP}" ] && [ -n "${NET6_GW}" ]; then
        cat >> "./${ci_dir}/network-config" <<-EOF
    dhcp6: false
    addresses:
      - $NET6_IP
    gateway6: $NET6_GW
EOF
      fi
    fi
  fi

  if [ -n "${FROM_PATH}" ]; then
    if [ -z "${NET4_IP}" ] && [ -z "${NET6_IP}" ]; then
      if [ -e "${FROM_PATH}/${ci_dir}/network-config" ]; then
        cp -f "${FROM_PATH}/${ci_dir}/network-config" "./${ci_dir}/"
      fi
    fi
  fi
}

install_from_template() {
  highlight "Installing instance from template (BUILD_ID: $BUILD_ID)"

  cp -rf $TEMPLATE_PATH/* $INSTANCE_PATH/
  [ -e "$INSTANCE_PATH/releases" ] && rm -rf "$INSTANCE_PATH/releases"
  mkdir build
  mv build*.* build/

  if [ -n "${SUBNET_ID}" ]; then
    local rel_path="${TEMPLATE_PATH}/releases/${SUBNET_ID}"
    if [ -e "${rel_path}" ]; then
      echo "Installing subnet ($SUBNET_ID) release assets"

      install -o root -g root -d "$INSTANCE_PATH/releases/${SUBNET_ID}"
      install -o root -g root -m 600 "${rel_path}"/* "$INSTANCE_PATH/releases/${SUBNET_ID}"/
    fi
  fi
}

resize_image() {
  echo ""
  highlight "Resizing guest image (adding: $GUEST_IMG_SIZE)"

  echo_run qemu-img resize -f qcow2 ./guest-disk.qcow2 "+${GUEST_IMG_SIZE}"
  echo_run qemu-nbd -d /dev/nbd8
  echo_run qemu-nbd -c /dev/nbd8 -f qcow2 ./guest-disk.qcow2
  sleep 0.5 # give QEMU some time to register the virtual blockdev
  echo_run sgdisk -e /dev/nbd8
  echo_run qemu-nbd -d /dev/nbd8
}

main() {
  local build_env="build.env"
  local instance_env="instance.env"

	# Check arguments
	if [ -z "${INSTANCE_PATH}" ] || [ -z "${GUEST_VCPUS}" ] || [ -z "${GUEST_MEM}" ]; then
		usage
	fi
	if [ -z "${TEMPLATE_PATH}" ] && [ "${RELEASE}" == "0" ]; then
	  usage
	fi
  if [ -n "${TEMPLATE_PATH}" ] && [ "${RELEASE}" == "1" ]; then
    stderr "ERROR: -template OR -release is required, not both."
    stderr
    usage
  fi
  if [ "${SELF_SIGNED}" == "1" ] && [ "${RELEASE}" == "1" ]; then
    stderr "ERROR: -self-signed cannot be used with -release option."
    stderr
    usage
  fi

	if [ -n "${NET4_IP}" ] || [ -n "${NET4_GW}" ]; then
	  if [ -z "${NET4_IP}" ] || [ -z "${NET4_GW}" ]; then
	    stderr "ERROR: -net4-ip and -net4-gw required or neither."
	    stderr
		  usage
		fi
	fi

  if [ -n "${NET6_IP}" ] || [ -n "${NET6_GW}" ]; then
    if [ "${NET6_IP}" == "dhcp" ]; then
      if [ -n "${NET6_GW}" ]; then
        stderr "ERROR: -net6-dhcp and -net6-gw can not be used together."
        stderr
        usage
      fi
    else
      if [ -z "${NET6_IP}" ] || [ -z "${NET6_GW}" ]; then
        stderr "ERROR: -net6-ip and -net6-gw required or neither."
        stderr
        usage
      fi
    fi
  fi
  if [ "${SAFE_BOOT}" == "1" ]; then
      if [ "${SELF_SIGNED}" != "1" ]; then
          stderr "ERROR: -safe-boot can only be used with -self-signed."
          stderr
          usage
      fi
  fi

  if [ -n "${TEMPLATE_PATH}" ]; then
    if [ ! -d "${TEMPLATE_PATH}" ]; then
      die "Template directory not found: $TEMPLATE_PATH"
    fi
    if [ ! -f "${TEMPLATE_PATH}/${build_env}" ]; then
      die "Template build.env file not found: $TEMPLATE_PATH/$build_env"
    fi

    . "${TEMPLATE_PATH}/${build_env}"
  else
    if [ ! -f "${INSTANCE_PATH}/build/${build_env}" ]; then
      die "Release build.env file not found: ${INSTANCE_PATH}/build/${build_env}"
    fi

    . "${INSTANCE_PATH}/build/${build_env}"
  fi

  if [ -n "${FROM_PATH}" ] && [ ! -d "${FROM_PATH}" ]; then
    stderr "ERROR: -from-path ($FROM_PATH) not found"
    stderr
    usage
  fi

  export INSTANCE_NAME_SUFFIX="${INSTANCE_NAME}"
  if [ -z "${INSTANCE_NAME}" ]; then
    if [ "${BUILD_TYPE}" == "custom" ]; then
      INSTANCE_NAME="${BUILD_KIND}-${BUILD_RELEASE}-${INSTANCE_ID}"
    else
      INSTANCE_NAME="${BUILD_TYPE}-${BUILD_RELEASE}-${INSTANCE_ID}"
    fi

  else
    if ! [[ $INSTANCE_NAME =~ ^[a-z]+[a-z0-9-]*[a-z0-9]+$ ]]; then
      die "-name ($INSTANCE_NAME) is invalid (can match ^[a-z]+[a-z0-9-]*[a-z0-9]+$ only)."
    fi

    if [ "${BUILD_TYPE}" == "custom" ]; then
      INSTANCE_NAME="${BUILD_KIND}-${BUILD_RELEASE}-${INSTANCE_ID}-${INSTANCE_NAME}"
    else
      INSTANCE_NAME="${BUILD_TYPE}-${BUILD_RELEASE}-${INSTANCE_ID}-${INSTANCE_NAME}"
    fi

  fi

  INSTANCE_HOSTNAME="${INSTANCE_NAME}"
  INSTANCE_DOMAIN="${BUILD_DOMAIN}"
  INSTANCE_SERVICE="litos-guest-${INSTANCE_NAME}.service"
  INSTANCE_SERVICE_FILE="/etc/systemd/system/${INSTANCE_SERVICE}"

  if [ -e "${INSTANCE_SERVICE_FILE}" ]; then
    die "Conflict, service already exists: ${INSTANCE_SERVICE_FILE}"
  fi

  mkdir -p $INSTANCE_PATH
  cd $INSTANCE_PATH

  if [ -n "${TEMPLATE_PATH}" ]; then
	  install_from_template
	fi

  create_cloud_init

  echo ""
	highlight "Writing ${instance_env}"

  {
    echo "# Instance Env Meta";
    echo "";
    echo "BUILD_ID=\"$BUILD_ID\"";
    echo "SUBNET_ID=\"$SUBNET_ID\"";
    echo "INSTANCE_ID=\"$INSTANCE_ID\"";
    echo "INSTANCE_NAME=\"$INSTANCE_NAME\"";
    if [ -n "${INSTANCE_NAME_SUFFIX}" ]; then
      echo "INSTANCE_NAME_SUFFIX=\"$INSTANCE_NAME_SUFFIX\"";
    fi
    if [ -n "${INSTANCE_LABELS}" ]; then
      echo "INSTANCE_LABELS=\"$INSTANCE_LABELS\"";
    fi
    if [ "${SELF_SIGNED}" == "1" ]; then
      echo "INSTANCE_SELF_SIGNED=\"$SELF_SIGNED\"";
    fi
    if [ "${RELEASE}" == "1" ]; then
      echo "INSTANCE_RELEASE=\"$RELEASE\"";
    fi
    echo "INSTANCE_UNIX=\"$(date +%s)\"";
    echo "INSTANCE_DATE=\"$(date "+%d-%b-%Y %T %Z")\"";
    echo "INSTANCE_SERVICE=\"$INSTANCE_SERVICE\"";
    echo "INSTANCE_VCPUS=\"$GUEST_VCPUS\"";
    echo "INSTANCE_MEM=\"$GUEST_MEM\"";
    if [ "${GUEST_NO_IMG_RESIZE}" == "0" ] && [ -n "$GUEST_IMG_SIZE" ]; then
      echo "INSTANCE_IMG_SIZE=\"$(expr "$(echo "$BUILD_IMG_SIZE" | tr -d 'G')" + "$(echo "$GUEST_IMG_SIZE" | tr -d 'G')")G\"";
    else
      echo "INSTANCE_IMG_SIZE=\"$BUILD_IMG_SIZE\"";
    fi
    echo "INSTANCE_NET_INT_MAC=\"$(echo "${INSTANCE_ID}.int"|md5sum|sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')\"";
    echo "INSTANCE_NET_EXT_MAC=\"$(echo "${INSTANCE_ID}.ext"|md5sum|sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')\"";
  } > ${instance_env}

  if [ "${SELF_SIGNED}" == "1" ]; then
    create_self_signed_id
  fi
  if [ "${ONESHOT}" == "1" ]; then
    process_oneshot
  fi

  if [ "${GUEST_NO_IMG_RESIZE}" == "0" ]; then
    resize_image
  fi
  init_logging_facilities
  create_systemd_service

	echo
	highlight "Successfully created ${INSTANCE_ID}!"

	if [ -n "${FOLLOW_LOGS}" ] &&[ "${FOLLOW_LOGS}" == "1" ]; then
	  if [ -n "${START_INSTANCE}" ] && [ "${START_INSTANCE}" == "1" ]; then
	    echo
      highlight "Following logs..."
      echo

      journalctl -f -u $INSTANCE_SERVICE --output cat
    fi
	fi

	exit 0
}

if [ `id -u` -ne 0 ]; then
	stderr "Must be run as root!"
	exit 1
fi

while [ -n "$1" ]; do
	case "$1" in
		-id)            INSTANCE_ID="$2"
				shift
				;;
		-name)          INSTANCE_NAME="$2"
				shift
				;;
		-labels)        INSTANCE_LABELS="$2"
				shift
				;;
		-path)          INSTANCE_PATH="$2"
				shift
				;;
		-template)      TEMPLATE_PATH="$2"
				shift
				;;
		-from-path)     FROM_PATH="$2"
				shift
				;;
		-release)       RELEASE="1"
				;;
		-oneshot)       ONESHOT="1"
				;;
    -bootstrap)     BOOTSTRAP="1"
        ;;
		-start)         START_INSTANCE="1"
				;;
		-follow|-f)     FOLLOW_LOGS="1"
		    ;;
		-self-signed)   SELF_SIGNED="1"
				;;
		-subnet-id)     SUBNET_ID="$2"
		    shift
				;;
		-safe-boot)     SAFE_BOOT="1"
				;;
		-vcpus)         GUEST_VCPUS="$2"
				shift
				;;
		-mem)           GUEST_MEM="$2"
				shift
				;;
		-img-size)      GUEST_IMG_SIZE="$2"
				shift
				;;
		-no-img-resize) GUEST_NO_IMG_RESIZE="1"
				;;
		-net4-ip)       NET4_IP="$2"
				shift
				;;
		-net4-gw)       NET4_GW="$2"
				shift
				;;
		-net6-dhcp)     NET6_IP="dhcp"
				shift
				;;
		-net6-ip)       NET6_IP="$2"
				shift
				;;
		-net6-gw)       NET6_GW="$2"
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

if [ -z "$INSTANCE_ID" ]; then
  INSTANCE_ID=$(uuid)
fi

modprobe nbd

main $@
