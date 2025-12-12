# Check for required keys.
{% set required_keys = [
    'logging_gcp_project_id',
    'logging_gcp_creds'
] %}
{% set ns = namespace(all_keys_present=True) %}
{% for key in required_keys %}
  {% if key not in pillar %}
    {% set ns.all_keys_present = False %}
  {% endif %}
{% endfor %}

{% if ns.all_keys_present %}

print_otelcol_notification:
  test.show_notification:
    - text: " "
    - name: "All required keys are present in secrets.sls. Installing OTEL Collector."

/var/monitoring/otelcol/file_storage:
  file.directory:
    - makedirs: True
    - mode: 0777

/etc/monitoring/otelcol:
  file.directory:
    - makedirs: True
    - mode: 0644

# We want to create the docker compose file but NOT manage / overwrite it via Salt, as it will be updated by
# create.sh whenever the guests are created.
/etc/monitoring/otelcol/docker-compose.yml:
  file.managed:
    - source: salt://monitoring/otelcol/etc/docker-compose.yml
    - mode: 0644
    - makedirs: True
    - replace: True

/etc/monitoring/otelcol/otel-collector-config.yaml:
  file.managed:
    - source: salt://monitoring/otelcol/etc/otel-collector-config.yaml.j2
    - template: jinja
    - mode: 0644
    - makedirs: True

gcp_service_account_key:
  file.managed:
    - name: /etc/monitoring/otelcol/service-account-key.json
    - source: salt://monitoring/otelcol/etc/service-account-key.json.j2
    - template: jinja
    - user: root
    - group: root
    - mode: "0644"
    - makedirs: False

# Copy the existing service file to the correct location
/etc/systemd/system/otelcol.service:
  file.managed:
    - source: salt://monitoring/otelcol/etc/systemd/system/otelcol.service
    - mode: 0644
    - require:
      - file: /etc/monitoring/otelcol/docker-compose.yml
      - file: /etc/monitoring/otelcol/otel-collector-config.yaml
      - file: /etc/monitoring/otelcol/service-account-key.json
      - sls: network
      - sls: docker

# Pull the latest otelcol docker image using cmd.run,
# 'docker.pulled' isn't supported by salt older version
pull_otelcol_image_cmd:
  cmd.run:
    - name: docker pull litptcl/otelcontribcol:e0f8435d042015d1ed56bb8f11974b32b26c2867
    - require:
      - sls: docker

# Enable the otelcol service
enable_otelcol_service:
  service.enabled:
    - name: otelcol
    - require:
      - file: /etc/systemd/system/otelcol.service
      - cmd: pull_otelcol_image_cmd

# Start the otelcol service
start_otelcol_service:
  service.running:
    - name: otelcol
    - watch:
      - file: /etc/systemd/system/otelcol.service
    - require:
      - service: enable_otelcol_service

# Script to wait until the OTEL Collector Healthcheck Endpoint returns fine.
{% set service_name = 'otel-collector' %}
{% set check_url = 'http://127.0.0.1:13133' %}
{% set max_attempts = 5 %}
{% set delay_seconds = 10 %}
wait_otelcol_up:
  cmd.wait:
    - name: |
        for i in $(seq 1 {{ max_attempts }}); do
          if curl -s {{ check_url }} | grep -q "Server available"; then
            echo "OTEL Collector service is available."
            exit 0
          else
            echo "OTEL Collector service not available, attempt $i to check its health."
            sleep {{ delay_seconds }}
          fi
        done
        echo "OTEL Collector service failed to start after {{ max_attempts }} attempts"
        exit 1
    - require:
      - service: start_otelcol_service
    - watch:
      - file: /etc/systemd/system/otelcol.service

{% else %}

print_otelcol_notification:
  test.show_notification:
    - text: " "
    - name: "Missing required keys in secrets.sls. Not installing OTEL Collector."

{% endif %}
