#!/bin/sh

PREREQ=""

prereqs() {
	echo "$PREREQ"
}

case $1 in
prereqs)
	prereqs
	exit 0
	;;
esac

. /usr/share/initramfs-tools/hook-functions
# Begin real processing below this line

# Add some system files
copy_file CFG /etc/group
copy_file CFG /etc/nsswitch.conf

if [ -L "/etc/resolv.conf" ]; then
	cp -f /var/local/etc/resolv.conf "${DESTDIR}/etc/resolv.conf"
else
	copy_file CFG /etc/resolv.conf
fi

cp -f /var/local/etc/hosts "${DESTDIR}/etc/hosts"

# Libs needed for DNS
mkdir -p "${DESTDIR}/usr/lib/x86_64-linux-gnu"
cp -rf /usr/lib/x86_64-linux-gnu/libnss_* "${DESTDIR}/usr/lib/x86_64-linux-gnu/"

# Add Lit OS configs
copy_file CFG /etc/lit/config.toml
copy_file CFG /etc/lit/rpc-config.yaml
copy_file CFG /etc/lit-os-build
copy_file PEM /etc/ssl/certs/build.pem

# Add AMD SEV-SNP firmware packages
add_firmware amd_sev_fam19h_model0xh.sbin #MILAN
add_firmware amd_sev_fam19h_model1xh.sbin #GENOA

# Add AMD SEV-SNP certs cache
copy_file PEM /var/cache/sev-snp/certs/Milan/cert_chain.pem

# Copy CA certs
mkdir -p "${DESTDIR}/usr/share/ca-certificates/mozilla"
mkdir -p "${DESTDIR}/usr/lib/ssl/certs"

cp -rf /usr/share/ca-certificates/mozilla/* "${DESTDIR}/usr/share/ca-certificates/mozilla/"
cp -rf /usr/lib/ssl/certs/* "${DESTDIR}/usr/lib/ssl/certs/"

# Add openssl
copy_exec /usr/bin/openssl

# Add the userspace programs
copy_exec /opt/lit/os/init/lit-os-init
copy_exec /opt/lit/os/init/lit-os-init-prepare.sh
copy_exec /opt/lit/os/init/lit-os-init-cleanup.sh

# Needed to resize volumes
copy_exec /usr/sbin/blockdev
copy_exec /usr/sbin/e2fsck
copy_exec /usr/sbin/resize2fs

# Needed to set ACL for config
copy_exec /usr/bin/setfacl

# Needed for lit-os-init-prepare.sh
copy_exec /bin/bash
copy_exec /usr/bin/touch
copy_exec /usr/bin/mount /usr/bin/mount-full # the minimal mount command in initrd doesn't know `--bind`
copy_exec /usr/bin/umount /usr/bin/umount-full # the minimal mount command in initrd doesn't know `--bind`

# Needed for lit-os-init-cleanup.sh (and the PREPARE step)
copy_exec /usr/bin/ip
copy_exec /usr/bin/awk
copy_exec /usr/bin/grep

# For lit-os-initrd
copy_exec /usr/sbin/cryptsetup # RAD: TEST (it seems cryptsetup-sys uses the binary)