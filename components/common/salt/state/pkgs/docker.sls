# docker install procedure lifted from https://gist.github.com/ScriptAutomate/77775f26c6640d184b0574065ff94d64#file-docker-sls

docker-prereqs:
  pkg.installed:
    - pkgs:
      - apt-transport-https
      - ca-certificates
      - curl
      - gnupg
      - lsb-release

docker-repo:
  pkgrepo.managed:
    - humanname: Docker Official
    - name: deb [signed-by=/etc/apt/keyrings/gpg arch=amd64] https://download.docker.com/linux/debian {{ grains['oscodename'] }} stable
    - dist: {{ grains['oscodename'] }}
    - file: /etc/apt/sources.list.d/docker.list
    - key_url: https://download.docker.com/linux/debian/gpg
    - aptkey: False

docker:
  pkg.installed:
    - refresh: True
    - pkgs:
      - docker-ce
      - docker-ce-cli
      - containerd.io
    - require:
      - docker-repo
      - file: /etc/modprobe.d/disable-br-netfilter.conf # Needed to keep Guest<->Host networking avilable
