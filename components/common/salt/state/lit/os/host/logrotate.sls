include:
  - pkgs.logrotate

lit_os_host_logrotate_timer_override_dir:
  file.directory:
    - name: /etc/systemd/system/logrotate.timer.d
    - mode: '0755'
    - user: root
    - group: root

lit_os_host_logrotate_timer_override_conf:
  file.managed:
    - name: /etc/systemd/system/logrotate.timer.d/override.conf
    - mode: '0644'
    - user: root
    - group: root
    - contents: |
        [Timer]
        OnCalendar=
        OnCalendar=hourly
        Persistent=true
        RandomizedDelaySec=10m
        AccuracySec=1m
    - require:
      - file: lit_os_host_logrotate_timer_override_dir
      - pkg: logrotate
    - watch_in:
      - cmd: lit_os_host_logrotate_systemd_daemon_reload

lit_os_host_logrotate_timer_enabled:
  service.enabled:
    - name: logrotate.timer
    - require:
      - file: lit_os_host_logrotate_timer_override_conf

lit_os_host_logrotate_timer_running:
  service.running:
    - name: logrotate.timer
    - enable: True
    - require:
      - service: lit_os_host_logrotate_timer_enabled
    - watch:
      - file: lit_os_host_logrotate_timer_override_conf
      - cmd: lit_os_host_logrotate_systemd_daemon_reload

lit_os_host_logrotate_systemd_daemon_reload:
  cmd.wait:
    - name: systemctl daemon-reload
    - watch:
      - file: lit_os_host_logrotate_timer_override_conf

