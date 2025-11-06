include:
  - git

sev_snp_measure_repo:
  git.latest:
    - name: https://github.com/Garandor/sev-snp-measure.git
    - target: /opt/sev-snp-measure
    - rev: garandor/measure_ovmf_section_4
    - force_checkout: True
    - force_clone: True
    - force_fetch: True
    - force_reset: True

sev_snp_measure_symlink:
  file.symlink:
    - name: /usr/local/bin/sev-snp-measure
    - target: /opt/sev-snp-measure/sev-snp-measure.py
    - mode: 755
    - force: True
    - require:
      - git: sev_snp_measure_repo
