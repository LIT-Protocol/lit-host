# The settings in here are used in the various systemd unit configuration files (eg. lit-actions.service or lit-node.service) and should be set accordingly for each binary/service.
logging:
    default:
        dev:
            level: debug,rocket=warn,rustls=warn,reqwest=warn,hyper=error,h2=warn,lit_node=trace,lit-attestation=trace,lit_prov_api=trace,lit_os_prov_api=trace,lit_os_guest_initrd=trace,tower=warn,lit_blockchain=trace,isahc=warn,lit_observability::channels=trace
        staging:
            # TODO: Make warn
            level: debug,rocket=warn,rustls=warn,reqwest=warn,hyper=warn,h2=warn,lit_node=trace,lit_prov_api=trace,lit_os_prov_api=trace,lit_os_guest_initrd=trace,tower=warn,lit_blockchain=trace,isahc=warn,lit_observability::channels=trace
        prod:
            # TODO: Make warn
            level: debug,rocket=warn,rustls=warn,reqwest=warn,hyper=warn,h2=warn,lit_node=trace,lit_prov_api=trace,lit_os_prov_api=trace,lit_os_guest_initrd=trace,tower=warn,lit_blockchain=trace,isahc=warn,lit_observability::channels=trace
    lit-attestation-service:
        dev:
            level: debug,lit-attestation-service=trace,rocket=warn,rustls=warn,reqwest=warn,hyper=error,h2=warn,tower=warn,lit_blockchain=trace,isahc=warn,lit_observability::channels=trace
        staging:
            level: debug,lit-attestation-service=debug,rocket=warn,rustls=warn,reqwest=warn,hyper=error,h2=warn,tower=warn,lit_blockchain=trace,isahc=warn,lit_observability::channels=trace
        prod:
            level: debug,lit-attestation-service=debug,rocket=warn,rustls=warn,reqwest=warn,hyper=error,h2=warn,tower=warn,lit_blockchain=trace,isahc=warn,lit_observability::channels=trace
    lit-actions:
        dev:
            level: debug,lit-actions=trace,rocket=warn,rustls=warn,reqwest=warn,hyper=error,h2=warn,tower=warn,lit_blockchain=trace,isahc=warn,lit_observability::channels=trace
        staging:
            level: debug,lit-actions=trace,rocket=warn,rustls=warn,reqwest=warn,hyper=error,h2=warn,tower=warn,lit_blockchain=trace,isahc=warn,lit_observability::channels=trace
        prod:
            level: debug,lit-actions=trace,rocket=warn,rustls=warn,reqwest=warn,hyper=error,h2=warn,tower=warn,lit_blockchain=trace,isahc=warn,lit_observability::channels=trace
    #lit-node:
    #lit-prov-api:
    #lit-node-operator: