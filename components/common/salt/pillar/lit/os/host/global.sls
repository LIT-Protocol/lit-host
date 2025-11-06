net_out_iface: br0
net_vm_iface: vmbr0

net_br0_enable: True
net_vmbr0_enable: True

net_dhcpd:
  interfaces_v4:
    - vmbr0
  subnets:
    - subnet: 172.30.0.0
      netmask: 255.255.0.0
      range: 172.30.0.100 172.30.3.254
      gw: 172.30.0.1

ipfs_update_version: v1.9.0
ipfs_profile: badgerds
ipfs_datastore_storage_max: 50G
ipfs_datastore_storage_gc_watermark: 90
ipfs_addresses_api: /ip4/172.30.0.1/tcp/5001
ipfs_addresses_gateway: /ip4/172.30.0.1/tcp/8080

