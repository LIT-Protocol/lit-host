include:
  - pkgs.curl

# download a rust deployment to the cargo paths
cargo_install_root:
  cmd.run:
    - name: bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -q -y --default-toolchain {{ pillar.rust_default_toolchain }} && chmod -R 700 /root/{.rustup,.cargo}'
    - env:
        - TMPDIR: "{{ pillar.tmp_dir }}"
    - require:
        - pkg: curl

# Install Rust to other users on host only
# NOTE: While we set the env here, it's actually persisted through a .bashrc file we write separately from this installation 
# see https://github.com/LIT-Protocol/lit-os/blob/e93945d37d561202a58a69fa816ae7d2b4a9a962/components/common/salt/state/users/bash/bash.bashrc.debian#L117
{% if pillar.get('is_chroot', False) == False %}
{% for username, userinfo in salt.pillar.get('users', {}).items() %}
{% if userinfo.active == True and pillar.env in userinfo.access and 'features' in userinfo and 'rust' in userinfo.features %}
cargo_install_{{ username }}:
  cmd.run:
    - name: bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -q -y --default-toolchain {{ pillar.rust_default_toolchain }} && chmod -R 700 /home/{{ username }}/{.rustup,.cargo}' && sleep 5
    - runas: {{ username }}
    - env:
        - TMPDIR: "{{ pillar.tmp_dir }}"
    - require:
        - pkg: curl
        - user: {{ username }}
{% endif %}
{% endfor %}
{% endif %}
