/etc/motd:
  file:
    - managed
    - source: salt://users/motd/motd.jin
    - template: jinja
