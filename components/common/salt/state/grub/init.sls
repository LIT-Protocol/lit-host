/etc/default/grub:
  file:
    - managed
    - user: root
    - group: root
    - mode: 644
    - source: salt://grub/etc/default/grub
    - template: jinja

update-grub:
  cmd.run:
    - name: update-grub
    - onchanges:
        - file: /etc/default/grub