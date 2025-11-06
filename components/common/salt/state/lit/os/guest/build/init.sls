{% set packages = ['gdisk', 'cryptsetup', 'dosfstools', 'uuid'] %}
{% for p in packages %}
litos_guest_build_pkg_{{ p }}:
  pkg.installed:
    - name: {{ p }}
{% endfor %}

/var/lit/os/guest/build/images:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - file_mode: 644
    - makedirs: True

/var/lit/os/guest/build/images/{{ pillar['litos_guest_ref_img'] }}:
  file:
    - managed
    - user: root
    - group: root
    - source: {{ pillar.litos_guest_ref_img_url }}
    - source_hash: {{ pillar.litos_guest_ref_img_hash_url }}
    - source_hash_name: {{ pillar.litos_guest_ref_img_hash_name }}
    - require:
      - file: /var/lit/os/guest/build/images

/var/lit/os/guest/build/.env:
  file:
    - managed
    - user: root
    - group: root
    - contents:
      - LITOS_GUEST_REF_IMG_DIR="/var/lit/os/guest/build/images"
      - LITOS_GUEST_REF_IMG_NAME="{{ pillar.litos_guest_ref_img }}"
    - require:
      - file: /var/lit/os/guest/build/images/{{ pillar.litos_guest_ref_img }}

