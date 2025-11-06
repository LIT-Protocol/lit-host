include:
  - rust
  - pkgs.pkg-config
  - pkgs.libssl-dev
{% if pillar.get('no_checkouts', False) == False %}
  - lit.core.assets.repo
{% endif %}
  - lit.os.scripts

/opt/lit/env:
  file:
    - managed
    - source: salt://lit/os/cli/env
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - require:
        - file: /opt/lit

#DJR: Do not enable rust_build_args/rust_build_dir (makes hash too slow).
lit_cli_install:
  cmd.run:
    - name: >
        cargo clean &&
        cargo test &&
        cargo build --release --no-default-features --features {{ pillar.litos_cli_features }} --color never &&
        cp -f ../target/release/lit /usr/local/bin/ &&
        cargo clean &&
        rm -f /opt/lit/env.bash &&
        touch /var/local/lit-cli.install
    - cwd: /opt/assets/lit-assets/rust/lit-os/lit-cli
    - prepend_path: /root/.cargo/bin
    - creates: /var/local/lit-cli.install
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
        - git: lit-assets
{% endif %}
    - require:
{% if pillar.get('no_checkouts', False) == False %}
        - git: lit-assets
{% endif %}
        - cmd: cargo_install_root
        - file: /etc/lit/config.toml
        - file: /opt/lit/env

lit_cli_init:
  cmd.run:
    - name: /usr/local/bin/lit init generate bash > /opt/lit/env.bash
    - creates: /opt/lit/env.bash
    - require:
        - cmd: lit_cli_install
        - file: /etc/lit/config.toml
        - file: /opt/lit/env