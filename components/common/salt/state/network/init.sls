include:
  - .sysctl
{% if 'net_iface_bonds' in pillar %}
  - pkgs.ifenslave
{% endif %}
{% if salt.pillar.get('net_br0_enable', False) == True or salt.pillar.get('net_vmbr0_enable', False) == True %}
  - pkgs.bridge-utils
{% endif %}

{% if 'net_iface_custom_files' in pillar %}
{% for file in pillar.net_iface_custom_files %}
/etc/network/interfaces.d/{{ file }}:
  file:
    - exists
{% endfor %}
{% endif %}

/etc/network/interfaces.d:
  file.directory:
    - clean: True
{% if 'net_iface_custom_files' in pillar %}
    - require:
{% for file in pillar.net_iface_custom_files %}
      - file: /etc/network/interfaces.d/{{ file }}
{% endfor %}
{% endif %}

{% if 'net_iface_bonds' in pillar %}
modprobe-bonding:
  cmd.run:
    - name: modprobe bonding && echo "bonding" > /etc/modules-load.d/bonding.conf
    - creates: /etc/modules-load.d/bonding.conf
    - require:
      - pkg: ifenslave
{% endif %}

/etc/network/interfaces:
  file:
    - managed
    - user: root
    - group: root
    - source: salt://network/etc/network/interfaces
    - template: jinja
    - require:
      - file: /etc/network/interfaces.d
{% if 'net_iface_bonds' in pillar %}
      - pkg: ifenslave
      - cmd: modprobe-bonding
{% endif %}
{% if salt.pillar.get('net_br0_enable', False) == True or salt.pillar.get('net_vmbr0_enable', False) == True %}
      - pkg: bridge-utils
{% endif %}

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