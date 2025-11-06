include:
  - users.sudoers
  - users.bash
  - users.motd

root:
  alias.present:
    - target: {{ pillar.root_email }}

{% for username, userinfo in salt.pillar.get('users', {}).items() %}
{% set user_gid = pillar.groups[userinfo.groups[0]].gid %}
{% set user_group = userinfo.groups[0] %}
{{ username }}:
{% if userinfo.active == True and pillar.env in userinfo.access %}
  user.present:
    - fullname: {{ userinfo.name }}
    - shell: {{ userinfo.shell }}
    - home: /home/{{ username }}
    - allow_uid_change: True
    - allow_gid_change: True
    {% if user_gid %}
    - gid: {{ user_gid }}
    {% endif %}
    {% if userinfo.groups %}
    - groups:
    {% for group in userinfo.groups %}
      - {{ group }}
    {% endfor %}
    {% endif %}
  {% if 'ssh_keys' in userinfo %}
  ssh_auth:
    - present
    - names:
      {% for key in userinfo.ssh_keys %}
      - {{ key }}
      {% endfor %}
    - user: {{ username }}
    - require:
      - user: {{ username }}
  {% endif %}

/home/{{ username }}:
  file.directory:
    - user: {{ username }}
    - group: {{ user_group }}
    - dir_mode: 755
    - file_mode: 644
    - makedirs: True

/home/{{ username }}/.vim/view:
  file.directory:
    - user: {{ username }}
    - group: {{ user_group }}
    - dir_mode: 700
    - file_mode: 600
    - makedirs: True
    - require:
      - file: /home/{{ username }}

/home/{{ username }}/.ssh:
  file.directory:
    - user: {{ username }}
    - group: {{ user_group }}
    - dir_mode: 700
    - file_mode: 600
    - makedirs: True
    - recurse:
        - user
        - group
        - mode
    - require:
      - file: /home/{{ username }}

/home/{{ username }}/.bashrc:
  file:
    - managed
    - user: {{ username }}
    - group: {{ user_group }}
    - source: salt://users/bash/user.bashrc.{{ grains['os'].lower() }}
    - template: jinja
    - require:
      - file: /home/{{ username }}

{% else %}
  user.absent
{% endif %}
{% endfor %}
