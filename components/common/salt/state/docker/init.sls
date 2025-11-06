include:
  - pkgs.docker
  - pkgs.python3-docker

/etc/modprobe.d:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False

# sequence is important here, the following file must be present before docker starts
/etc/modprobe.d/disable-br-netfilter.conf:
  file:
    - managed
    - source: salt://docker/etc/modprobe.d/disable-br-netfilter.conf
    - replace: true
    - user: root
    - group: root
    - mode: 600
    - require:
      - file: /etc/modprobe.d

docker_service_up:
{% if pillar.get('is_chroot', False) == True %}
  # service.enabled doesn't appear to work.
  cmd.run:
    - name: systemctl enable docker
{% else %}
  service.running:
    - name: docker
    - enable: docker
    # TODO: doesn't find the file although it exists
    # - watch:
    #  - file: /lib/systemd/system/docker.service
{% endif %}
    - require:
      - pkg: docker
      - pkg: python3-docker
      - file: /etc/modprobe.d/disable-br-netfilter.conf

restart_docker_because_lit_os_update_breaks_networking:
  cmd.run:
    - name: systemctl restart docker
    - require:
      - docker_service_up
