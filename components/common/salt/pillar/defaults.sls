# Do not forget to edit internal/default.sls too.

env: dev
location: null00
domain: litnet.io
search: litnet.io
nameservers:
  - 1.1.1.1
  - 8.8.8.8

# internal will be the correct ones.
cron_email: admin@litprotocol.com
root_email: admin@litprotocol.com

timezone: America/New_York

rust_default_toolchain: 1.91

grub_cmdline_linux_default: quiet
grub_gfxpayload_linux: text


# These are applied to all rust builds except lit cli and lit guest initrd (due to making the disk hashing too slow).
rust_build_args:
  dev: "--profile develop"
  staging: "--release"
  prod: "--release"

rust_build_dir:
  dev: "target/develop"
  staging: "target/release"
  prod: "target/release"

tmp_dir: "/var/tmp"

