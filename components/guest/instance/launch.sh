#!/bin/bash
#
#

set -e

trap 'cleanup' ERR EXIT SIGHUP SIGINT

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
COMMON_BASE_DIR="$SCRIPT_DIR/../../common"
COMMON_SCRIPT_DIR="$COMMON_BASE_DIR/scripts"

. "$COMMON_SCRIPT_DIR/common.sh"
. "$COMMON_SCRIPT_DIR/salt.sh"
. "$SCRIPT_DIR/common.sh"

INSTANCE_PATH=""
VCPUS=""
MEM=""
ONESHOT=""

UEFI_CODE="./amd/OVMF.fd"

ONESHOT_MNT="./oneshot"
ONESHOT_INPUT="./oneshot.input"
ONESHOT_OUTPUT="./oneshot.output"
ONESHOT_IMG="./one-shot.qcow2"
ONESHOT_LABEL="one-shot"
ONESHOT_ROOT_PART_NR="1"
ONESHOT_SIZE="512M"
ONESHOT_NBD="/dev/nbd9"

usage() {
  if [ "${LIT_CLI}" = "1" ]; then
    exit 1
  fi

	stderr "$0 [options]"
  stderr
  stderr "Launch a Lit-OS guest instance."
  stderr
	stderr "Options:"
  stderr
	stderr " -path <PATH>       instance path"
	stderr " -vcpus <NUM>       number of VCPUs to allocate (default: instance.env)"
	stderr " -mem <STR>         memory to allocate (default: instance.env)"
	stderr " -oneshot           process oneshot actions"
  stderr
	exit 1
}


cleanup() {
  unmount_oneshot

  if [ -f ${ONESHOT_IMG} ]; then
    rm -f ${ONESHOT_IMG}
  fi

  # For SIG's
  exit 0;
}

add_qemu_opts() {
  for o in "$@"; do
    QEMU_OPTS+=("$o")
  done
}

get_cbitpos() {
  modprobe cpuid
  #
  # Get C-bit position directly from the hardware
  #   Reads of /dev/cpu/x/cpuid have to be 16 bytes in size
  #     and the seek position represents the CPUID function
  #     to read.
  #   The skip parameter of DD skips ibs-sized blocks, so
  #     can't directly go to 0x8000001f function (since it
  #     is not a multiple of 16). So just start at 0x80000000
  #     function and read 32 functions to get to 0x8000001f
  #   To get to EBX, which contains the C-bit position, skip
  #     the first 4 bytes (EAX) and then convert 4 bytes.
  #

  EBX=$(dd if=/dev/cpu/0/cpuid ibs=16 count=32 skip=134217728 | tail -c 16 | od -An -t u4 -j 4 -N 4 | sed -re 's|^ *||')
  CBITPOS=$((EBX & 0x3f))
}

create_cloud_init_iso() {
  local cloud_init_path="./cloud-init"
  local seed_filename="guest-cloud-init.iso"

  for req in "${cloud_init_path}/network-config" "${cloud_init_path}/user-data" "${cloud_init_path}/meta-data"; do
    if [ ! -f "$req" ]; then
      die "Missing file: $req"
    fi
  done

  if [ -f ./$seed_filename ]; then
    rm -f ./$seed_filename;
  fi

  # TODO: Refactor this to use arrays.
  # Use genisoimage directly to support other kinds of files (not just cloud-init).
  if [ -f "${cloud_init_path}/.init.pw" ]; then
    if [ -f "${cloud_init_path}/.safe-boot" ]; then
      genisoimage -output "./${seed_filename}" -volid cidata -joliet -rock "${cloud_init_path}"/* "${cloud_init_path}/.init.pw" "${cloud_init_path}/.safe-boot"
    else
      genisoimage -output "./${seed_filename}" -volid cidata -joliet -rock "${cloud_init_path}"/* "${cloud_init_path}/.init.pw"
    fi
  else
    if [ -f "${cloud_init_path}/.safe-boot" ]; then
      genisoimage -output "./${seed_filename}" -volid cidata -joliet -rock "${cloud_init_path}"/* "${cloud_init_path}/.safe-boot"
    else
      genisoimage -output "./${seed_filename}" -volid cidata -joliet -rock "${cloud_init_path}"/*
    fi
  fi

  if [ ! -f ./$seed_filename ]; then
    die "Missing file: $seed_filename"
  fi

  chown root:root "./${seed_filename}"
  chmod 600 "./${seed_filename}"

  readlink -f ./${seed_filename}
}

create_oneshot_image() {
  echo ""
  highlight "Creating: ${ONESHOT_IMG}"

  if [ ! -e "${ONESHOT_INPUT}" ]; then
    die "Missing oneshot input: ${ONESHOT_INPUT}"
  fi

  # Ensure it's disconnected first.
  unmount_oneshot

  echo_run qemu-img create -f qcow2 ${ONESHOT_IMG} ${ONESHOT_SIZE}
  if [ ! -f "${ONESHOT_IMG}" ]; then
    die "Missing file after 'qemu-img create': $ONESHOT_IMG"
  fi

  echo_run chown root:root ${ONESHOT_IMG}
  echo_run chmod 600 ${ONESHOT_IMG}

  echo_run qemu-nbd -c ${ONESHOT_NBD} -f qcow2 ${ONESHOT_IMG}
  sleep 0.5 # delay format operations to let the drive initialize

	echo_run sgdisk --zap-all ${ONESHOT_NBD} # wipe GPT and MBR
  echo_run sgdisk --new=${ONESHOT_ROOT_PART_NR}:0:0 ${ONESHOT_NBD}	   # /
	echo_run sgdisk --typecode=${ONESHOT_ROOT_PART_NR}:83 ${ONESHOT_NBD} # type = Linux
	echo_run sgdisk --change-name=${ONESHOT_ROOT_PART_NR}:${ONESHOT_LABEL} ${ONESHOT_NBD}
	echo_run sgdisk --print ${ONESHOT_NBD}

	echo_run mkfs.ext4 "${ONESHOT_NBD}p${ONESHOT_ROOT_PART_NR}"

	echo_run mkdir -p "${ONESHOT_MNT}"
  echo_run mount "${ONESHOT_NBD}p${ONESHOT_ROOT_PART_NR}" "${ONESHOT_MNT}"

  cp -rf "${ONESHOT_INPUT}"/* "${ONESHOT_MNT}"
  rm -rf ${ONESHOT_INPUT}

  unmount_oneshot
}

copy_oneshot_output() {
  echo ""
  highlight "Retrieving outputs from: ${ONESHOT_IMG}"

  echo_run mkdir -p "${ONESHOT_MNT}"
  echo_run qemu-nbd -d ${ONESHOT_NBD}
  echo_run qemu-nbd -c ${ONESHOT_NBD} -f qcow2 ${ONESHOT_IMG} --read-only
  echo_run blockdev --rereadpt "${ONESHOT_NBD}"
  sleep 0.5

  # Attempt to fix intermittent bug.
  # - Sometimes the partition tables aren't available on the device!??!
  for n in $(seq 1 10); do
    if [ ! -e "${ONESHOT_NBD}" ] || [ ! -e "${ONESHOT_NBD}p${ONESHOT_ROOT_PART_NR}" ]; then
      echo "NBD gone away, attempting to correct (attempt $n)"
      echo_run qemu-nbd -d ${ONESHOT_NBD}
      echo_run qemu-nbd -c ${ONESHOT_NBD} -f qcow2 ${ONESHOT_IMG} --read-only
      echo_run blockdev --rereadpt "${ONESHOT_NBD}"
      sleep 1
    else
      break;
    fi
  done

  echo_run mount "${ONESHOT_NBD}p${ONESHOT_ROOT_PART_NR}" "${ONESHOT_MNT}"

  local status_file="${ONESHOT_MNT}"/status
  if [ ! -e "${status_file}" ]; then
    die "One-shot failed (missing: $status_file)"
  fi
  local status=$(cat "${status_file}")
  if [ "${status}" != "1" ]; then
    die "One-shot failed (status not '1')"
  fi

  [ -e "${ONESHOT_OUTPUT}" ] && rm -rf "${ONESHOT_OUTPUT}"
  echo_run mkdir -p "${ONESHOT_OUTPUT}"

  cp -rf "${ONESHOT_MNT}"/* "${ONESHOT_OUTPUT}"/

  chown root:root "${ONESHOT_OUTPUT}"/*
  chmod 600 "${ONESHOT_OUTPUT}"/*

  # Remove original config (could leak sensitive info).
  if [ -e "${ONESHOT_OUTPUT}/config.yaml" ]; then
    rm "${ONESHOT_OUTPUT}/config.yaml"
  fi

  unmount_oneshot
}

unmount_oneshot() {
  if mount | grep ${ONESHOT_MNT} > /dev/null 2>&1; then
    umount -R ${ONESHOT_MNT}
    rmdir ${ONESHOT_MNT}
  fi

  if [ -e ${ONESHOT_NBD} ]; then
    qemu-nbd -d ${ONESHOT_NBD}
  fi
}

main() {
	# Check arguments
	if [ -z "${INSTANCE_PATH}" ]; then
		usage
	fi

	init_instance_env true

  highlight "Preparing..."

  if [ ! -e "${UEFI_CODE}" ]; then
        echo "Can't locate UEFI code file: $UEFI_CODE"
        usage
  fi
  UEFI_CODE="$(readlink -e ${UEFI_CODE})"

  if [ -z "$VCPUS" ]; then
    if [ -z "${INSTANCE_VCPUS}" ]; then
      die "Unable to determine VCPUs (please provide -vcpus)"
    else
      VCPUS="$INSTANCE_VCPUS"
    fi
  fi
  if [ -z "$MEM" ]; then
    if [ -z "${INSTANCE_MEM}" ]; then
      die "Unable to determine MEM (please provide -mem)"
    else
      MEM="$INSTANCE_MEM"
    fi
  fi
  if [ -z "$INSTANCE_NET_INT_MAC" ]; then
    INSTANCE_NET_INT_MAC=$(echo "${INSTANCE_ID}.int"|md5sum|sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')
  fi
  if [ -z "$INSTANCE_NET_EXT_MAC" ]; then
    INSTANCE_NET_EXT_MAC=$(echo "${INSTANCE_ID}.ext"|md5sum|sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')
  fi

  for req in "./guest-disk.qcow2" "./guest-vmlinuz" "./guest-vmlinuz.cmdline" "./guest-initrd.img"; do
      if [ ! -f "$req" ]; then
        die "Missing file: $req"
      fi
  done

  local hda_file="$(readlink -f ./guest-disk.qcow2)"
  local seed_file="$(create_cloud_init_iso)"
  local kernel_file="$(readlink -f ./guest-vmlinuz)"
  local cmdline_file="$(readlink -f ./guest-vmlinuz.cmdline)"
  local initrd_file="$(readlink -f ./guest-initrd.img)"

  # Overrides
  if [ -n "${SUBNET_ID}" ] && [ -e "./releases/${SUBNET_ID}/guest-vmlinuz.cmdline" ]; then
    local cmdline_file="$(readlink -f "./releases/${SUBNET_ID}/guest-vmlinuz.cmdline")"
  fi

  # Basic virtual machine property
  if is_amd; then
    add_qemu_opts -enable-kvm -cpu ${BUILD_CPU_TYPE} -machine q35
  else
    die "Unknown platform (not AMD)"
  fi

  # add number of VCPUs
  add_qemu_opts -smp ${VCPUS}

  # define guest memory
  add_qemu_opts -m ${MEM}

  # don't reboot for SEV-ES guest
  add_qemu_opts -no-reboot

  # The OVMF binary, including the non-volatile variable store, appears as a
  # "normal" qemu drive on the host side, and it is exposed to the guest as a
  # persistent flash device.
  if is_amd; then
    add_qemu_opts -bios ${UEFI_CODE}
  else
    add_qemu_opts -drive if=pflash,format=raw,unit=0,file=${UEFI_CODE},readonly=on
  fi

  # Configure VM networking
  # NOTE: QEMU creates/destroys tap devices automatically, but we need a startup script to attach the tap to the host bridge device
  # add network (host-only)
  add_qemu_opts -netdev tap,id=net0,ifname="vmtap0.${INSTANCE_ID}",script="/opt/AMDSEV/usr/local/etc/qemu-ifup,downscript=no"
  add_qemu_opts -device virtio-net-pci,disable-legacy=on,iommu_platform=true,netdev=net0,romfile=,mac=${INSTANCE_NET_INT_MAC}

  # add network (bridge)
  add_qemu_opts -netdev tap,id=net1,ifname="tap0.${INSTANCE_ID}",script="/opt/AMDSEV/usr/local/etc/qemu-ifup,downscript=no"
  add_qemu_opts -device virtio-net-pci,disable-legacy=on,iommu_platform=true,netdev=net1,romfile=,mac=${INSTANCE_NET_EXT_MAC}

  # add disk
  add_qemu_opts -drive file=${hda_file},if=none,id=disk0,format=qcow2
  add_qemu_opts -device virtio-scsi-pci,id=scsi0,disable-legacy=on,iommu_platform=true
  add_qemu_opts -device scsi-hd,drive=disk0

  # add cloud-init seed
  add_qemu_opts -drive if=virtio,file=${seed_file},format=raw,readonly=on

  if [ "${ONESHOT}" = "1" ]; then
    # override to ensure we don't exec the child process
    NOCONSOLE=0

    # add oneshot image
    create_oneshot_image

    add_qemu_opts -drive file=$(ensure readlink -f "$ONESHOT_IMG"),if=none,id=disk1,format=qcow2
    add_qemu_opts -device virtio-scsi-pci,id=scsi1,disable-legacy=on,iommu_platform=true
    add_qemu_opts -device scsi-hd,drive=disk1
  fi

  if is_amd; then
    # add SEV-SNP feature flags
    add_qemu_opts -machine confidential-guest-support=sev0,vmport=off
    get_cbitpos

    local id_path="./id"
    if [ -d "${id_path}" ]; then
      local state_file="$(readlink -f "${id_path}/state")"
      local state="$(ensure cat "${state_file}")"
      local id_block_file="$(readlink -f "${id_path}/id_block.b64")"
      local id_block="$(ensure cat "${id_block_file}")"
      local auth_info_file="$(readlink -f "${id_path}/auth_info.b64")"
      local auth_info="$(ensure cat "${auth_info_file}")"

      local cur_state="${BUILD_CPU_TYPE}:${VCPUS}"
      if [ "${state}" != "${cur_state}" ]; then
        die "ID State miss-match: ${state} vs ${cur_state}"
      fi

      # TODO: host-data=ZGViaWFuLTExLXNldi1zbnAK (add INSTANCE_ID in host-data to augment the key derivation).
      add_qemu_opts -object sev-snp-guest,id=sev0,cbitpos=${CBITPOS},reduced-phys-bits=1,policy=0x30000,id-block=${id_block},id-auth=${auth_info},author-key-enabled=on,kernel-hashes=on
    else
      add_qemu_opts -object sev-snp-guest,id=sev0,cbitpos=${CBITPOS},reduced-phys-bits=1,policy=0x30000,kernel-hashes=on
    fi
  fi

  # add kernel / initrd
  add_qemu_opts -kernel ${kernel_file} -append "$(cat ${cmdline_file})" -initrd ${initrd_file}

  # output options
  add_qemu_opts -nographic -serial stdio -monitor unix:monitor.sock,server,nowait

  if [ "${NOCONSOLE}" != "1" ]; then
    add_qemu_opts -monitor pty
  fi

  # services logging ( talks to lit-logging-service )
  mkdir -p ./logs
  # use virtio-serial for logging - much faster
  add_qemu_opts -chardev file,id=char1,path=./logs/otel.log
  add_qemu_opts -device virtio-serial-pci
  add_qemu_opts -device virtserialport,chardev=char1,name=com.litprotocol.logging.port0

  # Exec qemu
  echo ""
  highlight "Launching..."

  if [ "${NOCONSOLE}" != "1" ]; then
    echo "Mapping CTRL-C to CTRL-]"
    stty intr ^]

    $QEMU_EXEC "${QEMU_OPTS[@]}"

    stty intr ^c
  else
    exec "$QEMU_EXEC" "${QEMU_OPTS[@]}"
  fi

  if [ "${ONESHOT}" = "1" ]; then
    copy_oneshot_output
  fi
}

if [ `id -u` -ne 0 ]; then
	stderr "Must be run as root!"
	exit 1
fi

if is_amd; then
  EXEC_PATH="/opt/AMDSEV/usr/local"
  UEFI_PATH="$EXEC_PATH/share/qemu"
  PATH="$EXEC_PATH/bin:$PATH"
else
  die "Unknown platform (not AMD)"
fi

QEMU_EXEC="$(readlink -e "$EXEC_PATH/bin/qemu-system-x86_64")"
[ -z "$QEMU_EXEC" ] && {
  echo "Can't locate qemu executable: $QEMU_EXEC"
  usage
}

while [ -n "$1" ]; do
	case "$1" in
		-path)        INSTANCE_PATH="$2"
				shift
				;;
		-vcpus)       VCPUS="$2"
				shift
				;;
		-mem)         MEM="$2"
				shift
				;;
		-oneshot)     ONESHOT="1"
				;;
		*)
        stderr "ERROR: Invalid option: $1"
        stderr
        usage
				;;
	esac

	shift
done

modprobe nbd

main $@