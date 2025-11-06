{% if grains['os'] in ['Debian'] %}
{% else %}
unsupported_os:
  test.fail_without_changes:
    - name: "OS not supported! Debian Linux only!"
    - failhard: True
{% endif %}
