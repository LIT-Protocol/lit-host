include:
  - osquery
  - monitoring.otelcol
  - rust
  - lit.core.assets.repo

{% set req_pkgs = [
  'build-essential'
] %}

{% for pkg in req_pkgs %}
monitoring_lit_os_metrics_host_req_pkg_{{ pkg }}:
  pkg.installed:
    - name: {{ pkg }}
{% endfor %}

{% set pillar_1min_enabled = salt['pillar.get']('lit-os-metrics-host:interval_1min:enabled', True) %}
{% set pillar_15min_enabled = salt['pillar.get']('lit-os-metrics-host:interval_15min:enabled', True) %}

monitoring_lit_os_metrics_host_build_and_install:
  cmd.run:
    - name: >
        cargo clean &&
        cargo test &&
        cargo build {{ pillar.rust_build_args[pillar.env] }} --color never &&
        cp ../{{ pillar.rust_build_dir[pillar.env] }}/lit-os-metrics /usr/local/bin/lit-os-metrics-host &&
        cargo clean
    - cwd: /opt/assets/lit-assets/rust/lit-os/lit-os-metrics
    - prepend_path: /root/.cargo/bin
    - creates: /usr/local/bin/lit-os-metrics-host
    - watch:
      - git: lit-assets
    - require:
      - git: lit-assets
      - cmd: cargo_install_root
{% for pkg in req_pkgs %}
      - pkg: monitoring_lit_os_metrics_host_req_pkg_{{ pkg }}
{% endfor %}

{% if pillar_1min_enabled %}

monitoring_lit_os_metrics_host_1min_service_file:
  file.managed:
    - name: /etc/systemd/system/lit-os-metrics-host-1min.service
    - source: salt://monitoring/lit-os-metrics-host/etc/systemd/system/lit-os-metrics-host-1min.service.j2
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - require:
      - cmd: monitoring_lit_os_metrics_host_build_and_install
    - watch_in:
      - cmd: systemd_daemon_reload_lit_os_metrics_host

monitoring_lit_os_metrics_host_1min_timer_file:
  file.managed:
    - name: /etc/systemd/system/lit-os-metrics-host-1min.timer
    - source: salt://monitoring/lit-os-metrics-host/etc/systemd/system/lit-os-metrics-host-1min.timer.j2
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - watch_in:
      - cmd: systemd_daemon_reload_lit_os_metrics_host

monitoring_lit_os_metrics_host_1min_timer_service:
  service.running:
    - name: lit-os-metrics-host-1min.timer
    - enable: True
    - require:
      - file: monitoring_lit_os_metrics_host_1min_service_file
      - file: monitoring_lit_os_metrics_host_1min_timer_file
      - service: osqueryd
      - service: otelcol
    - watch:
      - file: monitoring_lit_os_metrics_host_1min_timer_file
      - file: monitoring_lit_os_metrics_host_1min_service_file

{% endif %}

{% if pillar_15min_enabled %}

monitoring_lit_os_metrics_host_15min_service_file:
  file.managed:
    - name: /etc/systemd/system/lit-os-metrics-host-15min.service
    - source: salt://monitoring/lit-os-metrics-host/etc/systemd/system/lit-os-metrics-host-15min.service.j2
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - require:
      - cmd: monitoring_lit_os_metrics_host_build_and_install
    - watch_in:
      - cmd: systemd_daemon_reload_lit_os_metrics_host

monitoring_lit_os_metrics_host_15min_timer_file:
  file.managed:
    - name: /etc/systemd/system/lit-os-metrics-host-15min.timer
    - source: salt://monitoring/lit-os-metrics-host/etc/systemd/system/lit-os-metrics-host-15min.timer.j2
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - watch_in:
      - cmd: systemd_daemon_reload_lit_os_metrics_host

monitoring_lit_os_metrics_host_15min_timer_service:
  service.running:
    - name: lit-os-metrics-host-15min.timer
    - enable: True
    - require:
      - file: monitoring_lit_os_metrics_host_15min_service_file
      - file: monitoring_lit_os_metrics_host_15min_timer_file
      - service: osqueryd
      - service: otelcol
    - watch:
      - file: monitoring_lit_os_metrics_host_15min_timer_file
      - file: monitoring_lit_os_metrics_host_15min_service_file

{% endif %}

systemd_daemon_reload_lit_os_metrics_host:
  cmd.wait:
    - name: systemctl daemon-reload
    - watch:
      - file: monitoring_lit_os_metrics_host_*_service_file
      - file: monitoring_lit_os_metrics_host_*_timer_file
