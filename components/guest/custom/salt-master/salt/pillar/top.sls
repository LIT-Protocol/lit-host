base:
  '*':
    - defaults
    - lit.os.guest.type.custom
    - custom.salt-master
  '*.litos-guest.*':
    - lit.os.guest.all
  '*-dev*.litos-guest.*':
    - lit.os.guest.env.dev
  '*-staging*.litos-guest.*':
    - lit.os.guest.env.staging
  '*-prod*.litos-guest.*':
    - lit.os.guest.env.prod
