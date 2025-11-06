include:
  - lit.node.defaults

litos_guest_type: node

litos_guest_allowed_cfg_keys:
  - guest.instance.id
  - zerossl.api_key
  - node.domain
  - node.staker_address
  - node.admin_address
  - node.coms_keys_sender_privkey
  - node.coms_keys_receiver_privkey
  - node.tls_csr_country
  - node.tls_csr_org_name
  - node.tls_csr_org_unit
  - node.tls_csr_self_signed_cn
  - node.tls_csr_self_signed_days
  - node.enter_restore_state
  - node.bls_key_blinder
  - node.ecdsa_key_blinder
  - node.restore_log_interval
  - blockchain.wallet.default.private_key
  - blockchain.contract.default.default.gas
  - blockchain.contract.default.default.gas_price

litos_init_features: type-node,common

firewall:
  tcp_port_forwards:
    80: 8080
    443: 8443
