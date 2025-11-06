/etc/resolv.conf:
  file:
    - managed
    - source: salt://hosts/resolv.conf.jin
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - attrs: i # Mark with immutable attribute
    - replace: True
    - follow_symlinks: False
