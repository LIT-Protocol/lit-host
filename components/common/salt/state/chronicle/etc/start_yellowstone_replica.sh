#!/bin/bash

docker rm -f yellowstone

mkdir -p /var/chronicle/yellowstone

docker run \
	--restart always\
	-d\
	--name yellowstone\
    -v /var/chronicle/yellowstone:/home/user/.arbitrum\
    -p 0.0.0.0:8549:8547 -p 0.0.0.0:8548:8548 offchainlabs/nitro-node:v3.0.3-3ecd01e\
    --parent-chain.connection.url="{{ pillar.chronicle_l2_rpc_url }}"\
    --execution.forwarding-target="{{ pillar.chronicle_l3_rpc_url }}"\
    --node.feed.input.url="{{ pillar.chronicle_node_feed_url }}"\
    --chain.id=175188\
    --chain.name=conduit-orbit-deployer\
    --http.api=net,web3,eth\
    --http.corsdomain=*\
    --http.addr=0.0.0.0\
    --http.vhosts=*\
    --node.data-availability.rest-aggregator.enable\
    --node.data-availability.rest-aggregator.urls="{{ pillar.chronicle_da_url }}"\
    --chain.info-json="[{\"chain-id\":175188,\"parent-chain-id\":421614,\"chain-name\":\"conduit-orbit-deployer\",\"chain-config\":{\"chainId\":175188,\"homesteadBlock\":0,\"daoForkBlock\":null,\"daoForkSupport\":true,\"eip150Block\":0,\"eip150Hash\":\"0x0000000000000000000000000000000000000000000000000000000000000000\",\"eip155Block\":0,\"eip158Block\":0,\"byzantiumBlock\":0,\"constantinopleBlock\":0,\"petersburgBlock\":0,\"istanbulBlock\":0,\"muirGlacierBlock\":0,\"berlinBlock\":0,\"londonBlock\":0,\"clique\":{\"period\":0,\"epoch\":0},\"arbitrum\":{\"EnableArbOS\":true,\"AllowDebugPrecompiles\":false,\"DataAvailabilityCommittee\":true,\"InitialArbOSVersion\":30,\"InitialChainOwner\":\"0xFE1A768C9f1061aD49fe252Ba8cC34018BaDD011\",\"GenesisBlockNum\":0}},\"rollup\":{\"bridge\":\"0x8df39376666F6E3e53f5f3c8F499564fBb706aDe\",\"inbox\":\"0x535123Ed4332D7B4d47d300496fE323942232D05\",\"sequencer-inbox\":\"0x54ce4B4c8027b2125592BFFcEE8915B675c0a526\",\"rollup\":\"0xFa5F419000992AF100E2068917506cdE17B15Cc5\",\"validator-utils\":\"0x0f6eFdBD537Bf8ae829A33FE4589634D876D9eA3\",\"validator-wallet-creator\":\"0x1ee39e82DB0023238cE9326A42873d9af4096f06\",\"deployed-at\":64358254}}]"