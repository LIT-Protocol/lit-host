include:
  - pkgs.openssh-server

/etc/ssh/sshd_config:
  file:
    - managed
    - source: salt://sshd/etc/ssh/sshd_config
    - template: jinja
    - require:
      - pkg: openssh-server

{% if not salt['service.enabled']('ssh') %}
# service.enable doesn't appear to work.
ssh-enabled:
  cmd.run:
    - name: systemctl enable ssh.service
{% endif %}

{% if pillar.get('is_chroot', False) == False %}
ssh-running:
  service.running:
    - name: ssh
    - watch:
        - file: /etc/ssh/sshd_config
    - require:
        - file: /etc/ssh/sshd_config
{% endif %}