base:
  '*':
    - defaults
  '*.litos-guest.*':
    - lit.os.guest.all
  '*-dev*.litos-guest.*':
    - lit.os.guest.env.dev
  '*-staging*.litos-guest.*':
    - lit.os.guest.env.staging
  '*-prod*.litos-guest.*':
    - lit.os.guest.env.prod
  'node-*.litos-guest.*':
    - lit.os.guest.type.node
  'prov-*.litos-guest.*':
    - lit.os.guest.type.prov
  'build-*.litos-guest.*':
    - lit.os.guest.type.build
