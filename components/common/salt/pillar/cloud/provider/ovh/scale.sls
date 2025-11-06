cloud_provider_class: scale

net_iface_bonds:
  # Public Bond
  bond0:
    proto: dhcp
    slaves:
      - ens3f0np0
      - ens3f1np1
    miimon: 100
    mode: 802.3ad
  # Private Bond
  bond1:
    proto: manual
    slaves:
      - ens2f0np0
      - ens2f1np1
    miimon: 100
    mode: 802.3ad
    bridge: br0

net_br0_use: bond1
net_out_iface: bond0