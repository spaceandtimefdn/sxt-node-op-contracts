// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CollaborativeStaking} from "./CollaborativeStaking.sol";

/// @title Collaborative Staking Factory Contract
/// @notice This contract allows the deployment of CollaborativeStaking contracts.
contract CollaborativeStakingFactory {
    /// @notice Emitted when a new CollaborativeStaking contract is deployed.
    /// @param deployedAddress The address of the deployed contract.
    /// @param deployer The address of the deployer.
    event CollaborativeStakingDeployed(address indexed deployedAddress, address indexed deployer);

    /// @notice Deploys a new instance of the CollaborativeStaking contract.
    /// @param tokenAddress The address of the ERC20 token used for staking.
    /// @param stakingAddress The address of the staking contract.
    /// @param timelockDelay The timelock delay for staking operations.
    /// @return deployedAddress The address of the newly deployed staking contract.
    function deployCollaborativeStaking(address tokenAddress, address stakingAddress, uint256 timelockDelay)
        external
        returns (address deployedAddress)
    {
        CollaborativeStaking staking = new CollaborativeStaking(tokenAddress, stakingAddress, timelockDelay);
        deployedAddress = address(staking);

        emit CollaborativeStakingDeployed(deployedAddress, msg.sender);

        // Assign the ADMIN_ROLE to the deployer (msg.sender)
        staking.grantRole(staking.DEFAULT_ADMIN_ROLE(), msg.sender);

        // Revoke the ADMIN_ROLE from the factory
        staking.revokeRole(staking.DEFAULT_ADMIN_ROLE(), address(this));

        assert(
            staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), msg.sender)
                && !staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), address(this))
        );
    }

    /// @notice Deploys a new instance of the CollaborativeStaking contract with default settings.
    /// @param tokenAddress The address of the ERC20 token used for staking.
    /// @param stakingAddress The address of the staking contract.
    /// @param funder The address to be assigned the FUNDER_ROLE and STAKER_ROLE.
    /// @param beneficiary The address to be assigned all roles (FUNDER_ROLE, STAKER_ROLE, and BENEFICIARY_ROLE).
    /// @return deployedAddress The address of the newly deployed staking contract.
    function deployCollaborativeStakingWithDefaults(
        address tokenAddress,
        address stakingAddress,
        address funder,
        address beneficiary
    ) external returns (address deployedAddress) {
        CollaborativeStaking staking = new CollaborativeStaking(tokenAddress, stakingAddress, 10 days);
        deployedAddress = address(staking);

        emit CollaborativeStakingDeployed(deployedAddress, msg.sender);

        // Assign roles
        staking.grantRole(staking.FUNDER_ROLE(), funder);
        staking.grantRole(staking.STAKER_ROLE(), funder);
        staking.grantRole(staking.FUNDER_ROLE(), beneficiary);
        staking.grantRole(staking.STAKER_ROLE(), beneficiary);
        staking.grantRole(staking.BENEFICIARY_ROLE(), beneficiary);

        // Revoke the ADMIN_ROLE from the factory
        staking.revokeRole(staking.DEFAULT_ADMIN_ROLE(), address(this));

        assert(
            staking.hasRole(staking.FUNDER_ROLE(), funder) && staking.hasRole(staking.STAKER_ROLE(), funder)
                && staking.hasRole(staking.FUNDER_ROLE(), beneficiary)
                && staking.hasRole(staking.STAKER_ROLE(), beneficiary)
                && staking.hasRole(staking.BENEFICIARY_ROLE(), beneficiary)
                && !staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), address(this))
        );
    }
}
