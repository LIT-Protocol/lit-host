include:
  - pkgs.git
  - git

{% set repo_name = 'lit-os' %}
{% set repo = pillar.git_repo[repo_name] %}
{% set repo_branches = repo.branch %}

{{ repo_name }}:
  git.latest:
    - name: {{ repo.url }}
    - rev: {% if pillar.env in repo_branches %}{{ repo_branches[pillar.env] }}{% else %}{{ repo_branches['default'] }}{% endif %}
    - user: git
    - target: /opt/assets/{{ repo_name }}
    - identity: /home/git/.ssh/id_git_{{ repo_name }}
    - force_fetch: True
    - force_reset: True
    - require:
        - pkg: git
        - file: /opt/assets
        - ssh_known_hosts: github.com