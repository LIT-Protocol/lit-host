include:
  - rust
{% if pillar.get('no_checkouts', False) == False %}
  - lit.core.assets.repo
{% endif %}

{% set req_pkgs = [
  'build-essential'
] %}

{% for pkg in req_pkgs %}
lit_attestation_service_req_pkg_{{ pkg }}:
  pkg.installed:
    - name: {{ pkg }}
{% endfor %}

lit_attestation_user_group:
  group.present:
    - name: lit-attestation-user
    - gid: 7401

/var/lit/attestation:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
      - file: /var/lit

/opt/lit/attestation/bin:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
      - file: /opt/lit

attestation_service_install:
  cmd.run:
    - name: >
        cargo clean &&
        cargo test &&
        cargo build {{ pillar.rust_build_args[pillar.env] }} --color never &&
        cp ../{{ pillar.rust_build_dir[pillar.env] }}/lit-attestation-service /opt/lit/attestation/bin/lit-attestation-service &&
        cargo clean
    - cwd: /opt/assets/lit-assets/rust/lit-os/lit-attestation-service
    - prepend_path: /root/.cargo/bin
    - creates: /opt/lit/attestation/bin/lit-attestation-service
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
      - git: lit-assets
{% endif %}
    - require:
      - group: lit-attestation-user
{% if pillar.get('no_checkouts', False) == False %}
      - git: lit-assets
{% endif %}
      - cmd: cargo_install_root
      - file: /opt/lit/attestation/bin
{% for pkg in req_pkgs %}
      - pkg: lit_attestation_service_req_pkg_{{ pkg }}
{% endfor %}

/etc/systemd/system/lit-attestation.service:
  file:
    - managed
    - source: salt://lit/os/guest/component/service/attestation/etc/systemd/system/lit-attestation.service
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - require:
      - cmd: attestation_service_install
      - file: /var/lit/attestation

attestation_service:
{% if pillar.get('is_chroot', False) == True %}
  # service.enabled doesn't appear to work.
  cmd.run:
    - name: systemctl enable lit-attestation
{% else %}
  service.running:
    - name: lit-attestation
    - enable: lit-attestation
    - watch:
      - cmd: attestation_service_install
      - file: /etc/systemd/system/lit-attestation.service
{% endif %}
    - require:
      - group: lit-attestation-user
      - cmd: attestation_service_install
      - file: /etc/systemd/system/lit-attestation.service