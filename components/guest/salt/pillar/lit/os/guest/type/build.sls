litos_guest_type: build
litos_cli_features: os-guest-build

litos_guest_allowed_cfg_keys:
  - guest.instance.id
  - blockchain.wallet.default.private_key
  - blockchain.contract.default.default.gas
  - blockchain.contract.default.default.gas_price

litos_init_features: type-build,common

firewall:
  tcp_ports:
    - 80
    - 443