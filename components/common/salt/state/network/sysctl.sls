net.core.somaxconn:
  sysctl.present:
    - value: 1024

net.core.netdev_max_backlog:
  sysctl.present:
    - value: 5000

net.core.rmem_max:
  sysctl.present:
    - value: 16777216

net.core.wmem_max:
  sysctl.present:
    - value: 16777216

net.ipv4.tcp_wmem:
  sysctl.present:
    - value: 4096 12582912 16777216

net.ipv4.tcp_rmem:
  sysctl.present:
    - value: 4096 12582912 16777216

net.ipv4.tcp_max_syn_backlog:
  sysctl.present:
    - value: 8096

net.ipv4.tcp_slow_start_after_idle:
  sysctl.present:
    - value: 0

net.ipv4.tcp_tw_reuse:
  sysctl.present:
    - value: 1

net.ipv4.ip_local_port_range:
  sysctl.present:
    - value: 10240 65535

{% for line in ['net.core.somaxconn', 'net.core.netdev_max_backlog', 'net.core.rmem_max', 'net.core.wmem_max',
                'net.ipv4.tcp_wmem', 'net.ipv4.tcp_rmem', 'net.ipv4.tcp_max_syn_backlog', 'net.ipv4.tcp_slow_start_after_idle',
                'net.ipv4.tcp_tw_reuse', 'net.ipv4.ip_local_port_range'] %}
/etc/sysctl.conf_rm_{{ line }}:
  file.comment:
    - name: /etc/sysctl.conf
    - regex: ^{{ line }}
    - ignore_missing: True
{% endfor %}