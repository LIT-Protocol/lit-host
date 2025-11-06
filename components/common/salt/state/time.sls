include:
  - pkgs.systemd-timesyncd

{% if 'timezone' in pillar %}
set_timezone:
{% if pillar.get('is_chroot', False) == True %}
  file:
    - managed
    - name: /etc/timezone
    - contents_pillar: timezone
    - user: root
    - group: root
    - mode: 644
{% else %}
  timezone.system:
    - name: {{ pillar.timezone }}
{% endif %}
{% endif %}

systemd-timesyncd-service:
{% if pillar.get('is_chroot', False) == True %}
  # service.enabled doesn't appear to work.
  cmd.run:
    - name: systemctl enable systemd-timesyncd
{% else %}
  service.running:
    - name: systemd-timesyncd
    - enable: systemd-timesyncd
{% endif %}
{% if 'timezone' in pillar %}
    - require:
{% if pillar.get('is_chroot', False) == True %}
        - file: set_timezone
{% else %}
        - timezone: set_timezone
{% endif %}
{% endif %}