include:
  - pkgs.logrotate

{% set add_packages = ['bc', 'aria2', 'jq'] %}
{% for p in add_packages %}
litos_host_pkg_add_{{ p }}:
  pkg.installed:
    - name: {{ p }}
{% endfor %}
{% set required_keys = [
    'chronicle_l2_rpc_url',
    'chronicle_l3_rpc_url',
    'chronicle_node_feed_url',
    'chronicle_da_url',
] %}
{% set ns = namespace(all_keys_present=True) %}
{% for key in required_keys %}
  {% if key not in pillar %}
    {% set ns.all_keys_present = False %}
  {% endif %}
{% endfor %}

# NOTE: Chronicle Replica only runs on 'node' type hosts (not prov) and not in production by default.
#       You can override by setting `enable_chronicle_replica: True` in pillar (defaults.sls).
{% set replica_enabled = pillar.get('enable_chronicle_replica', host_type == 'node' and pillar.get('env') != 'prod') %}

{% if ns.all_keys_present and replica_enabled %}
print_notification:
  test.show_notification:
    - text: " "
    - name: "All Chronicle keys are present in secrets.sls. Installing Chronicle Replica"

# Noticed this Salt bug - Surgically removing the problematic directory, but ONLY IF it exists.
conditional_cleanup_of_healthcheck_dir:
  cmd.run:
    - name: 'rm -rf /var/chronicle/check_replica_sync.sh'
    - onlyif: 'test -d /var/chronicle/check_replica_sync.sh'

chronicle_base_directory:
  file.directory:
    - name: /var/chronicle
    - mode: '0755'
    - makedirs: True
    - require:
      - cmd: conditional_cleanup_of_healthcheck_dir

chronicle_yellowstone_data_directory:
  file.directory:
    - name: /var/chronicle/yellowstone
    - mode: '0777'
    - makedirs: True
    - require:
      - file: chronicle_base_directory

yellowstone_seeding_logrotate_config:
  file.managed:
    - name: /etc/logrotate.d/yellowstone-seeding
    - mode: '0644'
    - user: root
    - group: root
    - contents: |
        /var/log/yellowstone_seeding.log {
          size 1G
          rotate 7
          missingok
          notifempty
          compress
          copytruncate
          dateext
          dateformat -%Y%m%d
        }
    - require:
      - pkg: logrotate

chronicle_start_script:
  file.managed:
    - name: /var/chronicle/start_yellowstone_replica.sh
    - source: salt://chronicle/var/start_yellowstone_replica.sh
    - mode: '0755'
    - template: jinja
    - makedirs: False
    - require:
      - file: chronicle_base_directory

chronicle_healthcheck_script:
  file.managed:
    - name: /var/chronicle/check_replica_sync.sh
    - source: salt://chronicle/var/check_replica_sync.sh
    - mode: '0755'
    - makedirs: False
    - require:
      - file: chronicle_base_directory
      - cmd: conditional_cleanup_of_healthcheck_dir

chronicle_torrent_file:
  file.managed:
    - name: /var/chronicle/yellowstone/archive.torrent
    - source: salt://chronicle/var/archive.torrent
    - mode: '0644'
    - makedirs: False
    - replace: True
    - require:
      - file: chronicle_yellowstone_data_directory

install_chronicle:
  cmd.run:
    - name: >
        /var/chronicle/start_yellowstone_replica.sh > /var/log/start_chronicle.log 2>&1
    - require:
      - file: chronicle_yellowstone_data_directory
      - file: chronicle_start_script
      - file: chronicle_healthcheck_script
      - file: chronicle_torrent_file
      - pkg: litos_host_pkg_add_bc
      - pkg: litos_host_pkg_add_aria2
      - pkg: litos_host_pkg_add_jq
      - sls: network
      - sls: docker

{% else %}
print_notification:
  test.show_notification:
    - text: " "
    - name: "Chronicle keys missing in secrets.sls OR host type is 'prov' OR replica explicitly disabled. Not installing Chronicle Replica!"

{% endif %}
