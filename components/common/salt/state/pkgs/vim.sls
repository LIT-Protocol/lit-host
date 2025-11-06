vim:
  pkg:
    - installed

/etc/vim/vimrc.local:
  file:
    - managed
    - user: root
    - group: root
    - mode: 644
    - source: salt://pkgs/vim/vimrc.local.jin
    - template: jinja

/root/.vim/view:
  file.directory:
    - user: root
    - group: root
    - makedirs: True
