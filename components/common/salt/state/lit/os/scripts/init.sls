{% if pillar.get('no_checkouts', False) == False %}
include:
  - lit.os.repo
{% endif %}

# All targets
{% if pillar.get('litos_guest', False) == False or pillar.get('litos_host_type', '') == 'prov' or pillar.get('litos_guest_type', '') == 'build' %}
{% for script in [
  'common/scripts/common.sh',
  'common/scripts/salt.sh'
] %}
all_/opt/lit/os/{{ script }}:
  file:
    - copy
    - name: /opt/lit/os/{{ script }}
    - source: /opt/assets/lit-os/components/{{ script }}
    - force: True
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
{% if pillar.get('no_checkouts', False) == False %}
    - require:
        - git: lit-os
{% endif %}
{% endfor %}
{% endif %}

# Host targets
{% if pillar.get('litos_guest', False) == False %}
{% for script in [
  'host/check.sh',
  'host/update.sh',
  'guest/instance/common.sh',
  'guest/instance/create.sh',
  'guest/instance/destroy.sh',
  'guest/instance/resize.sh',
  'guest/instance/repair.sh',
  'guest/instance/launch.sh',
  'guest/instance/monitor.sh'
] %}
host_/opt/lit/os/{{ script }}:
  file:
    - copy
    - name: /opt/lit/os/{{ script }}
    - source: /opt/assets/lit-os/components/{{ script }}
    - force: True
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
{% if pillar.get('no_checkouts', False) == False %}
    - require:
        - git: lit-os
{% endif %}
{% endfor %}
{% endif %}

# Build targets
{% if pillar.get('litos_host_type', '') == 'prov' or pillar.get('litos_guest_type', '') == 'build' %}
{% for script in [
  'guest/build/build.sh'
] %}
build_/opt/lit/os/{{ script }}:
  file:
    - copy
    - name: /opt/lit/os/{{ script }}
    - source: /opt/assets/lit-os/components/{{ script }}
    - force: True
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
{% if pillar.get('no_checkouts', False) == False %}
    - require:
        - git: lit-os
{% endif %}
{% endfor %}
{% endif %}