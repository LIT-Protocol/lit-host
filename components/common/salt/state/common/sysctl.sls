fs.protected_hardlinks:
  sysctl.present:
    - value: 1

fs.protected_symlinks:
  sysctl.present:
    - value: 1

{% for line in ['fs.protected_hardlinks', 'fs.protected_symlinks'] %}
/etc/sysctl.conf_rm_{{ line }}:
  file.comment:
    - name: /etc/sysctl.conf
    - regex: ^{{ line }}
    - ignore_missing: True
{% endfor %}