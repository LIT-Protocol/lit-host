/etc/default/isc-dhcp-server:
  file:
    - managed
    - source: salt://dhcp-server/etc/default/isc-dhcp-server.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644

/etc/dhcp/dhcpd.conf:
  file:
    - managed
    - source: salt://dhcp-server/etc/dhcp/dhcpd.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644

isc-dhcp-server:
  pkg.installed:
    - name: isc-dhcp-server
{% if pillar.get('is_init_install', False) == True %}
  # service.enabled doesn't appear to work.
  cmd.run:
    - name: systemctl enable isc-dhcp-server.service
{% else %}
  service.running:
    - name: isc-dhcp-server
    - enable: true
    - watch:
      - file: /etc/default/isc-dhcp-server
      - file: /etc/dhcp/dhcpd.conf
{% endif %}
    - require:
      - file: /etc/default/isc-dhcp-server
      - file: /etc/dhcp/dhcpd.conf
      - pkg: isc-dhcp-server
