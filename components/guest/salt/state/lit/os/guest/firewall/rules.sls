/etc/iptables/rules.v4:
  file:
    - managed
    - source: salt://lit/os/guest/firewall/etc/iptables/rules.v4
    - user: root
    - group: root
    - mode: 600
    - makedirs: True
    - dir_mode: 755
    - template: jinja