#!/bin/bash
#
#

set -e

## Environment

PATH=/opt/AMDSEV/usr/local/bin:$PATH

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
COMMON_BASE_DIR=$(readlink -f "$SCRIPT_DIR/../../common")
COMMON_SCRIPT_DIR=$(readlink -f "$COMMON_BASE_DIR/scripts")
BUILD_BUNDLE_DIR=$(readlink -f "$SCRIPT_DIR/bundle")

. /var/lit/os/guest/build/.env
. "$COMMON_SCRIPT_DIR/common.sh"
. "$COMMON_SCRIPT_DIR/salt.sh"

TMP_DIR="./tmp"
ASSET_DIR="${TMP_DIR}/assets"
REPO_NAME="lit-os"
REPO_BASE_DIR="${ASSET_DIR}/${REPO_NAME}"
REPO_COMPONENT_DIR="${REPO_BASE_DIR}/components"
REPO_SCRIPT_DIR="${REPO_COMPONENT_DIR}/guest/build"
REPO_CUSTOM_TYPE_DIR="${REPO_COMPONENT_DIR}/guest/custom"

META_FILE="./build-meta.toml"

REF_IMG="$LITOS_GUEST_REF_IMG_DIR/$LITOS_GUEST_REF_IMG_NAME"

GUEST_IMG_NAME="guest-disk.qcow2"
GUEST_IMG_SIZE="10G"
GUEST_ROOT_SIZE="5G"

LINUX_RESERVED_PART_CODE="8300" # = Linux Filesystem
LINUX_X86_ROOT_PART_CODE="8304" # = Linux x86-64 root (/)

LUKS_ROOT_PART_NR="1"
LUKS_ROOT_PART_NAME="luks-rootfs"
LUKS_ROOT_PART_LABEL="${LUKS_ROOT_PART_NAME}"
LUKS_ROOT_DM_NAME="${LUKS_ROOT_PART_NAME}"

LUKS_VAR_PART_NR="2"
LUKS_VAR_PART_NAME="luks-varfs"
LUKS_VAR_PART_LABEL="${LUKS_VAR_PART_NAME}"
LUKS_VAR_DM_NAME="${LUKS_VAR_PART_NAME}"

LUKS_NBD="/dev/nbd0"
LUKS_ROOT_PART="${LUKS_NBD}p${LUKS_ROOT_PART_NR}"
LUKS_VAR_PART="${LUKS_NBD}p${LUKS_VAR_PART_NR}"

REF_NBD="/dev/nbd1"

TEE_AMD_EXTRA_FILES=("/opt/AMDSEV/usr/local/share/qemu/OVMF.fd")

## Args

BUILD_ID=""
BUILD_PATH=""
BUILD_CPU_TYPE=""
TYPE="node"
RELEASE="dev"
KIND=""
CUSTOM_PATH=""
CUSTOM_SOURCE="" # Not an arg.
READONLY="0"
NO_CLEANUP="0"
DO_CLEANUP="0"
VERBOSE="0"

## Node Binary Meta
NODE_BINARY_HASH="not-computed"

## State

BUILD_UNIX="$(date +%s)"
BUILD_DATE="$(date "+%d-%b-%Y %T %Z")"

usage() {
  if [ "${LIT_CLI}" = "1" ]; then
    exit 1
  fi

  stderr "$0 [options]"
  stderr
  stderr "Create a Lit-OS guest/prov QCOW2 image from a reference image."
  stderr
  stderr "Options:"
  stderr
  stderr " -type <TYPE>         creation type (default: $TYPE)"
  stderr
  stderr "    TYPE:"
  stderr
  stderr "      node:    node guest VM"
  stderr "      prov:    prov guest VM"
  stderr "      build:   prov build guest VM"
  stderr "      custom <KIND>:  custom build guest VM"
  stderr
  stderr " -release <ENV>       release type  (default: $RELEASE)"
  stderr
  stderr "    ENV:"
  stderr
  stderr "      dev:     read-write, users, ssh access, extra utils installed"
  stderr "      staging: read-only, users, ssh access"
  stderr "      prod:    read-only"
  stderr
  stderr " -ref-image <PATH>    reference image (default: $LITOS_GUEST_REF_IMG_NAME)"
  stderr " -image <PATH>        image to create (default: $GUEST_IMG_NAME)"
  stderr " -image-size <SIZE>   image size      (default: $GUEST_IMG_SIZE)"
  stderr " -root-size <SIZE>    root size       (default: $GUEST_ROOT_SIZE)"
  stderr " -id <ID>             template id     (default: \$(uuid))"
  stderr " -path <PATH>         template path   (default: $PWD)"
  stderr " -ro                  force read-only (for dev builds)"
  stderr " -no-cleanup          disable clean up"
  stderr " -cleanup             use after -no-cleanup to clean up a build"
  stderr
  exit 1
}

is_dev() {
  if [ "${RELEASE}" == "dev" ]; then
    return 0
  fi

  return 1
}

is_dev_or_staging() {
  if [ "${RELEASE}" == "dev" -o "${RELEASE}" == "staging" ]; then
    return 0
  fi

  return 1
}

cleanup() {
  echo
  if [ "${NO_CLEANUP}" != "1" ]; then
    highlight "Cleaning up..."
  else
    highlight "Cleaning up... (skipped)"
    exit 0
  fi

  # Unmount filesystems
  if mount | grep ${REF_MNT} >/dev/null 2>&1; then
    umount -R ${REF_MNT}
    rmdir ${REF_MNT}
  fi

  if mount | grep ${LUKS_MNT} >/dev/null 2>&1; then
    umount -R ${LUKS_MNT}
    rmdir ${LUKS_MNT}
  fi

  # Close the LUKS device
  [ -a /dev/mapper/${LUKS_ROOT_DM_NAME} ] && cryptsetup close ${LUKS_ROOT_DM_NAME}
  [ -a /dev/mapper/${LUKS_VAR_DM_NAME} ] && cryptsetup close ${LUKS_VAR_DM_NAME}

  cleanup_nbds

  # Remove temp files
  if [ -e "${TMP_DIR}" ]; then
    rm -rf "${TMP_DIR}"
  fi

  # For SIG's
  exit 0
}

cleanup_nbds() {
  # Disconnect the nbd devices
  if [ -e ${LUKS_NBD} ]; then
    qemu-nbd -d ${LUKS_NBD}
  fi
  if [ -e ${REF_NBD} ]; then
    qemu-nbd -d ${REF_NBD}
  fi
}

safe_bind_nbd() {
  local dev=$1
  local img=$2
  # mnt is only used to unmount existing and ensure an empty dir exists.
  local mnt=$3
  local args=("${@:4}")

  if [ -n "${mnt}" ]; then
    if mount | grep "${mnt}" >/dev/null 2>&1; then
      umount -R "${mnt}"
      rmdir "${mnt}"
    fi

    install -o root -g root -d "${mnt}"
  fi

  if [ -e ${dev} ]; then
    echo_run qemu-nbd -d ${dev}
  fi

  echo_run qemu-nbd -c ${dev} -f qcow2 ${img} "${args[@]}"
  sleep 0.5
}

create_disk_partitions() {
  local dev=${1}

  [ -z "${dev}" ] && die "disk device unspecified"

  sgdisk --zap-all ${dev}

  sgdisk --new=${LUKS_ROOT_PART_NR}:0:+${GUEST_ROOT_SIZE} ${dev} # /
  sgdisk --typecode=${LUKS_ROOT_PART_NR}:8309 ${dev}             # type = Linux LUKS
  sgdisk --change-name=${LUKS_ROOT_PART_NR}:${LUKS_ROOT_PART_NAME} ${dev}

  sgdisk --new=${LUKS_VAR_PART_NR}:0:0 ${dev}       # /var
  sgdisk --typecode=${LUKS_VAR_PART_NR}:8309 ${dev} # type = Linux LUKS
  sgdisk --change-name=${LUKS_VAR_PART_NR}:${LUKS_VAR_PART_NAME} ${dev}

  sgdisk --print ${dev}
}

get_partition_number() {
  local dev=${1}
  local code=${2^^} # Convert to upper case

  [ -z "${dev}" ] && die "block device is unspecified."
  [ -z "${code}" ] && die "partition code is unspecified."

  sgdisk --print ${dev} |
    grep "^ \+[0-9]\+" |
    sed -e 's/  */ /g' |
    cut -d ' ' -f 2,7 |
    grep ${code} |
    cut -d ' ' -f 1
}

open_luks() {
  local init_pw_file=$1

  echo_run cryptsetup open ${LUKS_ROOT_PART} ${LUKS_ROOT_DM_NAME} -q --key-file=$init_pw_file
  echo_run cryptsetup open ${LUKS_VAR_PART} ${LUKS_VAR_DM_NAME} -q --key-file=$init_pw_file
}

close_luks() {
  echo_run cryptsetup close ${LUKS_ROOT_DM_NAME}
  echo_run cryptsetup close ${LUKS_VAR_DM_NAME}
}

create_qcow2_image_and_mount() {
  local luks_mnt=$1
  local ref_mnt=$2
  local init_pw_file=$3

  # Create the base qcow2 image
  echo
  highlight "Creating qcow2 img: ${GUEST_IMG_NAME} (size: ${GUEST_IMG_SIZE}, root size: ${GUEST_ROOT_SIZE})"
  qemu-img create -f qcow2 ${GUEST_IMG_NAME} ${GUEST_IMG_SIZE}

  # Connect the image files to nbd devices
  local new_img_nbd=${LUKS_NBD}
  local ref_img_nbd=${REF_NBD}

  safe_bind_nbd "${new_img_nbd}" "${GUEST_IMG_NAME}" "${luks_mnt}"
  safe_bind_nbd "${ref_img_nbd}" "${REF_IMG}" "${ref_mnt}" --read-only

  # Partition the virtual disk
  echo
  highlight "Partitioning virtual disk..."
  create_disk_partitions ${new_img_nbd}

  # Setup LUKS partitions
  echo
  highlight "Setting up LUKS encrypted partitions..."
  echo_run cryptsetup luksFormat ${LUKS_ROOT_PART} -q --key-file=$init_pw_file --cipher aes-xts-plain64 --key-size 512 --hash sha512
  echo_run cryptsetup luksFormat ${LUKS_VAR_PART} -q --key-file=$init_pw_file --cipher aes-xts-plain64 --key-size 512 --hash sha512

  echo
  highlight "Unlocking the LUKS partitions for installation..."
  open_luks "$init_pw_file"

  # Format var filesystems (left for var)
  echo
  highlight "Formatting /var ..."
  echo_run mkfs.ext4 /dev/mapper/${LUKS_VAR_DM_NAME}

  echo
  highlight "Copying files from reference image to LUKS image..."

  # Determine which partition on the reference image contains the rootfs
  echo_run blockdev --rereadpt "${ref_img_nbd}"
  sleep 0.5
  local root_partnum=$(get_partition_number ${ref_img_nbd} ${LINUX_X86_ROOT_PART_CODE}) # prefer new partition type if exists
  if [ -z "${root_partnum}" ]; then
    root_partnum=$(get_partition_number ${ref_img_nbd} ${LINUX_RESERVED_PART_CODE}) # fall back to generic linux partition type
    if [ -z "${root_partnum}" ]; then
      die "could not find root partition number ($LINUX_X86_ROOT_PART_CODE or $LINLINUX_RESERVED_PART_CODE) on $ref_img_nbd"
    fi
  fi
  local ref_rootfs="${ref_img_nbd}p${root_partnum}"

  # Attempt to fix intermittent bug.
  # - Sometimes the partition tables aren't available on the device!??!
  for n in $(seq 1 10); do
    if [ ! -e "${ref_img_nbd}" ] || [ ! -e "${ref_rootfs}" ]; then
      echo "NBD gone away, attempting to correct (attempt $n)"
      safe_bind_nbd "${ref_img_nbd}" "${REF_IMG}" "${ref_mnt}" --read-only
      echo_run blockdev --rereadpt "${ref_img_nbd}"
      sleep 1
    else
      break
    fi
  done

  echo_run dd if=${ref_rootfs} of=/dev/mapper/${LUKS_ROOT_DM_NAME} status=progress

  if [ "${OPT_READONLY}" == "1" ]; then
    echo_run tune2fs -O ^has_journal /dev/mapper/${LUKS_ROOT_DM_NAME}
  fi
  echo_run e2fsck -p -f /dev/mapper/${LUKS_ROOT_DM_NAME}
  echo_run resize2fs /dev/mapper/${LUKS_ROOT_DM_NAME}

  echo
  highlight "Mounting images and binds..."
  echo_run install -o root -g root -d ${ref_mnt}
  echo_run mount ${ref_rootfs} ${ref_mnt}

  echo_run install -o root -g root -d ${luks_mnt}
  echo_run mount /dev/mapper/${LUKS_ROOT_DM_NAME} ${luks_mnt}

  local boot_dir=$TMP_DIR/boot
  install -o root -g root -d $boot_dir

  # Move the contents of /boot to the new boot partition
  mv ${luks_mnt}/boot ${luks_mnt}/boot.orig
  install -o root -g root -d ${luks_mnt}/boot
  echo "mount --bind ${boot_dir} /boot"
  mount --bind ${boot_dir} ${luks_mnt}/boot
  mv ${luks_mnt}/boot.orig/* ${luks_mnt}/boot
  rm -rf ${luks_mnt}/boot.orig

  # Move the contents of /var to the new partition
  mv ${luks_mnt}/var ${luks_mnt}/var.orig
  install -o root -g root -d ${luks_mnt}/var
  echo "mount /dev/mapper/${LUKS_VAR_DM_NAME} ${luks_mnt}/var"
  mount /dev/mapper/${LUKS_VAR_DM_NAME} ${luks_mnt}/var
  mv ${luks_mnt}/var.orig/* ${luks_mnt}/var
  rm -rf ${luks_mnt}/var.orig

  # Setup /var/local (for rw stuff).
  install -o root -g root -d ${luks_mnt}/var/local
  rm -rf ${luks_mnt}/var/meta_file/*

  for p in home srv; do
    if [ -d ${luks_mnt}/$p ]; then
      mv ${luks_mnt}/$p ${luks_mnt}/var/local/$p
    else
      install -o root -g root -d ${luks_mnt}/var/local/$p
    fi

    install -o root -g root -d ${luks_mnt}/$p
    echo "mount --bind /var/local/$p /$p"
    mount --bind ${luks_mnt}/var/local/$p ${luks_mnt}/$p
  done

  # Mount other stuff
  install -o root -g root -d ${luks_mnt}/opt/assets
  echo "mount --bind ${ASSET_DIR} /opt/assets"
  mount --bind ${ASSET_DIR} ${luks_mnt}/opt/assets

  # Copy these dirs to /var/local (will be used when booted, but not now)
  # - "root" will be created during the "temporary dirs" step below.
  for p in root; do
    if [ -d ${luks_mnt}/$p ]; then
      mv ${luks_mnt}/$p ${luks_mnt}/var/local/$p
    else
      install -o root -g root -d ${luks_mnt}/var/local/$p
    fi

    if [ "${p}" == "root" ]; then
      chmod 700 ${luks_mnt}/var/local/$p
    fi
  done

  # Temporary dirs (these are placed on the host to avoid the guest image getting too big)
  # NB: These are all set to 777 which should be ok as they only exist during build.
  for p in "root" "tmp" "var/tmp" "var/lib/dpkg/updates" "var/cache/apt" "var/cache/debconf" "var/cache/salt"; do
    local cur="${TMP_DIR}/${p}"
    install -o root -g root -m 777 -d "${cur}"
    [ -e "${luks_mnt}/${p}" ] && rm -rf "${luks_mnt:?}/${p}"
    install -o root -g root -m 777 -d "${luks_mnt}/${p}"
    echo "mount --bind ${cur} /${p}"
    mount --bind "${cur}" "${luks_mnt}/${p}"
  done

  # Ensure apt isn't broken.
  run_chroot_cmd ${luks_mnt} apt-get update -y
}

git_clone_and_log_meta() {
  local dir
  local meta_file
  local repo
  local env
  local branch
  local sha
  local cur_dir

  dir=$(readlink -f "${1}")
  meta_file=$(readlink -f "${2}")
  repo="$3"
  env="$4"

  salt_call_git_clone "${dir}" "${repo}" "${env}"

  branch=$(salt_call_git_repo_branch_with_default "${repo}" "${env}")
  if [ -z "${branch}" ]; then
    die "failed to determine branch for repo: $repo, env: $env"
  fi

  pushd "${dir}" >/dev/null

  sha=$(git rev-parse --short $branch)
  if [ -z "${sha}" ]; then
    die "failed to get git sha for for repo: $repo, env: $env"
  fi

  popd >/dev/null

  if [ ! -f "${meta_file}" ]; then
    echo "[versions]" >"${meta_file}"
  fi

  echo "${repo} = \"${sha}\"" >>"${meta_file}"
  echo "Added version entry (${repo} = \"${sha}\")"
}

checkout_git_deps() {
  if [ "${#GIT_DEPENDENCIES[@]}" -gt 0 ]; then
    echo
    highlight "Checking out git dependencies..."

    for repo in "${GIT_DEPENDENCIES[@]}"; do
      local repo_dir="${ASSET_DIR}/${repo}"
      git_clone_and_log_meta "${repo_dir}" "${META_FILE}" "${repo}" "${RELEASE}"
    done
  fi
}

prepare_base_system() {
  local luks_mnt=$1
  local ref_mnt=$2

  echo
  highlight "Preparing base system..."

  local dir_list="etc/network/interfaces.d"
  local file_list="etc/lit-os-release etc/hosts etc/hostname etc/udev/rules.d/70-persistent-net.rules etc/adjtime"

  rm -f ${luks_mnt}/etc/{resolv.conf,hosts}

  echo "${BUILD_HOSTNAME}" >${luks_mnt}/etc/hostname

  install_bundle ${luks_mnt} etc/resolv.conf 644 yes
  install_bundle ${luks_mnt} etc/hosts 644 yes

  if [ "${OPT_SSH}" == "1" ]; then
    local dir_list="$dir_list etc/ssh"
  fi

  install -o root -g root -d ${luks_mnt}/var/local/etc/network
  install -o root -g root -d ${luks_mnt}/var/local/etc/udev/rules.d

  for dir in $dir_list; do
    if [ -d ${luks_mnt}/$dir ]; then
      mv ${luks_mnt}/$dir ${luks_mnt}/var/local/$dir
    else
      install -o root -g root -d ${luks_mnt}/var/local/$dir
    fi

    echo "ln -s /var/local/$dir /$dir"
    ln -s /var/local/$dir ${luks_mnt}/$dir
  done

  for file in $file_list; do
    if [ -f ${luks_mnt}/$file ]; then
      mv ${luks_mnt}/$file ${luks_mnt}/var/local/$file
    else
      touch ${luks_mnt}/var/local/$file
    fi

    echo "ln -s /var/local/$file /$file"
    ln -s /var/local/$file ${luks_mnt}/$file
  done
}

run_chroot_cmd() {
  local new_root=${1}
  shift

  [ -z "${new_root}" ] && die "new root directory is empty!"
  [ ${#} -eq 0 ] && die "no command specified!"

  # Mount /dev and virtual filesystems inside the chroot
  mount --bind /dev ${new_root}/dev
  mount --bind /dev/pts ${new_root}/dev/pts
  mount -t proc proc ${new_root}/proc
  mount -t sysfs sysfs ${new_root}/sys
  mount -t tmpfs tmpfs ${new_root}/run

  # Bind mount /etc/resolv.conf to enable DNS within the chroot jail
  local resolv=$(realpath -m ${new_root}/etc/resolv.conf)
  local parent=$(dirname ${resolv})
  [ ! -d "${parent}" ] && install -o root -g root -d ${parent}
  touch ${resolv}
  mount --bind /etc/resolv.conf ${resolv}

  chroot "${new_root}" \
    /usr/bin/env -i HOME=/root TERM="${TERM}" PATH=/usr/bin:/usr/sbin DEBIAN_FRONTEND=noninteractive \
    "${@}"

  # Unmount virtual filesystems
  umount ${resolv}
  umount ${new_root}/dev{/pts,}
  umount ${new_root}/{sys,proc,run}
}

install_bundle() {
  local path=$1
  local file=$2
  local mode=$3
  local is_template=$4

  if [ -z "${is_template}" ]; then
    is_template="no"
  fi

  for s in "$RELEASE" "all"; do
    if [ -f "$BUILD_BUNDLE_DIR/$s/$file" ]; then
      install -o root -g root -d $(dirname $path/$file)

      if [ "${is_template}" == "yes" ]; then
        envsubst <$BUILD_BUNDLE_DIR/$s/$file >$path/$file
      else
        install -o root -g root -m "$mode" "$BUILD_BUNDLE_DIR/$s/$file" "$path/$file"
      fi

      echo "Installed bundled file: /$file (template: $is_template)"

      return 0
    fi
  done

  echo "Bundled file not found: ${BUILD_BUNDLE_DIR}/{$RELEASE,all}/${file}"
  exit 2
}

install_deps() {
  local luks_mnt="$1"

  shift
  local packages=(${@})

  echo
  highlight "Installing base dependencies..."

  run_chroot_cmd ${luks_mnt} apt-get update -y
  run_chroot_cmd ${luks_mnt} apt-get install uuid-dev openssl -y

  # Install any packages
  if [ "${#packages[@]}" -gt 0 ]; then
    echo
    highlight "Installing ${#packages[@]} packages..."

    if [ "${ID}" == "ubuntu" ]; then
      # bugs.launchpad.net/ubuntu/+source/livecd-rootfs/+bug/1870189
      #
      # Setting GRUB_FORCE_PARTUUID causes grub to boot without
      # an initrd. If this file is present, just remove it.
      rm -f ${luks_mnt}/etc/default/grub.d/40-force-partuuid.cfg
    fi

    # DJR: Fix for OVH globbing order being different for some reason.
    # All of this is to be able to call dpkg -i once with a glob and not need to care about ordering.

    local tmp_dir="/tmp/build-pkgs"
    local tmp_dir_full="${luks_mnt}/${tmp_dir}"
    install -o root -g root -d "${tmp_dir_full}"
    cp "${packages[@]}" "${tmp_dir_full}/"

    # Globbing inside run_chroot_cmd is a pain.
    local installer_path="${tmp_dir}/install.sh"
    echo 'cd /tmp/build-pkgs && dpkg -i *.deb' >${luks_mnt}/${installer_path}
    run_chroot_cmd ${luks_mnt} /bin/sh ${installer_path}

    [ -e "${tmp_dir_full}" ] && rm -rf "${tmp_dir_full}"
  fi
}

install_salt_in_guest() {
  local luks_mnt="$1"

  # Salt
  echo
  highlight "Installing salt..."

  run_chroot_cmd ${luks_mnt} apt-get install curl rsync -y
  run_chroot_cmd ${luks_mnt} curl -o /tmp/install-salt.sh -L https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh
  run_chroot_cmd ${luks_mnt} chmod +x /tmp/install-salt.sh
  run_chroot_cmd ${luks_mnt} /tmp/install-salt.sh -X -d stable latest && rm -f /tmp/install-salt.sh

  install -o root -g root -d ${luks_mnt}/srv/{salt,pillar}

  # TODO: When internal is moved, we will need to setup users for internal guests still.
  for d in "common" "internal" "guest"; do
    install_salt_files "${REPO_COMPONENT_DIR}/${d}/salt" "${luks_mnt}"
  done

  if [ "${TYPE}" == "custom" ]; then
    if [ -n "${CUSTOM_PATH}" ] && [ -d "${CUSTOM_PATH}/salt" ]; then
      for d in $CUSTOM_PATH; do
        install_salt_files "${d}/salt" "${luks_mnt}"
      done
    fi
  fi

  install_salt_local_files_list "${luks_mnt}" users.sls logging.sls blockchain.sls

  {
    echo "build_info:"
    echo "  build_id: $BUILD_ID"
    echo "  build_type: $TYPE"
    if [ -n "${KIND}" ]; then
      echo "  build_kind: $KIND"
    fi
    echo "  build_unix: $BUILD_UNIX"
    echo "  build_date: $BUILD_DATE"
    if [ "${OPT_READONLY}" == "1" ]; then
      echo "  build_opt_ro: True"
    else
      echo "  build_opt_ro: False"
    fi
    if [ "${OPT_USERS}" == "1" ]; then
      echo "  build_opt_users: True"
    else
      echo "  build_opt_users: False"
    fi
    if [ "${OPT_SSH}" == "1" ]; then
      echo "  build_opt_ssh: True"
    else
      echo "  build_opt_ssh: False"
    fi
  } >${luks_mnt}/srv/pillar/local/defaults.sls

  echo "${BUILD_HOSTNAME}.${BUILD_DOMAIN}" >${luks_mnt}/etc/salt/minion_id
  install -o root -g root -m 644 "$COMMON_BASE_DIR/bundle/etc/salt/minion-masterless.guest" "${luks_mnt}/etc/salt/minion"
  run_chroot_cmd ${luks_mnt} systemctl disable salt-minion
}

run_salt() {
  local luks_mnt="$1"

  echo
  highlight "Running salt..."

  local static_pillar="pillar={\"is_chroot\": True, \"no_checkouts\": True}"

  if [ "${VERBOSE}" == "1" ]; then
    run_chroot_cmd ${luks_mnt} salt-call --local --force-color --hard-crash --log-file-level=debug --log-level=debug --state-output=mixed state.highstate "${static_pillar}"
  else
    run_chroot_cmd ${luks_mnt} salt-call --local --force-color --hard-crash --log-file-level=debug --state-output=mixed state.highstate "${static_pillar}"
  fi
}

update_fstabs() {
  local luks_mnt="$1"
  local ro="$2"

  # Update etc/fstab to include the new boot partition
  echo
  highlight "Updating etc/fstab..."

  # make clean fstab.
  echo "# <file system> <mount point>   <type>  <options>       <dump>  <pass>" >${luks_mnt}/etc/fstab

  if [ "${OPT_READONLY}" == "1" ]; then
    echo "UUID=$(ensure blkid -s UUID -o value /dev/mapper/${LUKS_ROOT_DM_NAME})  /        ext4   defaults,noatime,ro        0  0" >>${luks_mnt}/etc/fstab
  else
    echo "UUID=$(ensure blkid -s UUID -o value /dev/mapper/${LUKS_ROOT_DM_NAME})  /        ext4   defaults                   0  0" >>${luks_mnt}/etc/fstab
  fi
  echo "UUID=$(ensure blkid -s UUID -o value /dev/mapper/${LUKS_VAR_DM_NAME})  /var     ext4   defaults                   0  2" >>${luks_mnt}/etc/fstab
  echo "/var/local/root         /root    none   defaults,bind              0  0" >>${luks_mnt}/etc/fstab
  echo "/var/local/home         /home    none   defaults,bind              0  0" >>${luks_mnt}/etc/fstab
  echo "/var/local/srv          /srv     none   defaults,bind              0  0" >>${luks_mnt}/etc/fstab
  echo "tmpfs                   /tmp     tmpfs  defaults,noatime,mode=1777,size=2048M 0  0" >>${luks_mnt}/etc/fstab

  # Add a crypttab entry for the LUKS partition
  echo
  highlight "Updating etc/crypttab..."

  local uuid=$(blkid -s UUID -o value ${LUKS_ROOT_PART})

  if [ "${ro}" == "1" ]; then
    echo "${LUKS_ROOT_DM_NAME} UUID=$uuid none luks,readonly" >>${luks_mnt}/etc/crypttab
  else
    echo "${LUKS_ROOT_DM_NAME} UUID=$uuid none luks" >>${luks_mnt}/etc/crypttab
  fi

  run_chroot_cmd ${luks_mnt} update-initramfs -u -k all
}

create_build_pem() {
  local build_key_pem="build.pem"

  echo
  highlight "Creating: ${build_key_pem}"

  local build_key_priv_file="${LUKS_MNT}/etc/ssl/private/${build_key_pem}"
  local build_key_pub_file="${LUKS_MNT}/etc/ssl/certs/${build_key_pem}"
  openssl ecparam -name secp256k1 -out "${TMP_DIR}/secp256k1.pem"
  openssl ecparam -in "${TMP_DIR}/secp256k1.pem" -genkey -noout -out "${build_key_priv_file}"
  openssl ec -in "${build_key_priv_file}" -pubout >"${build_key_pub_file}"
  chown root:root "$build_key_priv_file"
  chown root:root "$build_key_pub_file"
  chmod 600 "$build_key_priv_file"
  chmod 644 "$build_key_pub_file"
  install -o root -g root -m 644 "${build_key_pub_file}" "./${build_key_pem}"
}

lockdown_and_clean() {
  local luks_mnt="$1"

  echo
  highlight "Lockdown & clean up..."

  # Remove files
  # - Remove lit os init (should exist only within initrd)
  [ -e "${luks_mnt}/opt/lit/os/init" ] && rm -rf "${luks_mnt}/opt/lit/os/init"

  # Fix symlinks (salt also installs a file here)
  for file in "etc/resolv.conf"; do
    if [ -e "${luks_mnt}/$file" ] && [ ! -L "${luks_mnt}/$file" ]; then
      mv "${luks_mnt}/$file" "${luks_mnt}/var/local/$file"
      ln -s "/var/local/$file" "${luks_mnt}/$file"
    fi
  done

  if [ "${OPT_READONLY}" == "1" ]; then
    for d in "srv/salt" "srv/pillar" "home/cargo" "root/.rustup"; do
      [ -e "${luks_mnt}/$d" ] && rm -rf "${luks_mnt:?}/${d:?}"
    done

    run_chroot_cmd ${luks_mnt} apt-get remove salt-minion -y
  fi

  run_chroot_cmd ${luks_mnt} apt-get remove cloud-init -y
  run_chroot_cmd ${luks_mnt} apt autoremove -y
  run_chroot_cmd ${luks_mnt} apt-get clean

  # Hooks
  after_lockdown_and_clean ${luks_mnt}
}

# Harry: This function is used to create a docker image (currently only supports ubuntu2204 from lit-assets) that will be used to build the Lit Node
create_build_env_image() {
    IMAGE_LABEL="$1"
    CODE_PATH="$2"

    highlight "Creating build environment image ($IMAGE_LABEL)"

    docker build "$CODE_PATH/docker/ubuntu2204" -t "$DOCKER_IMAGE"
}

# Harry: Only builds the Lit Node currently - could be made more generic to build anything inside of a docker container
build_in_docker() {
    DOCKER_IMAGE="$1"
    CODE_PATH="$2"

    highlight "Building Lit Node Within Docker ($DOCKER_IMAGE)"

    CPU_COUNT=$(nproc --all)
    docker run --rm --cpus=$CPU_COUNT \
        -e RUSTFLAGS="--remap-path-prefix=$HOME=/remap-home --remap-path-prefix=$PWD=/remap-pwd" \
        -e CARGO_INCREMENTAL="false" \
        -v "$CODE_PATH:/home/root/node-code" \
        "$DOCKER_IMAGE" /bin/bash -c "
            cd /home/root/node-code/rust/lit-node &&
            cargo clean &&
            cargo build --release --locked -j $CPU_COUNT
        "

    BIN_PATH="$CODE_PATH/rust/lit-node/target/release/lit_node"
    if [ ! -e "$BIN_PATH" ] || [ ! -x "$BIN_PATH" ] || ! file "$BIN_PATH" | grep -q "executable"; then
        echo "lit_node binary not valid"
        exit 1
    fi

    NODE_BINARY_HASH=$(sha256sum $BIN_PATH | cut -d ' ' -f 1)

    mkdir -p "${LUKS_MNT}/opt/lit/node/bin"
    cp "$CODE_PATH/rust/lit-node/target/release/lit_node" "${LUKS_MNT}/opt/lit/node/bin"
}

main() {
  local build_env="build.env"

  # Opts
  OPT_READONLY="1"
  OPT_USERS="0"
  OPT_SSH="0"

  if is_dev_or_staging; then
    OPT_USERS="1"
    OPT_SSH="1"

    if is_dev; then
      OPT_READONLY="${READONLY}"
    fi
  fi

  # Template ENV
  export BASE_DOMAIN="$(salt_call_pillar_item 'domain')"
  export BUILD_HOSTNAME="$TYPE-$RELEASE"
  export BUILD_DOMAIN="litos-guest.${BASE_DOMAIN}"

  # Check arguments
  if [ -z "${REF_IMG}" ]; then
    usage
  fi

  [ ! -r "${REF_IMG}" ] && die "${REF_IMG} is not readable!"

  install -o root -g root -d amd
  for tf in ${TEE_AMD_EXTRA_FILES}; do
    if [ ! -f $tf ]; then
      die "Missing required file: $tf"
    fi

    cp $tf amd/
  done

  highlight "Building LitOS template ${BUILD_ID} (type: ${TYPE}, release: ${RELEASE}, read-only: ${OPT_READONLY}, hostname: ${BUILD_HOSTNAME}.${BUILD_DOMAIN})"

  for f in "all" "${TYPE}"; do
    local types_script="${REPO_COMPONENT_DIR}/guest/build/type/${f}.sh"
    if [ -f "${types_script}" ]; then
      echo "Loading: ${types_script}"
      . "${types_script}"
    fi
  done

  if [ "${TYPE}" == "custom" ]; then
    if [ -d "${CUSTOM_PATH}/hooks" ]; then
      for f in ${CUSTOM_PATH}/hooks/build.sh; do
        if [ ! -f $f ]; then
          die "Missing required file: $f"
        fi

        echo
        highlight "sourcing custom build.sh"
        . "$f"
      done
    fi
  fi

  # Checkout dependencies
  checkout_git_deps

  # Generate build password (beware)
  local init_pw_file="./.init.pw"
  echo -n "$(tr -cd '[:alnum:]' </dev/urandom | fold -w64 | head -n 1)" >$init_pw_file
  chown root:root $init_pw_file
  chmod 600 $init_pw_file

  # Create the base qcow2 image
  create_qcow2_image_and_mount ${LUKS_MNT} ${REF_MNT} $init_pw_file

  . ${LUKS_MNT}/etc/os-release

  if [ "${ID}" != "ubuntu" -a "${ID}" != "debian" ]; then
    die "Unsupported OS: $ID"
  fi

  # Prepare base system (some extra stuff from the ref image plus some bundled stuff).
  prepare_base_system ${LUKS_MNT} ${REF_MNT}

  # Install steps
  install_deps ${LUKS_MNT} $TEE_PACKAGE_DIR/snp-release-current/linux/guest/*.deb
  install_salt_in_guest ${LUKS_MNT}

  # Harry: install coreutils so that we have sha256sum
  apt-get install -y coreutils

  DOCKER_IMAGE="litptcl/build-env:$BUILD_ID"
  CODE_PATH="${ASSET_DIR}/lit-assets"

  if [ "${TYPE}" = "node" ]; then
    highlight "Building Lit Node"
    create_build_env_image "$DOCKER_IMAGE" "$CODE_PATH"
    build_in_docker "$DOCKER_IMAGE" "$CODE_PATH"
  fi

  run_salt ${LUKS_MNT}

  # Create build pem
  create_build_pem

  echo ""
  highlight "Writing ${build_env}"

  local root_uuid=$(ensure blkid -s UUID -o value /dev/mapper/${LUKS_ROOT_DM_NAME})
  local var_uuid=$(ensure blkid -s UUID -o value /dev/mapper/${LUKS_VAR_DM_NAME})

  {
    echo "# Build Env Meta"
    echo ""
    echo "BUILD_ID=\"$BUILD_ID\""
    if [ "${TYPE}" == "node" ]; then
        # Only set BUILD_ENV_IMG if we are not in dev mode, this means that the Lit OS CLI will not try to push to docker hub.
        if [ "${RELEASE}" != "dev" ]; then
            echo "BUILD_ENV_IMG=\"${DOCKER_IMAGE%:*}\""
        fi
        echo "BUILD_BIN_HASH=\"$NODE_BINARY_HASH\""
    fi
    echo "BUILD_UNIX=\"$BUILD_UNIX\""
    echo "BUILD_DATE=\"$BUILD_DATE\""
    echo "BUILD_UNAME=\"$(uname -a)\""
    echo "BUILD_TYPE=\"$TYPE\""
    if [ -n "${KIND}" ]; then
      echo "BUILD_KIND=\"$KIND\""
    fi
    if [ -n "${CUSTOM_SOURCE}" ]; then
      echo "BUILD_CUSTOM_SOURCE=\"$CUSTOM_SOURCE\""
    fi
    echo "BUILD_RELEASE=\"$RELEASE\""
    echo "BUILD_CPU_TYPE=\"$BUILD_CPU_TYPE\""
    echo "BUILD_OS_TYPE=\"debian\""
    echo "BUILD_OS_VERSION=\"11\"" # Hardcoded, change.
    echo "BUILD_REF_IMG=\"$(basename $REF_IMG)\""
    echo "BUILD_IMG_NAME=\"$GUEST_IMG_NAME\""
    echo "BUILD_IMG_SIZE=\"$GUEST_IMG_SIZE\""
    echo "BUILD_ROOT_SIZE=\"$GUEST_ROOT_SIZE\""
    echo "BUILD_HOSTNAME=\"${BUILD_HOSTNAME}\""
    echo "BUILD_DOMAIN=\"${BUILD_DOMAIN}\""
    echo "BUILD_OPT_RO=\"${OPT_READONLY}\""
    echo "BUILD_OPT_USERS=\"${OPT_USERS}\""
    echo "BUILD_OPT_SSH=\"${OPT_SSH}\""
    echo "BUILD_LUKS_ROOT_UUID=\"$(ensure blkid -s UUID -o value ${LUKS_ROOT_PART})\""
    echo "BUILD_LUKS_VAR_UUID=\"$(ensure blkid -s UUID -o value ${LUKS_VAR_PART})\""
    echo "BUILD_ROOT_UUID=\"$root_uuid\""
    echo "BUILD_VAR_UUID=\"$var_uuid\""
  } >${build_env}

  # Copy build.env to guest with prefixes.
  cat ${build_env} | sed -e 's/^BUILD_/LIT_OS_BUILD_/g' >${LUKS_MNT}/etc/lit-os-build

  echo ""
  highlight "Copy files to guest..."
  install -o root -g root -m 600 ${META_FILE} ${LUKS_MNT}/etc/lit/build-meta.toml
  run_chroot_cmd ${LUKS_MNT} /usr/bin/setfacl -m g:lit-config:r /etc/lit/build-meta.toml
  install -o root -g root -m 600 -D /lib/firmware/amd/amd_sev_fam19h_model0xh.sbin ${LUKS_MNT}/lib/firmware/amd/amd_sev_fam19h_model0xh.sbin #MILAN
  install -o root -g root -m 600 -D /lib/firmware/amd/amd_sev_fam19h_model1xh.sbin ${LUKS_MNT}/lib/firmware/amd/amd_sev_fam19h_model1xh.sbin #GENOA

  # Write fstab after the lit-os-release file is finalised.
  update_fstabs ${LUKS_MNT} ${OPT_READONLY}
  lockdown_and_clean ${LUKS_MNT}

  echo ""
  highlight "Copy files from guest..."

  install -o root -g root -m 644 ${LUKS_MNT}/var/log/salt/minion build-salt.log
  install -o root -g root -m 644 ${LUKS_MNT}/boot/vmlinuz-*-snp-guest-* guest-vmlinuz
  install -o root -g root -m 644 ${LUKS_MNT}/boot/initrd.img-*-snp-guest-* guest-initrd.img
  install -o root -g root -m 600 ${LUKS_MNT}/etc/lit/config.toml build-lit-config.toml

  echo ""
  highlight "Measuring disk hashes..."

  echo_run umount -R "${LUKS_MNT}"
  close_luks
  open_luks "$init_pw_file"

  echo "lit os util hash /dev/disk/by-uuid/${root_uuid}"
  local root_hash=$(ensure lit os util hash /dev/disk/by-uuid/${root_uuid})
  echo "BUILD_ROOT_HASH=\"${root_hash}\"" >>${build_env}

  echo "lit os util hash /dev/disk/by-uuid/${var_uuid}"
  local var_hash=$(ensure lit os util hash /dev/disk/by-uuid/${var_uuid})
  echo "BUILD_VAR_HASH=\"${var_hash}\"" >>${build_env}

  echo ""
  highlight "Writing guest assets..."

  {
    echo -n "console=ttyS0 earlyprintk=serial root=/dev/disk/by-uuid/${root_uuid} usbcore.nousb "
    if [ "${OPT_READONLY}" == "1" ]; then
      echo -n "ro "
    fi
    echo -n "litos.build_id=${BUILD_ID} litos.type=${TYPE} "
    if [ -n "${KIND}" ]; then
      echo -n "litos.kind=${KIND} "
    fi
    echo -n "litos.env=${RELEASE} litos.roothash=${root_hash} "
    if [ -n "${var_hash}" ]; then
      echo -n "litos.varhash=${var_hash} "
    fi
    echo -n "litos.opt_ro=${OPT_READONLY} litos.opt_users=${OPT_USERS} litos.opt_ssh=${OPT_SSH}"
  } >guest-vmlinuz.cmdline

  echo
  highlight "Successfully created ${GUEST_IMG_NAME}!"
  exit 0
}

# If we are not root, re-run with root privileges.
if [ "${UID}" -ne 0 ]; then
  highlight "root priviliges are required. Re-running under sudo..."
  exec sudo ${0} $@
fi

if [ ! -d $TEE_PACKAGE_DIR ]; then
  stderr "Missing AMD TEE package dir: $TEE_PACKAGE_DIR"
  exit 1
fi

ORIG_ARGS=("$@")

while [ -n "$1" ]; do
  case "$1" in
  -id)
    BUILD_ID="$2"
    shift
    ;;
  -path)
    BUILD_PATH="$2"
    shift
    ;;
  -type)
    TYPE="$2"
    shift
    ;;
  -kind)
    KIND="$2"
    shift
    ;;
  -release)
    RELEASE="$2"
    shift
    ;;
  -ref-image)
    REF_IMG="$2"
    shift
    ;;
  -image)
    GUEST_IMG_NAME="$2"
    shift
    ;;
  -image-size)
    GUEST_IMG_SIZE="$2"
    shift
    ;;
  -root-size)
    GUEST_ROOT_SIZE="$2"
    shift
    ;;
  -custom-path)
    CUSTOM_PATH="$2"
    shift
    ;;
  -ro)
    READONLY="1"
    ;;
  -no-cleanup)
    NO_CLEANUP="1"
    ;;
  -cleanup)
    DO_CLEANUP="1"
    ;;
  -verbose)
    VERBOSE="1"
    ;;
  *)
    stderr "ERROR: Invalid option: $1"
    stderr
    usage
    ;;
  esac

  shift
done

if [ -z "$BUILD_ID" ]; then
  BUILD_ID=$(uuid)
fi

if [ -z "${BUILD_PATH}" ]; then
  stderr "ERROR: -path is required."
  stderr
  usage
fi

if [ "$TYPE" != "node" ] && [ "$TYPE" != "prov" ] && [ "$TYPE" != "build" ] && [ "$TYPE" != "custom" ]; then
  stderr "ERROR: Invalid -type $TYPE"
  stderr
  usage
fi

if [ "$RELEASE" != "dev" ] && [ "$RELEASE" != "staging" ] && [ "$RELEASE" != "prod" ]; then
  stderr "ERROR: Invalid -release $RELEASE"
  stderr
  usage
fi

if [ "${TYPE}" != "custom" ] && [ -n "${CUSTOM_PATH}" ]; then
  stderr "ERROR: -custom-path is only valid for custom build type"
  stderr
  usage
fi

if [ "${TYPE}" != "custom" ] && [ -n "${KIND}" ]; then
  stderr "ERROR: -kind is only valid for custom build type"
  stderr
  usage
fi

if [ "${TYPE}" == "custom" ] && [ -z "${KIND}" ]; then
  stderr "ERROR: -kind is required for custom build types"
  stderr
  usage
fi

if [ -n "${CUSTOM_PATH}" ] && [ ! -d "${CUSTOM_PATH}" ]; then
  stderr "ERROR: -custom-path ${CUSTOM_PATH} invalid, directory does not exist"
  stderr
  usage
fi

# TODO: Improve (may not need to be built ON AMD, just FOR AMD).
if is_amd; then
  BUILD_CPU_TYPE="EPYC-v4"
else
  stderr "ERROR: unrecognised build platform (not AMD)."
  stderr
  usage
fi

# Change to build dir
install -o root -g root -d $BUILD_PATH
cd $BUILD_PATH

if [ "${DO_CLEANUP}" == "1" ]; then
  # Only perform clean up.
  LUKS_MNT=$TMP_DIR/mnt/luks
  REF_MNT=$TMP_DIR/mnt/ref
  NO_CLEANUP="0"

  cleanup
  exit 0
fi

# Canonicalize
if [ -d "${REPO_SCRIPT_DIR}" ]; then
  TMP_DIR=$(readlink -f ${TMP_DIR})
  ASSET_DIR=$(readlink -f ${ASSET_DIR})
  REPO_BASE_DIR=$(readlink -f ${REPO_BASE_DIR})
  REPO_COMPONENT_DIR=$(readlink -f ${REPO_COMPONENT_DIR})
  REPO_SCRIPT_DIR=$(readlink -f ${REPO_SCRIPT_DIR})
  REPO_CUSTOM_TYPE_DIR=$(readlink -f ${REPO_CUSTOM_TYPE_DIR})
  META_FILE=$(readlink -f ${META_FILE})

  if [ "${TYPE}" == "custom" ]; then
    if [ -n "${CUSTOM_PATH}" ]; then
      CUSTOM_SOURCE="file://${CUSTOM_PATH}"
    elif [ -d "${REPO_CUSTOM_TYPE_DIR}/${KIND}" ]; then
      CUSTOM_PATH="${REPO_CUSTOM_TYPE_DIR}/${KIND}"
      CUSTOM_SOURCE="repo://lit-os:${REPO_CUSTOM_TYPE_DIR}/${KIND}"
    else
      stderr "ERROR: No custom type path found for this kind: ${KIND}"
      stderr
      usage
    fi
  fi
fi

if [ ! -d "${REPO_SCRIPT_DIR}" ] || [ "${SCRIPT_DIR}" != "${REPO_SCRIPT_DIR}" ]; then
  highlight "Bootstrapping..."
  echo "Build path: ${BUILD_PATH}"

  # Setup tmp
  [ -d "${TMP_DIR}" ] && rm -rf $TMP_DIR

  # Setup assets
  install -o root -g root -d ${ASSET_DIR}
  chown git:git ${ASSET_DIR}

  # Canonicalize
  TMP_DIR=$(readlink -f ${TMP_DIR})
  ASSET_DIR=$(readlink -f ${ASSET_DIR})
  REPO_BASE_DIR="${ASSET_DIR}/${REPO_NAME}"
  META_FILE=$(readlink -f ${META_FILE})

  # Checkout lit-os
  git_clone_and_log_meta "${REPO_BASE_DIR}" "${META_FILE}" "${REPO_NAME}" "${RELEASE}"

  # Re-launch
  echo
  highlight "Launching..."

  exec time ${REPO_SCRIPT_DIR}/build.sh "${ORIG_ARGS[@]}"
fi

# We are main
trap 'cleanup' ERR EXIT SIGHUP SIGINT

modprobe nbd

LUKS_MNT=$TMP_DIR/mnt/luks
REF_MNT=$TMP_DIR/mnt/ref

# Disconnect the nbd devices (prior states).
cleanup_nbds
echo

main "$@"
