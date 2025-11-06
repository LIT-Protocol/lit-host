include:
  - pkgs.cron

purge_old_cache:
  cron.present:
    - name: find /var/cache/lit-core -type f -mtime +{{ pillar.lit_core_cache_file_retention }} -exec rm -f {} \;
    - user: root
    - minute: 00
    - hour: 01
    - daymonth: '*'
    - month: '*'
    - dayweek: '*'
    - require:
      - service: cron_service_running

cron_service_running:
  service.running:
    - name: cron
    - enable: True
    - require:
      - pkg: cron
