include:
  - rust
  - lit.core.assets.repo

operator_build_and_install:
  cmd.run:
    - name: >
        cargo clean &&
        cargo build {{ pillar.rust_build_args[pillar.env] }} --color never --locked &&
        mkdir -p /opt/lit/operator/bin &&
        cp -f ../{{ pillar.rust_build_dir[pillar.env] }}/lit-node-operator /opt/lit/operator/bin/lit-node-operator &&
        chmod 700 /opt/lit/operator/bin/lit-node-operator &&
        cargo clean
    - cwd: /opt/assets/lit-assets/rust/lit-os/lit-node-operator
    - prepend_path: /root/.cargo/bin
    - watch:
        - git: lit-assets
    - require:
        - git: lit-assets
        - cmd: cargo_install_root


/etc/systemd/system/lit-node-operator.service:
  file:
    - managed
    - source: salt://lit/os/node-operator/etc/systemd/system/lit-node-operator.service
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - require:
        - cmd: operator_build_and_install

lit-node-operator:
  service.running:
    - name: lit-node-operator
    - enable: True
    - sig: dead
    - watch:
        - cmd: operator_build_and_install
        - file: /etc/systemd/system/lit-node-operator.service
    - require:
        - cmd: operator_build_and_install
        - file: /etc/systemd/system/lit-node-operator.service

restart_operator:
  cmd.run:
    - name: systemctl restart lit-node-operator
    - onchanges:
        - cmd: operator_build_and_install
        - file: /etc/systemd/system/lit-node-operator.service
    - require:
        - service: lit-node-operator
