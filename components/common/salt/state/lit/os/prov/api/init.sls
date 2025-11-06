include:
  - rust
{% if pillar.get('no_checkouts', False) == False %}
  - lit.core.assets.repo
{% endif %}

{% set req_pkgs = [
  'build-essential'
] %}

{% for pkg in req_pkgs %}
lit_prov_api_req_pkg_{{ pkg }}:
  pkg.installed:
    - name: {{ pkg }}
{% endfor %}

/etc/lit/api.prov.config.toml:
  file:
    - managed
    - source: salt://lit/os/prov/api/config/config.toml
    - replace: False
    - user: root
    - group: root
    - mode: 600
    - template: jinja
    - require:
        - file: /etc/lit

/etc/lit/api.prov.config.toml_acl:
  acl.present:
    - name: /etc/lit/api.prov.config.toml
    - acl_type: group
    - acl_name: lit-config
    - perms: rx
    - require:
        - file: /etc/lit/api.prov.config.toml
        - group: lit_config_group

lit_prov_group:
  group.present:
    - name: lit-prov
    - gid: 4102

lit_prov_user:
  user.present:
    - name: lit-prov
    - fullname: Lit Prov
    - shell: /bin/bash
    - home: /var/lit/os/prov
    - uid: 4102
    - gid: 4102
    - groups:
        - lit-config
        - lit-cache
{% if pillar.get('litos_guest', False) == True %}
        - lit-attestation-user
        - lit-logging-user
{% endif %}
    - require:
        - group: lit-prov
        - group: lit-config
        - group: lit-cache
{% if pillar.get('litos_guest', False) == True %}
        - group: lit-attestation-user
        - group: lit-logging-user
{% endif %}

/var/lit/os/prov:
  file.directory:
    - user: lit-prov
    - group: lit-prov
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
        - file: /var/lit
        - user: lit_prov_user

/var/lit/os/prov/api:
  file.directory:
    - user: lit-prov
    - group: lit-prov
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
        - file: /var/lit/os/prov
        - user: lit_prov_user

{% set cfg_files = [
  'Rocket.toml'
] %}

{% for cfg in cfg_files %}
/var/lit/os/prov/api/{{ cfg }}:
  file:
    - managed
    - source: salt://lit/os/prov/api/config/{{ cfg }}
    - replace: False
    - user: lit-prov
    - group: lit-prov
    - mode: 644
    - template: jinja
    - require:
        - file: /var/lit/os/prov/api
        - user: lit_prov_user
{% endfor %}

/opt/lit/os/prov/bin:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
        - file: /opt/lit

prov_api_install:
  cmd.run:
    - name: >
        cargo clean &&
        cargo test &&
        cargo build {{ pillar.rust_build_args[pillar.env] }} --color never &&
        cp -f ../{{ pillar.rust_build_dir[pillar.env] }}/api /opt/lit/os/prov/bin/api &&
        cp Rocket.toml /var/lit/os/prov/api &&
        cargo clean
    - cwd: /opt/assets/lit-assets/rust/lit-os/lit-os-prov-api
    - prepend_path: /root/.cargo/bin
    - creates: /opt/lit/os/prov/bin/api
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
        - git: lit-assets
{% endif %}
    - require:
{% if pillar.get('no_checkouts', False) == False %}
        - git: lit-assets
{% endif %}
        - cmd: cargo_install_root
        - file: /opt/lit/os/prov/bin
{% for pkg in req_pkgs %}
        - pkg: lit_prov_api_req_pkg_{{ pkg }}
{% endfor %}

/opt/lit/os/prov/bin/before-start.sh:
  file:
    - managed
    - source: salt://lit/os/prov/api/scripts/before-start.sh
    - replace: False
    - user: root
    - group: root
    - mode: 700
    - template: jinja
    - require:
        - file: /opt/lit/os/prov/bin
        - cmd: prov_api_install

/etc/systemd/system/prov-api.service:
  file:
    - managed
    - source: salt://lit/os/prov/api/etc/systemd/system/prov-api.service
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - require:
        - cmd: prov_api_install
        - user: lit_prov_user
        - file: /opt/lit/os/prov/bin/before-start.sh
        - file: /etc/lit/api.prov.config.toml
        - file: /var/lit/os/prov/api
{% for cfg in cfg_files %}
        - file: /var/lit/os/prov/api/{{ cfg }}
{% endfor %}

prov-api:
{% if pillar.get('is_chroot', False) == True %}
  # service.enabled doesn't appear to work.
  cmd.run:
    - name: systemctl enable prov-api.service
{% else %}
  service.running:
    - name: prov-api
    - enable: prov-api
    - watch:
        - cmd: prov_api_install
        - file: /etc/lit/api.prov.config.toml
        - file: /etc/systemd/system/prov-api.service
{% endif %}
    - require:
        - cmd: prov_api_install
        - user: lit_prov_user
        - file: /etc/systemd/system/prov-api.service