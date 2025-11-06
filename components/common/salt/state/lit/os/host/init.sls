include:
{% if grains['os'] == 'Debian' and grains['osrelease'] == '11' %}
  - .debian12
{% else %}
  - common.limits
  - common.sysctl
  - network
  - grub
  - ipfs
  - .hosts
  - .pkgs
  - .logrotate
  - .firewall
  - dhcp-server
  - docker
  - chronicle
  - monitoring
  - lit
  - lit.core.blockchain
  - lit.os
  - lit.os.cli
  - lit.core.cron
{% endif %}
