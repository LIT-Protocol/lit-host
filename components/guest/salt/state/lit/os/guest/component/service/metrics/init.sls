include:
- rust
{% if pillar.get('no_checkouts', False) == False %}
- lit.core.assets.repo
{% endif %}

{% set req_pkgs = [
  'build-essential'
] %}

{% for pkg in req_pkgs %}
lit_os_metrics_cli_req_pkg_{{ pkg }}:
  pkg.installed:
    - name: {{ pkg }}
{% endfor %}

lit_os_metrics_user_group:
  group.present:
    - name: lit-os-metrics-user
    - system: True

/opt/lit/metrics/bin:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
      - file: /opt/lit

# Define common resource attributes for guest
{% set guest_attrs = '--resource-attribute system_context=guest' %}

os_metrics_install:
  cmd.run:
    - name: >
        cargo clean &&
        cargo test &&
        cargo build {{ pillar.rust_build_args[pillar.env] }} --color never &&
        cp ../{{ pillar.rust_build_dir[pillar.env] }}/lit-os-metrics /opt/lit/metrics/bin/lit-os-metrics &&
        cargo clean
    - cwd: /opt/assets/lit-assets/rust/lit-os/lit-os-metrics
    - prepend_path: /root/.cargo/bin
    - creates: /opt/lit/metrics/bin/lit-os-metrics
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
      - git: lit-assets
{% endif %}
    - require:
      - group: lit-os-metrics-user
{% if pillar.get('no_checkouts', False) == False %}
      - git: lit-assets
{% endif %}
      - cmd: cargo_install_root
      - file: /opt/lit/metrics/bin
{% for pkg in req_pkgs %}
      - pkg: lit_os_metrics_cli_req_pkg_{{ pkg }}
{% endfor %}

os_metrics_1_minute:
  cron.present:
    - name: >
        /opt/lit/metrics/bin/lit-os-metrics
        --query=memory-info
        --query=load-average
        --query=cpu-info
        {{ guest_attrs }}
    - user: root
    - minute: '*'
    - hour: '*'
    - daymonth: '*'
    - month: '*'
    - dayweek: '*'
    - require:
      - cmd: os_metrics_install

os_metrics_15_minutes:
  cron.present:
    - name: >
        /opt/lit/metrics/bin/lit-os-metrics
        --query=running-process
        --query=established-outbound
        --query=disk-info
        {{ guest_attrs }}
    - user: root
    - minute: '*/15'
    - hour: '*'
    - daymonth: '*'
    - month: '*'
    - dayweek: '*'
    - require:
      - cmd: os_metrics_install

os_metrics_hourly:
  cron.present:
    - name: >
        /opt/lit/metrics/bin/lit-os-metrics
        --query=cron-job
        --query=login-history
        --query=docker-running-containers
        --query=listening-ports
        --query=kernel-info
        --query=uptime
        --query=iptables
        {{ guest_attrs }}
    - user: root
    - minute: '0'
    - hour: '*/1'
    - daymonth: '*'
    - month: '*'
    - dayweek: '*'
    - require:
      - cmd: os_metrics_install

os_metrics_daily:
  cron.present:
    - name: >
        /opt/lit/metrics/bin/lit-os-metrics
        --query=os-info
        --query=debian-package
        --query=interface-address
        --query=system-info
        {{ guest_attrs }}
    - user: root
    - minute: '0'
    - hour: '0'
    - daymonth: '*'
    - month: '*'
    - dayweek: '*'
    - require:
      - cmd: os_metrics_install
