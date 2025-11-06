{% set req_pkgs = ['certbot', 'python3-certbot-nginx'] %}

{% for pkg in req_pkgs %}
{{ pkg }}:
  pkg:
    - installed
{% endfor %}

