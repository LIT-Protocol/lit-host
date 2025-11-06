include:
  {% if salt['grains.get']('cpu_model', '') is match('.*[A][M][D].*') %}
  - lit.os.tee.amd
  {% endif %}

# Simple target for use in require.
lit_os_tee_init:
  cmd.run:
    - name: touch /var/local/litos-tee.install
    - creates: /var/local/litos-tee.install
    - require:
    {% if salt['grains.get']('cpu_model', '') is match('.*[A][M][D].*') %}
      - cmd: install_tee_amd
      - file: /etc/modprobe.d/kvm.conf
      - file: /opt/AMDSEV/usr/local/etc
    {% endif %}