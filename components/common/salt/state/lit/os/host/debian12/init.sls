{% if grains['os'] == 'Debian' and grains['osrelease'] == '11' %}
upgrade_debian:
  test.fail_with_changes:
    - name: "Debian 11 is no longer supported, please upgrade your system by following https://www.notion.so/litprotocol/Debian-12-Node-Upgrade-Guide"
    - failhard: True
{% else %}
already_deb12:
  test.echo:
    - name: "System is Debian 12"
{% endif %}
