// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {CollaborativeStakingFactory} from "../src/CollaborativeStakingFactory.sol";
import {CollaborativeStaking} from "../src/CollaborativeStaking.sol";

/// @title Deployment Script for CollaborativeStakingFactory
/// @notice This script deploys the CollaborativeStakingFactory contract.
/// @dev Use this script with Foundry's `forge script` command.
///
/// ## How to Run
/// `forge script script/deployCollaborativeStakingFactory.s.sol --broadcast --rpc-url=$ETH_RPC_URL --private-key=$PRIVATE_KEY --verify -vvvvv`
///
/// Replace `<RPC_URL>` with the RPC endpoint of the network you want to deploy to.
contract DeployCollaborativeStakingFactory is Script {
    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the CollaborativeStakingFactory contract
        CollaborativeStakingFactory factory = new CollaborativeStakingFactory();

        // Log the deployed factory address
        // solhint-disable-next-line
        console.log("CollaborativeStakingFactory deployed at:", address(factory));

        // Deploy a CollaborativeStaking contract so that etherscan can verify it
        CollaborativeStaking collaborativeStaking = new CollaborativeStaking(address(0x1234), address(0x5678), 10 days);

        // Log the deployed collaborativeStaking address
        // solhint-disable-next-line
        console.log("CollaborativeStaking deployed at:", address(collaborativeStaking));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
