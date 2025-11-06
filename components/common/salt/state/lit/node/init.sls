include:
  - rust
  - pkgs.build-essential
  - pkgs.nodejs-18

{% set req_pkgs = [
  'pkg-config', 'gcc', 'g++', 'make',
  'libssl-dev', 'libgmp3-dev', 'libudev-dev', 'libsqlite3-dev',
  'libprotobuf-c-dev', 'protobuf-c-compiler', 'python3', 'python3-protobuf',
  'libcrack2', 'cmake', 'protobuf-compiler'
] %}

{% for pkg in req_pkgs %}
lit_node_req_pkg_{{ pkg }}:
  pkg.installed:
    - name: {{ pkg }}
{% endfor %}

/etc/lit/node.config.toml:
  file:
    - managed
    - source: salt://lit/node/config/config.toml
    - replace: True
    - user: root
    - group: root
    - mode: 600
    - template: jinja
    - require:
        - file: /etc/lit

/etc/lit/node.config.toml_acl:
  acl.present:
    - name: /etc/lit/node.config.toml
    - acl_type: group
    - acl_name: lit-config
    - perms: rx
    - require:
        - file: /etc/lit/node.config.toml
        - group: lit_config_group

lit_node_group:
  group.present:
    - name: lit-node
    - gid: 4101

lit_node_user:
  user.present:
    - name: lit-node
    - fullname: Lit Node
    - shell: /bin/bash
    - home: /var/lit/node
    - uid: 4101
    - gid: 4101
    - groups:
        - lit-config
        - lit-cache
{% if pillar.get('litos_guest', False) == True %}
        - lit-attestation-user
        - lit-logging-user
{% endif %}
    - require:
        - file: /var/lit
        - group: lit-node
        - group: lit-config
        - group: lit-cache
{% if pillar.get('litos_guest', False) == True %}
        - group: lit-attestation-user
        - group: lit-logging-user
{% endif %}

/var/lit/node:
  file.directory:
    - user: lit-node
    - group: lit-node
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
        - user: lit_node_user
        - file: /var/lit

/var/lit/node/rpc-config.yaml:
  file.managed:
    - source: salt://lit/core/blockchain/config/rpc-config.yaml.jinja
    - replace: False
    - user: lit-node
    - group: lit-node
    - mode: 600
    - template: jinja
    - context:
        pillar: {{ pillar | json() }}
    - require:
        - file: /var/lit/node
        - user: lit_node_user

{% set cfg_files = [
  'Rocket.toml'
] %}

{% for cfg in cfg_files %}
/var/lit/node/{{ cfg }}:
  file:
    - managed
    - source: salt://lit/node/config/{{ cfg }}
    - replace: True
    - user: lit-node
    - group: lit-node
    - mode: 644
    - template: jinja
    - require:
        - file: /var/lit/node
        - user: lit_node_user
{% endfor %}

/opt/lit/node/bin:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
        - file: /opt/lit

lit_node_init_git_submodule:
  cmd.run:
    - name: git submodule init && git submodule update
    - cwd: /opt/assets/lit-assets/blockchain/contracts/lib
    - runas: git
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
        - git: lit-assets
{% endif %}
{% if pillar.get('no_checkouts', False) == False %}
    - require:
        - git: lit-assets
{% endif %}

lit_node_contracts_install:
  cmd.run:
    - name: npm install
    - cwd: /opt/assets/lit-assets/blockchain/contracts
    - runas: git
    - creates: /opt/assets/lit-assets/blockchain/contracts/node_modules
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
        - git: lit-assets
{% endif %}
    - require:
{% if pillar.get('no_checkouts', False) == False %}
        - git: lit-assets
{% endif %}
{% for pkg in req_pkgs %}
        - pkg: lit_node_req_pkg_{{ pkg }}
{% endfor %}
        - pkg: nodejs

lit_node_contracts_compile:
  cmd.run:
    - name: npx hardhat compile
    - cwd: /opt/assets/lit-assets/blockchain/contracts
    - runas: git
    - creates: /opt/assets/lit-assets/blockchain/contracts/artifacts
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
        - git: lit-assets
{% endif %}
    - require:
{% if pillar.get('no_checkouts', False) == False %}
        - git: lit-assets
{% endif %}
{% for pkg in req_pkgs %}
        - pkg: lit_node_req_pkg_{{ pkg }}
{% endfor %}
        - pkg: nodejs
        - cmd: lit_node_init_git_submodule
        - cmd: lit_node_contracts_install

# change to verify that node is here and works
lit_node_verify:
  cmd.run:
    - name: |
        chown root:root /opt/lit/node/bin/lit_node &&
        if [ ! -e "/opt/lit/node/bin/lit_node" ] || [ ! -x "/opt/lit/node/bin/lit_node" ] || ! file "/opt/lit/node/bin/lit_node" | grep -q "executable"; then
            echo "lit_node binary not valid"
            exit 1
        fi &&
        touch /var/local/lit-node.install
    - creates: /var/local/lit-node.install
    - require:
{% for pkg in req_pkgs %}
        - pkg: lit_node_req_pkg_{{ pkg }}
{% endfor %}

/etc/systemd/system/lit-node.service:
  file:
    - managed
    - source: salt://lit/node/etc/systemd/system/lit-node.service
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - require:
        - cmd: lit_node_verify
        - file: /etc/lit/node.config.toml
        - file: /var/lit/node
        - file: /var/lit/node/rpc-config.yaml
{% for cfg in cfg_files %}
        - file: /var/lit/node/{{ cfg }}
{% endfor %}

lit-node:
{% if pillar.get('is_chroot', False) == True %}
  # service.enabled doesn't appear to work.
  cmd.run:
    - name: systemctl enable lit-node.service
{% else %}
  service.running:
    - name: lit-node
    - enable: lit-node
    - watch:
        - cmd: lit_node_verify
        - file: /etc/lit/node.config.toml
        - file: /etc/systemd/system/lit-node.service
{% endif %}
    - require:
        - cmd: lit_node_verify
        - file: /etc/systemd/system/lit-node.service
