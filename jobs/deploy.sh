#!/bin/bash
source .env

# check required environment variables
required_env_vars=("ETH_RPC_URL" "ETHERSCAN_API_KEY" "PRIVATE_KEY")
for var in "${required_env_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "$var is not set"
        exit 1
    fi
done

if forge clean && forge build && forge script script/deploy.s.sol --broadcast --rpc-url=$ETH_RPC_URL --private-key=$PRIVATE_KEY --verify -vvvvv; then
    echo "Deployment successful!"
else
    echo "Deployment failed!"
fi
