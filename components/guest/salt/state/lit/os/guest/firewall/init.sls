include:
  - pkgs.iptables
  - pkgs.iptables-persistent
  - .rules

/etc/sysctl.d/99-guest-firewall.conf:
  file:
    - managed
    - user: root
    - group: root
    - mode: 644
    - makedirs: True
    - dir_mode: 755
    - contents:
      - net.ipv4.ip_forward = 1
      - net.ipv6.ip_forward = 1
      - net.ipv4.conf.enp0s2.route_localnet = 1
      - net.ipv4.conf.enp0s3.route_localnet = 1
