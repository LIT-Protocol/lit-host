#!/bin/bash

set -e

export INSTALL_TYPE="node"

export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export COMPONENT_DIR=$(readlink -f "$SCRIPT_DIR/../../components")
export COMMON_BASE_DIR=$(readlink -f "$COMPONENT_DIR/common")
export COMMON_SCRIPT_DIR=$(readlink -f "$COMMON_BASE_DIR/scripts")

. $COMMON_SCRIPT_DIR/common.sh
. $COMMON_SCRIPT_DIR/salt.sh
. $COMMON_SCRIPT_DIR/install.sh