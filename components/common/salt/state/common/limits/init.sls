/etc/security/limits.conf:
  file:
    - managed
    - source: salt://common/limits/etc/security/limits.conf
    - user: root
    - group: root
    - mode: 600
    - makedirs: True
    - dir_mode: 755
    - template: jinja