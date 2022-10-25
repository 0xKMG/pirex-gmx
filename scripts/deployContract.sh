#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Load environment variables
source $SCRIPT_DIR/loadEnv.sh

forge create --rpc-url $DEPLOY_RPC_URL --optimize --optimizer-runs 200 --private-key $DEPLOY_PRIVATE_KEY --use $COMPILER_VERSION "$@"
