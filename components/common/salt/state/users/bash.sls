/etc/bash.bashrc:
  file:
    - managed
    - source: salt://users/bash/bash.bashrc.{{ grains['os'].lower() }}
    - template: jinja

/etc/skel/.bashrc:
  file:
    - managed
    - source: salt://users/bash/user.bashrc.{{ grains['os'].lower() }}
    - template: jinja

/root/.bashrc:
  file:
    - managed
    - source: salt://users/bash/user.bashrc.{{ grains['os'].lower() }}
    - template: jinja
