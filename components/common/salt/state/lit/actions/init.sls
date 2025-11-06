include:
  - rust
  - pkgs.build-essential

{% set req_pkgs = [
  'gcc', 'g++', 'make', 'cmake', 'protobuf-compiler'
] %}

{% for pkg in req_pkgs %}
lit_actions_req_pkg_{{ pkg }}:
  pkg.installed:
    - name: {{ pkg }}
{% endfor %}

lit_actions_user:
  user.present:
    - name: lit-actions
    - fullname: Lit Actions
    - system: True # no homefolder and no shell login
{% if pillar.get('litos_guest', False) == True %}
    - groups:
        - lit-logging-user
{% endif %}

/opt/lit/actions/bin:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
        - file: /opt/lit

lit_actions_install:
  cmd.run:
    - name: >
        cargo clean &&
        cargo build {{ pillar.rust_build_args[pillar.env] }} --color never &&
        cp -f {{ pillar.rust_build_dir[pillar.env] }}/lit_actions /opt/lit/actions/bin/lit_actions &&
        chown root:root /opt/lit/actions/bin/lit_actions &&
        cargo clean &&
        touch /var/local/lit-actions.install
    - cwd: /opt/assets/lit-assets/rust/lit-actions
    - prepend_path: /root/.cargo/bin
    - creates: /var/local/lit-actions.install
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
        - git: lit-assets
{% endif %}
    - require:
{% if pillar.get('no_checkouts', False) == False %}
        - git: lit-assets
{% endif %}
        - cmd: cargo_install_root
        - file: /opt/lit/actions/bin
{% for pkg in req_pkgs %}
        - pkg: lit_actions_req_pkg_{{ pkg }}
{% endfor %}

/etc/systemd/system/lit-actions.service:
  file:
    - managed
    - source: salt://lit/actions/etc/systemd/system/lit-actions.service
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - require:
        - cmd: lit_actions_install

lit-actions:
{% if pillar.get('is_chroot', False) == True %}
  # service.enabled doesn't appear to work.
  cmd.run:
    - name: systemctl enable lit-actions.service
{% else %}
  service.running:
    - name: lit-actions
    - enable: lit-actions
    - watch:
        - cmd: lit_actions_install
        - file: /etc/systemd/system/lit-actions.service
{% endif %}
    - require:
        - cmd: lit_actions_install
        - file: /etc/systemd/system/lit-actions.service
