{% set files = {
  'etc/modules': { 'mode': 600, 'template': 'jinja' },
  'etc/network/interfaces': { 'mode': 600, 'template': 'jinja' },
  'etc/iproute2/rt_tables': { 'mode': 644, 'template': 'jinja' },
  'etc/dhcp/dhclient.conf': { 'mode': 600, 'template': 'jinja' },
  'etc/security/limits.conf': { 'mode': 600, 'template': 'jinja' },
  'etc/systemd/system/journald.service': { 'mode': 600, 'template': 'jinja' },
  'etc/systemd/system/set_hostname.service': { 'mode': 600, 'template': 'jinja' },
  'etc/set_hostname.sh': { 'mode': 744, 'template': 'jinja' },
  'etc/initramfs-tools/modules': { 'mode': 600, 'template': 'jinja' },
  'etc/initramfs-tools/hooks/litos-hook.sh': { 'mode': 700, 'template': 'jinja' },
  'etc/initramfs-tools/scripts/local-top/lit-os-init.sh': { 'mode': 700, 'template': 'jinja' },
  'etc/apparmor.d/abstractions/nameservice': { 'mode': 644  },
} %}

{% for file, opts in files.items() %}
/{{ file }}:
  file:
    - managed
    - source: salt://lit/os/guest/base/{{ file }}
    - user: root
    - group: root
    - mode: {{ opts.mode }}
    - makedirs: True
    - dir_mode: 755
{% if 'template' in opts %}
    - template: {{ opts.template }}
{% endif %}
{% endfor %}

{% for service in ['networking','set_hostname','journald'] %}
service_{{ service }}:
{% if pillar.get('is_chroot', False) == True %}
  # service.enabled doesn't appear to work.
  cmd.run:
    - name: systemctl enable {{service}}.service
{% else %}
  service.running:
    - name: {{service}}
    - enable: {{service}}
{% endif %}
{% endfor %}

{% for service in ['systemd-networkd'] %}
not_service_{{ service }}:
{% if pillar.get('is_chroot', False) == True %}
  cmd.run:
    - name: systemctl mask {{service}}.service
{% else %}
  service.masked:
    - name: {{service}}
    - enable: False
{% endif %}
{% endfor %}
