/etc/sudoers.d/admin:
  file:
    - managed
    - source: salt://users/sudoers/sudoers-admin.jin
    - template: jinja
    - require:
      - pkg: sudo
      - sls: groups
