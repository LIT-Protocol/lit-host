include:
  - rust
{% if pillar.get('no_checkouts', False) == False %}
  - lit.core.assets.repo
{% endif %}

{% set req_pkgs = [
  'build-essential'
] %}

{% for pkg in req_pkgs %}
lit_logging_service_req_pkg_{{ pkg }}:
  pkg.installed:
    - name: {{ pkg }}
{% endfor %}

lit_logging_user_group:
  group.present:
    - name: lit-logging-user
    - gid: 7402

/var/lit/logging:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
      - file: /var/lit

/opt/lit/logging/bin:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
      - file: /opt/lit

logging_service_install:
  cmd.run:
    - name: >
        cargo clean &&
        cargo test &&
        cargo build {{ pillar.rust_build_args[pillar.env] }} --color never &&
        cp ../{{ pillar.rust_build_dir[pillar.env] }}/lit-logging-service /opt/lit/logging/bin/lit-logging-service &&
        cargo clean
    - cwd: /opt/assets/lit-assets/rust/lit-os/lit-logging-service
    - prepend_path: /root/.cargo/bin
    - creates: /opt/lit/logging/bin/lit-logging-service
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
      - git: lit-assets
{% endif %}
    - require:
      - group: lit-logging-user
{% if pillar.get('no_checkouts', False) == False %}
      - git: lit-assets
{% endif %}
      - cmd: cargo_install_root
      - file: /opt/lit/logging/bin
{% for pkg in req_pkgs %}
      - pkg: lit_logging_service_req_pkg_{{ pkg }}
{% endfor %}

/etc/systemd/system/lit-logging.service:
  file:
    - managed
    - source: salt://lit/os/guest/component/service/logging/etc/systemd/system/lit-logging.service
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - require:
      - cmd: logging_service_install
      - file: /var/lit/logging

logging_service:
{% if pillar.get('is_chroot', False) == True %}
  # service.enabled doesn't appear to work.
  cmd.run:
    - name: systemctl enable lit-logging
{% else %}
  service.running:
    - name: lit-logging
    - enable: lit-logging
    - watch:
      - cmd: logging_service_install
      - file: /etc/systemd/system/lit-logging.service
{% endif %}
    - require:
      - group: lit-logging-user
      - cmd: logging_service_install
      - file: /etc/systemd/system/lit-logging.service