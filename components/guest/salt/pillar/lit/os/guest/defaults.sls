litos_guest: True

litos_guest_add_packages:
  - uuid-dev
  - cryptsetup
  - git
  - curl
  - wget

litos_guest_rem_packages:
  - unattended-upgrades
  - cloud-init
  - resolvconf

litos_guest_rem_services:
  - apt-daily.timer
  - apt-daily-upgrade.timer
  - man-db.timer
  - unattended-upgrades.service

litos_cfg_includes:
  - lit/os/guest/component/config/etc/lit/config.toml