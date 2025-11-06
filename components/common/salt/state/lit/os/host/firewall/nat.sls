net.ipv4.ip_forward:
  sysctl.present:
    - value: 1

{% for line in ['net.ipv4.ip_forward'] %}
/etc/sysctl.conf_rm_{{ line }}:
  file.comment:
    - name: /etc/sysctl.conf
    - regex: ^{{ line }}
    - ignore_missing: True
{% endfor %}

iptables-vm-nat-flush-nat-POSTROUTING:
  iptables.flush:
    - table: nat
    - chain: POSTROUTING
    - require:
        - pkg: iptables

iptables-vm-nat:
  iptables.append:
    - table: nat
    - chain: POSTROUTING
    - jump: MASQUERADE
    - source: 172.30.0.1/16
    - out-interface: {{ pillar.net_out_iface }}
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-rules-flush-INPUT
        - iptables: iptables-rules-flush-FORWARD
        - iptables: iptables-rules-flush-OUTPUT
        - iptables: iptables-vm-nat-flush-nat-POSTROUTING

iptables-vm-out-fwd:
  iptables.append:
    - chain: FORWARD
    - jump: ACCEPT
    - source: 172.30.0.1/16
    - in-interface: {{ pillar.net_vm_iface }}
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-vm-nat

# Probably not needed, but why not.
iptables-vm-in-fwd:
  iptables.append:
    - chain: FORWARD
    - jump: ACCEPT
    - destination: 172.30.0.1/16
    - out-interface: {{ pillar.net_vm_iface }}
    - save: True
    - require:
        - pkg: iptables
        - iptables: iptables-vm-out-fwd