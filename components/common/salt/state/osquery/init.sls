include:
  - pkgs.curl

osquery_install:
  cmd.run:
    - name: bash -c 'curl -sSL https://pkg.osquery.io/deb/osquery_5.12.1-1.linux_amd64.deb -o /tmp/osquery.deb && dpkg -i /tmp/osquery.deb && rm /tmp/osquery.deb'
    - unless: which osqueryd
    - require:
        - pkg: curl

/usr/bin/osqueryd:
  file.exists

/etc/systemd/system/osqueryd.service:
  file.managed:
    - source: salt://osquery/etc/systemd/system/osqueryd.service
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: /usr/bin/osqueryd

enable_and_start_program:
{% if pillar.get('is_chroot', False) == True %}
  cmd.run:
    - name: systemctl enable osqueryd
{% else %}
  service.running:
    - name: osqueryd
    - enable: True
    - reload: True
{% endif %}
    - require:
      - file: /usr/bin/osqueryd
    - watch:
      - file: /etc/systemd/system/osqueryd.service