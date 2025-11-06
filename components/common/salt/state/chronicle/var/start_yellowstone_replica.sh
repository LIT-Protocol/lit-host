#!/bin/bash
# Script to manage Yellowstone replica container startup, iptables, and seeding.
# Handles: snapshotting, container setup, data cleaning, iptables init, seeding.
# Assumes it's run as root (for docker and iptables).

set -e

# === Configuration ===
CONTAINER_NAME="yellowstone"
DATA_DIR="/var/chronicle/yellowstone"
TORRENT_FILE="archive.torrent"
TORRENT_PATH="$DATA_DIR/$TORRENT_FILE"
HEALTHCHECK_SCRIPT_HOST_PATH="/var/chronicle/check_replica_sync.sh"
HEALTHCHECK_SCRIPT_CONT_PATH="/usr/local/bin/check_replica_sync.sh"
ARCHIVE_NAME="" # Determined dynamically from torrent file

# iptables config
IPTABLES_CHAIN="YELLOWSTONE_ACCESS"
RPC_PORT="8547"
WS_PORT="8548"

# Seeding config
SEEDING_PID_DIR="/var/run/chronicle"
SEEDING_LOG_FILE="/var/log/yellowstone_seeding.log"
LOCK_FILE="$SEEDING_PID_DIR/aria2c-yellowstone.lock"
PID_FILE="$SEEDING_PID_DIR/aria2c-yellowstone.pid"

# Resource Limits (IMPORTANT: Monitor and adjust!)
MEMORY_LIMIT="24g"
CPU_LIMIT="8.0"

# Healthcheck settings
HEALTH_INTERVAL="1m"
HEALTH_TIMEOUT="10s"
HEALTH_RETRIES="2"

# Pillar values (to be replaced by Salt)
PILLAR_CHRONICLE_L2_RPC_URL="{{ pillar.chronicle_l2_rpc_url }}"
PILLAR_CHRONICLE_L3_RPC_URL="{{ pillar.chronicle_l3_rpc_url }}"
PILLAR_CHRONICLE_NODE_FEED_URL="{{ pillar.chronicle_node_feed_url }}"
PILLAR_CHRONICLE_DA_URL="{{ pillar.chronicle_da_url }}"

# === Helper Functions ===

# Function to log errors and exit
exit_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        exit_error "Required command not found: '$1'"
    fi
}

echo "=== Starting Yellowstone Replica Setup ==="

# --- Sanity Checks ---
echo "[1/7] Performing Sanity Checks..."
check_command "iptables"
check_command "docker"
check_command "aria2c"
if [ ! -f "$HEALTHCHECK_SCRIPT_HOST_PATH" ]; then
    exit_error "Healthcheck script not found: $HEALTHCHECK_SCRIPT_HOST_PATH"
fi
echo "Checks passed."

# --- Snapshot Handling ---
echo "[2/7] Handling Snapshot..."
if [ ! -f "$TORRENT_PATH" ]; then
    exit_error "Torrent file not found: $TORRENT_PATH"
fi

# Determine archive name from torrent metadata
echo "Determining archive name from torrent..."
ARCHIVE_NAME=$(aria2c -S "$TORRENT_PATH" 2>/dev/null | grep 'Name:' | head -n 1 | cut -d' ' -f2-)
if [ -z "$ARCHIVE_NAME" ]; then
    exit_error "Could not determine archive name from torrent: $TORRENT_PATH"
fi
SNAPSHOT_PATH="$DATA_DIR/$ARCHIVE_NAME"
echo "Expecting snapshot file: $SNAPSHOT_PATH"

# Download snapshot if it doesn't exist
if [ ! -f "$SNAPSHOT_PATH" ]; then
    echo "Snapshot file '$SNAPSHOT_PATH' not found. Downloading using torrent: $TORRENT_PATH..."
    aria2c --seed-time=0 \
           --allow-overwrite=true \
           --file-allocation=none \
           -d "$DATA_DIR" \
           "$TORRENT_PATH"
    if [ $? -ne 0 ]; then exit_error "Snapshot download failed."; fi
    echo "Snapshot download completed."
else
    echo "Snapshot file already exists: $SNAPSHOT_PATH"
fi
echo "Snapshot file verified."

# --- Container Cleanup ---
echo "[3/7] Cleaning Up Existing Container..."
echo "Stopping and removing any existing '$CONTAINER_NAME' container..."
docker stop --timeout=300 "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
echo "Existing container removed."

# --- Clean Data Directory (Preserve Snapshot/Torrent) ---
echo "[4/7] Cleaning Data Directory..."
if [ -d "$DATA_DIR" ]; then
    echo "Cleaning existing data directory '$DATA_DIR' (preserving snapshot/torrent)..."
    if find "$DATA_DIR" -mindepth 1 ! -name "$TORRENT_FILE" ! -name "$ARCHIVE_NAME" -delete; then
        # find succeeded (or found nothing to delete)
        echo "Data directory cleanup completed successfully."
    else
        # find failed
        find_exit_code=$?
        echo "Warning: 'find ... -delete' command in $DATA_DIR finished with a non-zero exit status ($find_exit_code)."
    fi
    echo "Data directory cleaned."
else
    echo "Data directory '$DATA_DIR' does not exist. Creating..."
    if ! mkdir -p "$DATA_DIR"; then
        # If mkdir fails, exit_error will be called, providing a custom message.
        # set -e would also cause an exit here if this explicit check wasn't present.
        exit_error "Failed to create data directory '$DATA_DIR'."
    fi
    echo "Data directory created."
fi

# --- iptables Chain Setup & Initial Block ---
# Note: Jump rules linking INPUT to this chain are managed by SaltStack "rules.sls".
# Here, we ensure the chain exists and sets the initial REJECT rule.
echo "[5/7] Setting Up Iptables Chain and Initial Rule..."

# Create the dedicated chain idempotently
echo "Ensuring iptables chain '$IPTABLES_CHAIN' exists..."
if ! iptables -N "$IPTABLES_CHAIN" 2>/dev/null; then
    # Check if the error was simply that the chain already exists (exit code 1 for -N)
    if ! iptables -L "$IPTABLES_CHAIN" >/dev/null 2>&1; then
        exit_error "Failed to create iptables chain '$IPTABLES_CHAIN' and it doesn't exist."
    else
        echo "iptables chain '$IPTABLES_CHAIN' already exists."
    fi
else
    echo "iptables chain '$IPTABLES_CHAIN' created."
fi

# Set initial state to REJECT traffic by default
echo "Setting initial policy to REJECT for $IPTABLES_CHAIN..."
iptables -F "$IPTABLES_CHAIN" # Flush existing rules in our chain
if [ $? -ne 0 ]; then exit_error "Failed to flush iptables chain '$IPTABLES_CHAIN'."; fi

iptables -A "$IPTABLES_CHAIN" -j REJECT --reject-with icmp-port-unreachable # Add default REJECT rule
if [ $? -ne 0 ]; then exit_error "Failed to add initial REJECT rule to chain '$IPTABLES_CHAIN'."; fi

# Verify the REJECT rule is in place
echo "Verifying initial REJECT rule..."
if ! iptables -C "$IPTABLES_CHAIN" -j REJECT --reject-with icmp-port-unreachable 2>/dev/null; then
    exit_error "Failed to verify initial REJECT rule in chain '$IPTABLES_CHAIN'. iptables setup failed."
fi
echo "Initial REJECT rule verified."
echo "iptables chain $IPTABLES_CHAIN created and initial REJECT rule set."

# --- Start Container ---
echo "[6/7] Starting '$CONTAINER_NAME' Container..."
# Note: Ports are published here but access is controlled by iptables that are already set up
docker run \
    --restart no \
    -d \
    --name "$CONTAINER_NAME" \
    -v "$DATA_DIR:/home/user/.arbitrum" \
    -v "$HEALTHCHECK_SCRIPT_HOST_PATH:$HEALTHCHECK_SCRIPT_CONT_PATH" \
    --health-cmd="$HEALTHCHECK_SCRIPT_CONT_PATH" \
    --health-interval="$HEALTH_INTERVAL" \
    --health-timeout="$HEALTH_TIMEOUT" \
    --health-retries="$HEALTH_RETRIES" \
    -p "0.0.0.0:$RPC_PORT:$RPC_PORT" \
    -p "0.0.0.0:$WS_PORT:$WS_PORT" \
    --memory="$MEMORY_LIMIT" \
    --cpus="$CPU_LIMIT" \
    offchainlabs/nitro-node:v3.7.4-9244576 \
    --parent-chain.connection.url="$PILLAR_CHRONICLE_L2_RPC_URL" \
    --execution.forwarding-target="$PILLAR_CHRONICLE_L3_RPC_URL" \
    --node.feed.input.url="$PILLAR_CHRONICLE_NODE_FEED_URL" \
    --chain.id=175188 \
    --chain.name=conduit-orbit-deployer \
    --http.api=net,web3,eth --http.corsdomain=* --http.addr=0.0.0.0 --http.vhosts=* \
    --init.url="file:///home/user/.arbitrum/$ARCHIVE_NAME" \
    --node.data-availability.rest-aggregator.enable \
    --node.data-availability.rest-aggregator.urls="$PILLAR_CHRONICLE_DA_URL" \
    --chain.info-json='[{"chain-id":175188,"parent-chain-id":421614,"chain-name":"conduit-orbit-deployer","chain-config":{"chainId":175188,"homesteadBlock":0,"daoForkBlock":null,"daoForkSupport":true,"eip150Block":0,"eip150Hash":"0x0000000000000000000000000000000000000000000000000000000000000000","eip155Block":0,"eip158Block":0,"byzantiumBlock":0,"constantinopleBlock":0,"petersburgBlock":0,"istanbulBlock":0,"muirGlacierBlock":0,"berlinBlock":0,"londonBlock":0,"clique":{"period":0,"epoch":0},"arbitrum":{"EnableArbOS":true,"AllowDebugPrecompiles":false,"DataAvailabilityCommittee":true,"InitialArbOSVersion":30,"InitialChainOwner":"0xFE1A768C9f1061aD49fe252Ba8cC34018BaDD011","GenesisBlockNum":0}},"rollup":{"bridge":"0x8df39376666F6E3e53f5f3c8F499564fBb706aDe","inbox":"0x535123Ed4332D7B4d47d300496fE323942232D05","sequencer-inbox":"0x54ce4B4c8027b2125592BFFcEE8915B675c0a526","rollup":"0xFa5F419000992AF100E2068917506cdE17B15Cc5","validator-utils":"0x0f6eFdBD537Bf8ae829A33FE4589634D876D9eA3","validator-wallet-creator":"0x1ee39e82DB0023238cE9326A42873d9af4096f06","deployed-at":64358254}}]'

# Verify container is running
echo "Waiting briefly for container process..."
sleep 3
if ! docker ps -q --filter name="^${CONTAINER_NAME}$" | grep -q .; then
    echo "ERROR: Container '$CONTAINER_NAME' process not found after start attempt. Check docker logs:" >&2
    docker logs --tail 50 "$CONTAINER_NAME" 2>/dev/null || true # Show recent logs if possible
    exit 1
fi
echo "'$CONTAINER_NAME' container process is running."

# --- Seeding Process Setup ---
echo "[7/7] Setting Up Background Seeding Process..."
mkdir -p "$SEEDING_PID_DIR"

echo "Checking state of PID file ($PID_FILE) and lock file ($LOCK_FILE)..."

# Check if a PID file exists and if the process is still running
PROCESS_ALREADY_RUNNING=false
if [ -f "$PID_FILE" ]; then
    STORED_PID=$(cat "$PID_FILE")
    if [ -n "$STORED_PID" ] && kill -0 "$STORED_PID" 2>/dev/null; then
        # Process is still running, setting flag
        echo "Existing aria2c process (PID: $STORED_PID) is still running. Skipping start."
        PROCESS_ALREADY_RUNNING=true
    else
        # Process is not running, assume lock file is stale
        echo "PID file ($PID_FILE) found, but process $STORED_PID is not running. Cleaning up stale lock and PID files."
        rm -f "$LOCK_FILE" "$PID_FILE"
    fi
else
    # No PID file, checking if lock file exists anyway (might be from a very old crash)
    if [ -f "$LOCK_FILE" ]; then
        echo "No PID file found, but lock file ($LOCK_FILE) exists. Assuming stale and removing."
        rm -f "$LOCK_FILE"
    fi
fi

if [ "$PROCESS_ALREADY_RUNNING" = false ]; then
    echo "Proceeding to acquire lock and start aria2c..."
    (
        # Using flock for mutual exclusion
        echo "Attempting to acquire lock: $LOCK_FILE"
        if ! flock -n 9; then
            echo "FAILED to acquire lock ($LOCK_FILE) even after checking PID. Another instance likely just started or lock is unexpectedly held. Skipping aria2c start." >&2
            exit 1
        fi
        echo "Successfully acquired lock: $LOCK_FILE"

        # Starting seeding process using nohup
        echo "Starting new aria2c seeding process in background using nohup..."
        nohup aria2c --seed-ratio=0.0 --max-upload-limit=15000K --allow-overwrite=true -d "$DATA_DIR" \
               --save-session="$SEEDING_PID_DIR/aria2c-yellowstone.session" --save-session-interval=60 \
               --daemon=false --enable-rpc=false \
               --log="$SEEDING_LOG_FILE" --log-level=info \
               "$TORRENT_PATH" > /dev/null 2>&1 &
        SEEDING_PID=$!
        echo "Background process launched with tentative PID: $SEEDING_PID"

        sleep 2
        if kill -0 $SEEDING_PID 2>/dev/null; then
            echo $SEEDING_PID > "$PID_FILE"
            echo "Confirmed aria2c seeding started with PID: $SEEDING_PID. Logs in $SEEDING_LOG_FILE"
        else
            echo "ERROR: Failed to confirm aria2c process (PID: $SEEDING_PID) started correctly or it exited quickly. Check $SEEDING_LOG_FILE for aria2c errors." >&2
            rm -f "$PID_FILE" "$LOCK_FILE"
            exit 1
        fi

    ) 9>"$LOCK_FILE"

    # Checking the exit code of the subshell
    SUBSHELL_EXIT_CODE=$?
    if [ $SUBSHELL_EXIT_CODE -ne 0 ]; then
        echo "Warning: Subshell for aria2c start exited with code $SUBSHELL_EXIT_CODE." >&2
    fi
fi

echo "===================================================="
echo "Yellowstone replica setup/recreation complete."
echo "Container '$CONTAINER_NAME' is running."
echo "Resource Limits: Memory=$MEMORY_LIMIT, CPUs=$CPU_LIMIT (Monitor!)"
echo "Health Check: Interval=$HEALTH_INTERVAL, Timeout=$HEALTH_TIMEOUT, Retries=$HEALTH_RETRIES"
echo "Access state (ACCEPT/REJECT) for iptables chain '$IPTABLES_CHAIN' is managed dynamically by the lit-node-operator daemon."
echo ""
echo "Current relevant iptables rules:"
echo "--- Chain $IPTABLES_CHAIN ---"
iptables -L "$IPTABLES_CHAIN" -n -v || echo "(Failed to list $IPTABLES_CHAIN rules)"
echo "--- Chain INPUT (showing jumps to $IPTABLES_CHAIN) ---"
iptables -L INPUT -n -v --line-numbers | grep "$IPTABLES_CHAIN" || echo "(No jumps found in INPUT to $IPTABLES_CHAIN)"
echo "===================================================="

exit 0
