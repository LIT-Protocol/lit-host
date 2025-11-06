/usr/local/bin/install-tee-amd.sh:
  file:
    - managed
    - source: salt://lit/os/tee/amd/install/scripts/install.sh
    - template: jinja
    - user: root
    - group: root
    - mode: 700

install_tee_amd:
  cmd.run:
    - name: /usr/local/bin/install-tee-amd.sh && touch /var/local/litos-tee-amd.install
    - creates: /var/local/litos-tee-amd.install
    - require:
      - file: /usr/local/bin/install-tee-amd.sh

/etc/modprobe.d/kvm.conf:
  file:
    - managed
    - source: salt://lit/os/tee/amd/install/etc/modprobe.d/kvm.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - require:
      - cmd: install_tee_amd

/opt/AMDSEV/usr/local/etc:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - file_mode: 644
    - makedirs: True

# Script to add the virtualized network devices to the bridge on host
/opt/AMDSEV/usr/local/etc/qemu-ifup:
  file:
    - managed
    - source: salt://lit/os/tee/common/usr/local/etc/qemu-ifup
    - template: jinja
    - user: root
    - group: root
    - mode: 755
    - require:
        - file: /opt/AMDSEV/usr/local/etc
