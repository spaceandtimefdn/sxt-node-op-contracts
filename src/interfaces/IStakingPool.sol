// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IStakingPool
/// @notice Interface for the StakingPool contract that will hold SXT tokens.
interface IStakingPool {
    /*  ********** events ********** */

    /// @notice Emitted when the staking token is set
    /// @param token The new staking token
    /// @dev this event is emitted only by the constructor
    event StakingTokenSet(address token);

    /// @notice Emitted when the staking contract is added
    /// @param stakingContractAddress The new staking contract address
    event StakingContractAdded(address stakingContractAddress);

    /// @notice Emitted when the staking contract is removed
    /// @param stakingContractAddress The staking contract address to remove
    event StakingContractRemoved(address stakingContractAddress);

    /// @notice Emitted when tokens are withdrawn from the staking pool
    /// @param amount The amount of tokens withdrawn
    /// @param staker The address to receive the tokens
    /// @param sender The address that initiated the withdrawal
    event AmountWithdrawn(uint248 amount, address staker, address sender);

    /*  ********** functions ********** */

    /// @notice Add a staking contract
    /// @param stakingContractAddress The staking contract address to add
    function addStakingContract(address stakingContractAddress) external;

    /// @notice Remove a staking contract
    /// @param stakingContractAddress The staking contract address to remove
    function removeStakingContract(address stakingContractAddress) external;

    /// @notice Withdraw tokens from the staking pool and send directly to staker
    /// @param staker The address to receive the tokens
    /// @param amount The amount of tokens to withdraw
    /// @dev can only be called by the staking contract
    /// @custom:events
    /// * Withdraw
    function withdraw(address staker, uint248 amount) external;
}
