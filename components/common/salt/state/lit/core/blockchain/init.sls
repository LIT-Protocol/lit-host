/etc/lit/rpc-config.yaml:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - source: salt://lit/core/blockchain/config/rpc-config.yaml.jinja
    - template: jinja
    - context:
        pillar: {{ pillar | json() }}
    - require:
        - file: /etc/lit

/etc/lit/rpc-config.yaml_acl:
  acl.present:
    - name: /etc/lit/rpc-config.yaml
    - acl_type: group
    - acl_name: lit-config
    - perms: rx
    - require:
        - file: /etc/lit/rpc-config.yaml
        - group: lit_config_group
