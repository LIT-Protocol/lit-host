include:
  - pkgs.nginx

/etc/nginx/ssl:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: nginx

{% for dir in salt.pillar.get('nginx_dirs', []) %}
{{ dir }}:
  file.directory:
    - user: www-data
    - group: www-data
    - mode: 755
    - makedirs: True
    - require:
        - pkg: nginx
{% endfor %}

/etc/nginx/nginx.conf:
  file:
    - managed
    - source: salt://http/nginx/etc/nginx/nginx.conf
    - template: jinja
    - require:
      - pkg: nginx

{% for file, cfginfo in salt.pillar.get('nginx_configs', {}).items() %}
{% if 'disabled' in cfginfo and cfginfo.disabled == True %}
/etc/nginx/sites-enabled/{{ file }}:
  file.absent:
    - require:
        - pkg: nginx
{% else %}
/etc/nginx/sites-available/{{ file }}:
  file:
    - managed
    - source: salt://{{ cfginfo.source }}
    - template: jinja
    - require:
        - pkg: nginx

/etc/nginx/sites-enabled/{{ file }}:
  file.symlink:
    - target: /etc/nginx/sites-available/{{ file }}
    - require:
        - pkg: nginx
{% endif %}
{% endfor %}

nginx_service:
{% if pillar.get('is_chroot', False) == True %}
  # service.enabled doesn't appear to work.
  cmd.run:
    - name: systemctl enable nginx.service
{% else %}
  service:
    - running
    - name: nginx
    - enable: True
    - reload: True
    - watch:
      - file: /etc/nginx/nginx.conf
{% for file, cfginfo in salt.pillar.get('nginx_configs', {}).items() %}
{% if 'disabled' not in cfginfo or cfginfo.disabled == False %}
      - file: /etc/nginx/sites-available/{{ file }}
{% endif %}
      - file: /etc/nginx/sites-enabled/{{ file }}
{% endfor %}
{% for dir in salt.pillar.get('nginx_dirs', []) %}
      - file: {{ dir }}
{% endfor %}
    - require:
      - pkg: nginx
      - file: /etc/nginx/nginx.conf
{% for file, cfginfo in salt.pillar.get('nginx_configs', {}).items() %}
{% if 'disabled' not in cfginfo or cfginfo.disabled == False %}
      - file: /etc/nginx/sites-available/{{ file }}
{% endif %}
      - file: /etc/nginx/sites-enabled/{{ file }}
{% endfor %}
{% for dir in salt.pillar.get('nginx_dirs', []) %}
      - file: {{ dir }}
{% endfor %}
{% endif %}