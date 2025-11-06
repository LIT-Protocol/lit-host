include:
  - hosts
  - time
{% if pillar.env in ['dev', 'staging'] %}
  - groups
  - users
  - pkgs.sudo
  - pkgs.fail2ban
  - pkgs.vim
{% endif %}
  - pkgs.ifupdown # deprecated and no longer standard in deb12
  - pkgs.isc-dhcp-client  # not shipped with deb12
  - pkgs.acl
  - git # RAD: DEPRECATED, not all guests need git, the service that does should include it
  - rust # RAD: DEPRECATED, not all guests need rust, the service that does should include it
  - osquery
  - lit
  - lit.core.blockchain
  - lit.os
  - lit.os.guest.firewall
  - lit.os.host.hosts
  - lit.core.cron
  - .component.init
  - .component.service.attestation
  - .component.service.logging
  - .component.service.metrics
  - .base

{% for p in pillar.litos_guest_add_packages %}
add_pkg_{{ p }}:
  pkg.installed:
    - name: {{ p }}
{% endfor %}


{% for p in pillar.litos_guest_rem_packages %}
rem_pkg_{{ p }}:
  pkg.removed:
    - name: {{ p }}
{% endfor %}


{% for s in pillar.litos_guest_rem_services %}
rem_svc_{{ s }}:
  service.disabled:
    - name: {{ s }}
{% endfor %}

/etc/dhcp/dhclient-enter-hooks.d:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True

/etc/dhcp/dhclient-enter-hooks.d/leave_my_resolv_conf_alone:
  file:
    - managed
    - contents:
      - make_resolv_conf() { :; }
    - user: root
    - group: root
    - mode: 755
    - require:
      - file: /etc/dhcp/dhclient-enter-hooks.d
