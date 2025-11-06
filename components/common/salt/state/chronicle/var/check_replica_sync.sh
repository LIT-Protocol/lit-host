#!/bin/bash

MAX_BLOCK_DIFFERENCE=10

echo "Starting Health Check for Yellowstone Replica..."

# Getting the highest block from the sequencer
echo "Fetching highest block from the sequencer..."
highestBlockFromSequencer=$(curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' https://yellowstone-rpc.litprotocol.com | jq -r '.result.number' | sed 's/0x//')
if [ -z "$highestBlockFromSequencer" ]; then
    echo "ERROR: Failed to get sequencer block height"
    exit 1
fi

highestBlockFromSequencer=$((16#$highestBlockFromSequencer))
echo "Sequencer block height: $highestBlockFromSequencer"

# Getting the current synced block from the local node
echo "Fetching current synced block from local node..."
currentSyncedBlock=$(curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' http://localhost:8547 | jq -r '.result.number' | sed 's/0x//')
if [ -z "$currentSyncedBlock" ]; then
    echo "ERROR: Failed to get local node block height"
    exit 1
fi

currentSyncedBlock=$((16#$currentSyncedBlock))
echo "Local node block height: $currentSyncedBlock"

# Checking block difference
blockDifference=$((highestBlockFromSequencer - currentSyncedBlock))
echo "Block difference: $blockDifference (max allowed: $MAX_BLOCK_DIFFERENCE)"

if [ $blockDifference -gt $MAX_BLOCK_DIFFERENCE ]; then
    echo "Unhealthy: Local replica out of sync by $blockDifference blocks"
    exit 1
else
    echo "Healthy: Local replica is up to date"
    exit 0
fi
