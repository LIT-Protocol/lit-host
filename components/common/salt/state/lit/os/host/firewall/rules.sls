iptables-rules-flush-INPUT:
  iptables.flush:
    - table: filter
    - chain: INPUT
    - require:
        - pkg: iptables

iptables-rules-flush-FORWARD:
  iptables.flush:
    - table: filter
    - chain: FORWARD
    - require:
        - pkg: iptables

iptables-rules-flush-OUTPUT:
  iptables.flush:
    - table: filter
    - chain: OUTPUT
    - require:
        - pkg: iptables

iptables-rules-default-INPUT-to-DROP:
  iptables.set_policy:
    - chain: INPUT
    - policy: DROP
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-flush-INPUT
        - iptables: iptables-rules-flush-FORWARD
        - iptables: iptables-rules-flush-OUTPUT

iptables-rules-default-FORWARD-to-DROP:
  iptables.set_policy:
    - chain: FORWARD
    - policy: DROP
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-flush-INPUT
        - iptables: iptables-rules-flush-FORWARD
        - iptables: iptables-rules-flush-OUTPUT

iptables-rules-default-OUTPUT-to-ACCEPT:
  iptables.set_policy:
    - chain: OUTPUT
    - policy: ACCEPT
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-flush-INPUT
        - iptables: iptables-rules-flush-FORWARD
        - iptables: iptables-rules-flush-OUTPUT

iptables-rules-ACCEPT-INPUT-ESTABLISHED:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - match:
        - conntrack
    - comment: "Allow ESTABLISHED,RELATED"
    - ctstate: ESTABLISHED,RELATED
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP

iptables-rules-DROP-INPUT-INVALID:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: DROP
    - match:
        - conntrack
    - comment: "Drop INVALID"
    - ctstate: INVALID
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP

# Managing YELLOWSTONE Chronicle Replica Chain
iptables-rules-CREATE-CHAIN-YELLOWSTONE:
  # Workaround: Use cmd.run as iptables.new_chain fails in highstate
  cmd.run:
    - name: 'iptables -N YELLOWSTONE_ACCESS || true' # Ensures chain exists, ignores error if already present
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP

# Insert rules into INPUT chain
iptables-rules-INSERT-JUMP-INPUT-to-YELLOWSTONE-8548:
  iptables.insert:
    - position: 1
    - table: filter
    - chain: INPUT
    - jump: YELLOWSTONE_ACCESS
    - protocol: tcp
    - dport: 8548
    - comment: "Insert Jump INPUT traffic for Yellowstone WS port 8548 to custom chain"
    - save: True
    - require:
        - cmd: iptables-rules-CREATE-CHAIN-YELLOWSTONE # Require chain existence

iptables-rules-INSERT-JUMP-INPUT-to-YELLOWSTONE-8547:
  iptables.insert:
    - position: 1 # Insert at the very top (will push 8548 rule down to 2)
    - table: filter
    - chain: INPUT
    - jump: YELLOWSTONE_ACCESS
    - protocol: tcp
    - dport: 8547
    - comment: "Insert Jump INPUT traffic for Yellowstone RPC port 8547 to custom chain"
    - save: True
    - require:
        - cmd: iptables-rules-CREATE-CHAIN-YELLOWSTONE # Require chain existence

# Insert rules into DOCKER-USER chain
iptables-rules-INSERT-JUMP-DOCKER-USER-to-YELLOWSTONE-8548:
  iptables.insert:
    - position: 1 # Insert at the very top
    - table: filter
    - chain: DOCKER-USER
    - jump: YELLOWSTONE_ACCESS
    - protocol: tcp
    - dport: 8548
    - comment: "Insert Jump DOCKER-USER traffic for Yellowstone WS port 8548 to custom chain"
    - save: True
    - require:
        - cmd: iptables-rules-CREATE-CHAIN-YELLOWSTONE # Require chain existence

iptables-rules-INSERT-JUMP-DOCKER-USER-to-YELLOWSTONE-8547:
  iptables.insert:
    - position: 1 # Insert at the very top (will push 8548 rule down to 2)
    - table: filter
    - chain: DOCKER-USER
    - jump: YELLOWSTONE_ACCESS
    - protocol: tcp
    - dport: 8547
    - comment: "Insert Jump DOCKER-USER traffic for Yellowstone RPC port 8547 to custom chain"
    - save: True
    - require:
        - cmd: iptables-rules-CREATE-CHAIN-YELLOWSTONE # Require chain existence

iptables-rules-ACCEPT-INPUT-via-lo:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - in-interface: lo
    - comment: "Accept INPUT lo"
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP

iptables-rules-ACCEPT-INPUT-ping:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - protocol: icmp
    - icmp-type: echo-request
    - comment: "Accept INPUT ping"
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP

{% if 'firewall' in pillar -%}
{% if 'allowed_ports' in pillar.firewall -%}
{% for port, cfg in pillar.firewall.allowed_ports.items() %}
{% if 'source' in cfg %}
{% for src in cfg.source %}
iptables-rules-ACCEPT-INPUT-{{ cfg.protocol }}-{{ port }}-src-{{ src }}:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - protocol: {{ cfg.protocol }}
    - state: NEW
    - source: {{ src }}
    - dport: {{ port }}
    - comment: "Accept INPUT {{ cfg.protocol }} {{ port }} from {{ src }}"
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP
{% endfor %}
{% else %}
iptables-rules-ACCEPT-INPUT-{{ cfg.protocol }}-{{ port }}-src_0.0.0.0/0:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - protocol: {{ cfg.protocol }}
    - state: NEW
    - source: 0.0.0.0/0
    - dport: {{ port }}
    - comment: "Accept INPUT {{ cfg.protocol }} {{ port }} from 0.0.0.0/0"
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP
{% endif %}
{% endfor %}
{% endif %}
{% endif %}

iptables-rules-ACCEPT-INPUT-via-{{ pillar.net_vm_iface }}:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - source: 172.30.0.1/16
    - in-interface: {{ pillar.net_vm_iface }}
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP

# IPFS

iptables-rules-ACCEPT-INPUT-tcp-4001-ipfs:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - protocol: tcp
    - state: NEW
    - dport: 4001
    - comment: "Accept INPUT tcp 4001 (ipfs)"
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP

iptables-rules-ACCEPT-INPUT-udp-4001-ipfs:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - protocol: udp
    - state: NEW
    - dport: 4001
    - comment: "Accept INPUT udp 4001 (ipfs)"
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP

iptables-rules-ACCEPT-INPUT-tcp-6881-6999-bittorrent:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - protocol: tcp
    - state: NEW
    - dport: 6881:6999
    - source: 0.0.0.0/0
    - comment: "Accept INPUT tcp 6881:6999 (BitTorrent)"
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP

iptables-rules-ACCEPT-INPUT-udp-6881-6999-bittorrent:
  iptables.append:
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - protocol: udp
    - state: NEW
    - dport: 6881:6999
    - source: 0.0.0.0/0
    - comment: "Accept INPUT udp 6881:6999 (BitTorrent)"
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-default-INPUT-to-DROP
