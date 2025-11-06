{% set add_packages = ['git', 'xz-utils', 'python-is-python3', 'rsync', 'cloud-image-utils', 'wget', 'socat', 'p7zip-full', 'libpixman-1-dev', 'time', 'gdisk', 'libxen-dev'] %}
{% for p in add_packages %}
litos_host_pkg_add_{{ p }}:
  pkg.installed:
    - name: {{ p }}
{% endfor %}

{% set rem_packages = ['resolvconf'] %}
{% for p in rem_packages %}
litos_host_pkg_rem_{{ p }}:
  pkg.removed:
    - name: {{ p }}
{% endfor %}
