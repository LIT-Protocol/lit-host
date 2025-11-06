cloud_provider: ovh
cloud_provider_class: default

net_iface_bonds:
  # Private Bond
  bond0:
    proto: manual
    slaves:
      - eno1
      - eno2
    miimon: 100
    mode: 802.3ad
    bridge: br0

net_br0_use: bond0
net_out_iface: br0

# For now, this is easier (because the 'host' needs a reboot anyway)
net_bonds_require_reboot: True
net_br0_require_reboot: True

grub_cmdline_linux_default: nomodeset console=tty0 console=ttyS0,115200n8
