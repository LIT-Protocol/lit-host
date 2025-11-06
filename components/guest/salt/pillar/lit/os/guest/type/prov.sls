litos_guest_type: prov

litos_guest_allowed_cfg_keys:
  - guest.instance.id
  - zerossl.api_key
  - api.prov.domain
  - api.prov.tls_csr_country
  - api.prov.tls_csr_org_name
  - api.prov.tls_csr_org_unit
  - api.prov.tls_csr_self_signed_cn
  - api.prov.tls_csr_self_signed_days
  - api.prov.wallet.default.private_key
  - blockchain.wallet.default.private_key
  - api.prov.contract.default.default.gas
  - blockchain.contract.default.default.gas
  - api.prov.contract.default.default.gas_price
  - blockchain.contract.default.default.gas_price

litos_init_features: type-prov,common

firewall:
  tcp_port_forwards:
    80: 8080
    443: 8443