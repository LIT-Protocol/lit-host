{% for group, groupinfo in salt['pillar.get']('groups', {}).items() %}
{{ group }}:
{% if groupinfo['active'] == True %}
  group.present:
    - gid: {{ groupinfo['gid'] }}
{% else %}
  group.absent
{% endif %}
{% endfor %}
