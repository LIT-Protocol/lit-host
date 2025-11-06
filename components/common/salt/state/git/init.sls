include:
  - pkgs.git

git_group:
  group.present:
    - name: git
    - gid: 4001

git_user:
  user.present:
    - name: git
    - fullname: Git
    - shell: /bin/bash
    - home: /home/git
    - uid: 4001
    - allow_uid_change: True
    - gid: 4001
    - allow_gid_change: True
    - require:
      - pkg: git
      - group: git

/home/git:
  file.directory:
    - user: git
    - group: git
    - dir_mode: 700
    - file_mode: 600
    - makedirs: True
    - recurse:
        - user
        - group
        - mode
    - require:
        - user: git

/home/git/.ssh:
  file.directory:
    - user: git
    - group: git
    - dir_mode: 700
    - file_mode: 600
    - makedirs: True
    - recurse:
        - user
        - group
        - mode
    - require:
        - user: git
        - file: /home/git

{% if 'git_ssh_keys' in pillar %}
{% for name, _ in salt.pillar.get('git_ssh_keys', {}).items() %}
/home/git/.ssh/id_git_{{ name }}:
  file:
    - managed
    - user: git
    - group: git
    - mode: 600
    - contents_pillar: git_ssh_keys:{{ name }}:key
    - require:
        - file: /home/git/.ssh
{% endfor %}
{% endif %}

/home/git/.ssh/config:
  file:
    - managed
    - user: git
    - group: git
    - source: salt://git/ssh/config
    - template: jinja
    - require:
        - file: /home/git/.ssh
{% if 'git_ssh_keys' in pillar %}
{% for name, _ in salt.pillar.get('git_ssh_keys', {}).items() %}
        - file: /home/git/.ssh/id_git_{{ name }}
{% endfor %}
{% endif %}

/opt/assets:
  file.directory:
    - user: git
    - group: git
    - dir_mode: 755
    - makedirs: True
    - recurse:
        - user
        - group
    - require:
        - user: git
        - file: /home/git/.ssh/config

github.com:
  ssh_known_hosts:
    - present
    - user: git
    - require:
        - user: git
        - file: /home/git/.ssh/config
        - file: /opt/assets