// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IStaking {
    // ** enum ** //
    /// @notice The state of a staker in the state machine
    enum StakerState {
        Unstaked, // Initial state, not staked
        Staked, // Tokens staked
        UnstakeInitiated, // Unstake process has been initiated
        UnstakeClaimed // Unstake claimed and ready for fulfillment

    }

    // ** events ** //
    /// @notice Emitted when the staking token is set
    /// @param token The new staking token
    /// @dev this event is emitted only by the constructor
    event StakingTokenSet(address token);

    /// @notice Emitted when the staking pool is set
    /// @param stakingPool The new staking pool
    /// @dev this event is emitted only by the constructor
    event StakingPoolSet(address stakingPool);

    /// @notice Emitted when the unstaking unbonding period is set
    /// @param unstakingUnbondingPeriod The new unstaking unbonding period
    /// @dev this event is emitted only by the constructor
    event UnstakingUnbondingPeriodSet(uint64 unstakingUnbondingPeriod);

    /// @notice Emitted when a user stakes tokens for a set of nodes
    /// @param staker The address of the user who staked the tokens
    /// @param amount The amount of tokens staked
    event Staked(address staker, uint248 amount);

    /// @notice Emitted when a user nominates a set of nodes
    /// @param nodesEd25519PubKeys nodes Ed25519 public keys to nominate, the amount of staked tokens will be evenly distributed to the nodes
    /// @param nominator The address of the user who nominated the nodes
    event Nominated(bytes32[] nodesEd25519PubKeys, address nominator);

    /// @notice Emitted when a user initiates an unstake
    /// @param staker The address of the user who initiated the unstake
    event UnstakeInitiated(address staker, uint248 amount);

    /// @notice Emitted when a user cancels an unstake
    /// @param staker The address of the user who cancelled the unstake
    event InitiateUnstakeCancelled(address staker);

    /// @notice Emitted when a user's unstake request is processed
    /// @param staker The address of the user who had their unstake request processed
    event UnstakeClaimed(address staker);

    /// @notice Emitted when the SubstrateSignatureValidator address is set
    /// @param substrateSignatureValidator The new SubstrateSignatureValidator address
    /// @dev this event is emitted only by the constructor
    event SubstrateSignatureValidatorSet(address substrateSignatureValidator);

    /// @notice Emitted when the unstake is completed and tokens are transferred to the staker
    /// @param staker The address of the user who had their unstake request processed
    /// @param amount The amount of tokens unstaked
    event Unstaked(address staker, uint248 amount);

    // ** functions ** //
    /// @notice Stake tokens by msg.sender
    /// @param amount The amount of tokens to stake
    /// @dev the staking balance will be distributed to the nodes evenly
    /// @dev requires:
    /// 1 - amount is > 100 wei of SXT token.
    /// 2 - user already UnstakeInitiated.
    function stake(uint248 amount) external;

    /// @notice Nominate a set of nodes
    /// @param nodesEd25519PubKeys nodes Ed25519 public keys to nominate, the amount of staked tokens will be evenly distributed to the nodes
    /// @dev the list of nodesEd25519PubKeys must be sorted in ascending order and unique
    function nominate(bytes32[] calldata nodesEd25519PubKeys) external;

    /// @notice Initiate an unstake request, the staker will not receive any rewards during the unbonding period
    /// @dev can be called only if user has not already initiated an unstake
    /// @custom:events
    /// * UnstakeInitiated
    function initiateUnstake(uint248 amount) external;

    /// @notice Cancel an unstake request
    /// @dev can only be called if the unstake request has not been processed
    /// @custom:events
    /// * InitiateUnstakeCancelled
    function cancelInitiateUnstake() external;

    /// @notice Request to process an unstake, this will be picked up by the SXT Chain which will fulfill the unstake
    /// @custom:events
    /// * UnstakeClaimed
    function claimUnstake() external;

    /// @notice Callback by the SXT Chain to fulfill an unstake request
    /// @param staker The staker of the unstake request
    /// @param amount The amount of tokens to unstake
    /// @param sxtBlockNumber The SXT Chain block number when the unstake was processed
    /// @param proof list of proof nodes
    /// @param r list of r values
    /// @param s list of s values
    /// @param v list of v values
    /// @dev the leaf consists of <staker, amount>, then we derive the root hash from the proofs and leaf.
    /// @dev the message hash is derived from the root hash, the sxt block number and the chain id.
    /// @dev the signature is validated by the SubstrateSignatureValidator contract against the attestors list and threshold.
    /// @dev attestors should be unique and sorted in ascending order.
    function sxtFulfillUnstake(
        address staker,
        uint248 amount,
        uint64 sxtBlockNumber,
        bytes32[] calldata proof,
        bytes32[] calldata r,
        bytes32[] calldata s,
        uint8[] calldata v
    ) external;

    /// @notice Unpause unstaking
    /// @dev can only be called by the owner
    function unpauseUnstaking() external;
}
