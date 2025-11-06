/etc/lit:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True

lit_config_group:
  group.present:
    - name: lit-config
    - gid: 7100

/etc/lit/config.toml:
  file:
    - managed
    - source: salt://lit/etc/lit/config.toml
    - user: root
    - group: root
    - mode: 600
    - replace: true
    - template: jinja
    - require:
        - file: /etc/lit
        - group: lit_config_group

/etc/lit/config.toml_acl:
  acl.present:
    - name: /etc/lit/config.toml
    - acl_type: group
    - acl_name: lit-config
    - perms: rx
    - require:
        - file: /etc/lit/config.toml
        - group: lit_config_group

/opt/lit:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False

/var/lit:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False

lit_cache_group:
  group.present:
    - name: lit-cache
    - gid: 7101

{% for d in ['/var/cache/lit-core', '/var/cache/sev-snp'] %}
{{ d }}:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False

{{ d }}_acl:
  acl.present:
    - name: {{ d }}
    - acl_type: group
    - acl_name: lit-cache
    - perms: rwx
    - recurse: True
    - require:
        - file: {{ d }}
        - group: lit_cache_group
{% endfor %}
