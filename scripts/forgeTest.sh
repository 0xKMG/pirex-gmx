#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Load environment variables
source $SCRIPT_DIR/loadEnv.sh

forge snapshot --fork-url $FORK_URL --fork-block-number $FORK_BLOCK_NUMBER "$@" >/dev/null && \
forge test --fork-url $FORK_URL --fork-block-number $FORK_BLOCK_NUMBER "$@"
