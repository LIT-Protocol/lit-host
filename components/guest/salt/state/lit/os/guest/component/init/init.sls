include:
  - rust
{% if pillar.get('no_checkouts', False) == False %}
  - lit.core.assets.repo
{% endif %}

  # line 1 used at runtime by initrd rust code
  # line 2 needed at buildtime for `libcryptsetup-rs` as per https://github.com/stratis-storage/libcryptsetup-rs?tab=readme-ov-file#building
{% set req_pkgs = [
  'grep', 'gawk', 'iproute2',
  'build-essential', 'pkg-config', 'cryptsetup', 'libcryptsetup-dev', 'clang-13'
] %}

{% for pkg in req_pkgs %}
lit_os_init_req_pkg_{{ pkg }}:
  pkg.installed:
    - name: {{ pkg }}
{% endfor %}

/opt/lit/os/init:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
        - file: /opt/lit

#DJR: Do not enable rust_build_args/rust_build_dir (makes hash too slow).
lit_os_init_install:
  cmd.run:
    - name: >
        cargo clean &&
        cargo test &&
        cargo build --release --no-default-features --features {{ pillar.litos_init_features }} --color never &&
        cp ../target/release/lit-os-init /opt/lit/os/init &&
        cp ../target/release/lit-os-cache-warmer /opt/lit/os/init &&
        cargo clean
    - cwd: /opt/assets/lit-assets/rust/lit-os/lit-os-guest-initrd
    - prepend_path: /root/.cargo/bin
    - creates: /opt/lit/os/init/lit-os-init
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
        - git: lit-assets
{% endif %}
    - require:
{% if pillar.get('no_checkouts', False) == False %}
        - git: lit-assets
{% endif %}
        - cmd: cargo_install_root
        - file: /opt/lit/os/init
{% for pkg in req_pkgs %}
        - pkg: lit_os_init_req_pkg_{{ pkg }}
{% endfor %}

lit_os_warm_cache:
  cmd.run:
    - name: /opt/lit/os/init/lit-os-cache-warmer
    - creates: /var/cache/sev-snp/certs/Milan/cert_chain.pem
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
        - git: lit-assets
        - cmd: lit_os_init_install
{% endif %}
    - require:
        - cmd: lit_os_init_install

lit_os_sev_snp_cache_perms:
  cmd.run:
    - name: >
        find /var/cache/sev-snp -type d -exec /usr/bin/setfacl -m g:lit-cache:rwx {} \; &&
        find /var/cache/sev-snp -type f -exec /usr/bin/setfacl -m g:lit-cache:rw {} \;
{% if pillar.get('no_checkouts', False) == False %}
    - watch:
        - cmd: lit_os_warm_cache
{% endif %}
    - require:
        - cmd: lit_os_warm_cache


{% for script in ['lit-os-init-prepare.sh', 'lit-os-init-cleanup.sh'] %}
/opt/lit/os/init/{{ script }}:
  file:
    - managed
    - source: salt://lit/os/guest/component/init/scripts/{{ script }}
    - user: root
    - group: root
    - mode: 700
    - require:
        - cmd: lit_os_init_install
        - cmd: lit_os_sev_snp_cache_perms

{% endfor %}