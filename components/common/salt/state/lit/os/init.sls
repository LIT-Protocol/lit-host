include:
  - .scripts

/opt/lit/os:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True
    - recurse: False
    - require:
        - file: /opt/lit