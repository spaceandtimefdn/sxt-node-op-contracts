// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ISubstrateSignatureValidator} from "./interfaces/ISubstrateSignatureValidator.sol";
import {IStakingPool} from "./interfaces/IStakingPool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract Staking is IStaking, Ownable, Pausable {
    using SafeERC20 for IERC20;

    /// @notice token address is the zero address
    error ZeroAddress();
    /// @notice nodes list is empty
    error EmptyNodesList();
    /// @notice amount is zero
    error StakingZeroAmount();
    /// @notice node Ed25519 public key is invalid
    error InvalidNodeEd25519PubKey();
    /// @notice node Ed25519 public key is duplicate
    error DuplicateNodeEd25519PubKey();
    /// @notice user has already initiated an unstake
    error UnstakeAlreadyInitiated();
    /// @notice unstake initiation has not met the unbonding period
    error UnstakeNotUnbonded();
    /// @notice user has no unstake initiation
    error InitiateUnstakeNotFound();
    /// @notice unbonding period is zero
    error UnbondingPeriodZero();
    /// @notice amount is below the minimum staking amount
    error StakingBelowMinAmount();
    /// @notice signature is invalid
    error InvalidSignature();
    /// @notice sxt block number is invalid
    error InvalidSxtBlockNumber();
    /// @notice staker is in an invalid state for the requested operation
    error InvalidStakerState(StakerState current, StakerState required);
    /// @notice staker has claimed unstake and is waiting for fulfillment
    error PendingUnstakeFulfillment();

    /// The number of decimals for the token
    uint8 public constant TOKEN_DECIMALS = 18;
    /// @notice The minimum amount of tokens that can be staked
    uint248 public constant MIN_STAKING_AMOUNT = 100 * uint248(10 ** TOKEN_DECIMALS);
    /// @notice The address of the token to stake
    address public immutable TOKEN_ADDRESS;
    /// @notice The address of the staking pool
    address public immutable STAKING_POOL_ADDRESS;
    /// @notice The unstaking unbonding period in seconds
    uint64 public immutable UNSTAKING_UNBONDING_PERIOD;
    /// @notice The address of the SubstrateSignatureValidator contract
    address public immutable SUBSTRATE_SIGNATURE_VALIDATOR_ADDRESS;

    /// @notice The unstake requests timestamp
    mapping(address => uint64) public initiateUnstakeRequestsTimestamp;

    /// @notice The latest sxtBlock unstake fulfillment by that staker
    mapping(address => uint64) public latestSxtBlockFulfillmentByStaker;

    /// @notice The staker state
    mapping(address => StakerState) public stakerState;

    /**
     * @dev Modifier to validate a staker is in a specific state
     * @param staker The address of the staker to check
     * @param requiredState The state the staker must be in
     */
    modifier requireState(address staker, StakerState requiredState) {
        if (stakerState[staker] != requiredState) {
            revert InvalidStakerState(stakerState[staker], requiredState);
        }
        _;
    }

    /**
     * @dev Modifier to validate a staker is not in the UnstakeClaimed state
     * @param staker The address of the staker to check
     */
    modifier requireStateNotUnstakeClaimed(address staker) {
        if (stakerState[staker] == StakerState.UnstakeClaimed) {
            revert PendingUnstakeFulfillment();
        }
        _;
    }

    constructor(
        address tokenAddress,
        address stakingPoolAddress,
        uint64 unstakingUnbondingPeriod,
        address substrateSignatureValidatorAddress
    ) Ownable(msg.sender) {
        if (tokenAddress == address(0)) revert ZeroAddress();
        if (stakingPoolAddress == address(0)) revert ZeroAddress();
        if (unstakingUnbondingPeriod == 0) revert UnbondingPeriodZero();
        if (substrateSignatureValidatorAddress == address(0)) revert ZeroAddress();

        TOKEN_ADDRESS = tokenAddress;
        emit StakingTokenSet(tokenAddress);

        STAKING_POOL_ADDRESS = stakingPoolAddress;
        emit StakingPoolSet(stakingPoolAddress);

        UNSTAKING_UNBONDING_PERIOD = unstakingUnbondingPeriod;
        emit UnstakingUnbondingPeriodSet(unstakingUnbondingPeriod);

        SUBSTRATE_SIGNATURE_VALIDATOR_ADDRESS = substrateSignatureValidatorAddress;
        emit SubstrateSignatureValidatorSet(substrateSignatureValidatorAddress);

        _pause();
    }

    // @inheritdoc IStaking
    function stake(uint248 amount) external requireStateNotUnstakeClaimed(msg.sender) {
        if (amount == 0) revert StakingZeroAmount();
        if (amount < MIN_STAKING_AMOUNT) revert StakingBelowMinAmount();

        // If the staker has already initiated an unstake, cancel it
        if (stakerState[msg.sender] == StakerState.UnstakeInitiated) {
            _cancelInitiateUnstake(msg.sender);
        }

        // Update state before external call (following checks-effects-interactions pattern)
        stakerState[msg.sender] = StakerState.Staked;

        // Transfer tokens directly from user to the staking pool
        IERC20(TOKEN_ADDRESS).safeTransferFrom(msg.sender, STAKING_POOL_ADDRESS, amount);

        // Emit event after all operations are complete
        emit Staked(msg.sender, amount);
    }

    // @inheritdoc IStaking
    function nominate(bytes32[] calldata nodesEd25519PubKeys) external {
        if (nodesEd25519PubKeys.length == 0) revert EmptyNodesList();
        if (nodesEd25519PubKeys[0] == bytes32(0)) revert InvalidNodeEd25519PubKey();

        uint256 nodesEd25519PubKeysLength = nodesEd25519PubKeys.length;
        for (uint256 i = 1; i < nodesEd25519PubKeysLength; ++i) {
            // solhint-disable-next-line gas-strict-inequalities
            if (nodesEd25519PubKeys[i] <= nodesEd25519PubKeys[i - 1]) {
                revert DuplicateNodeEd25519PubKey();
            }
        }

        emit Nominated(nodesEd25519PubKeys, msg.sender);
    }

    // @inheritdoc IStaking
    function initiateUnstake(uint248 amount) external requireState(msg.sender, StakerState.Staked) whenNotPaused {
        initiateUnstakeRequestsTimestamp[msg.sender] = uint64(block.timestamp);
        stakerState[msg.sender] = StakerState.UnstakeInitiated;
        emit UnstakeInitiated(msg.sender, amount);
    }

    function _cancelInitiateUnstake(address user) internal {
        initiateUnstakeRequestsTimestamp[user] = 0;
        stakerState[user] = StakerState.Staked;
        emit InitiateUnstakeCancelled(user);
    }

    // @inheritdoc IStaking
    function cancelInitiateUnstake() external requireState(msg.sender, StakerState.UnstakeInitiated) whenNotPaused {
        _cancelInitiateUnstake(msg.sender);
    }

    // @inheritdoc IStaking
    function claimUnstake() external requireState(msg.sender, StakerState.UnstakeInitiated) whenNotPaused {
        uint64 earliestPossibleClaimUnstakeRequest =
            initiateUnstakeRequestsTimestamp[msg.sender] + UNSTAKING_UNBONDING_PERIOD;
        // slither-disable-next-line timestamp
        if (block.timestamp < earliestPossibleClaimUnstakeRequest) revert UnstakeNotUnbonded();

        stakerState[msg.sender] = StakerState.UnstakeClaimed;
        emit UnstakeClaimed(msg.sender);
    }

    function _validateSxtFulfillUnstake(
        address staker,
        uint248 amount,
        uint64 sxtBlockNumber,
        bytes32[] calldata proof,
        bytes32[] calldata r,
        bytes32[] calldata s,
        uint8[] calldata v
    ) internal view returns (bool isValid) {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encodePacked(uint256(uint160(staker)), amount, block.chainid, address(this))))
        );
        bytes32 rootHash = MerkleProof.processProof(proof, leaf);
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n40", rootHash, sxtBlockNumber));

        isValid =
            ISubstrateSignatureValidator(SUBSTRATE_SIGNATURE_VALIDATOR_ADDRESS).validateMessage(messageHash, r, s, v);
    }

    // @inheritdoc IStaking
    function sxtFulfillUnstake(
        address staker,
        uint248 amount,
        uint64 sxtBlockNumber,
        bytes32[] calldata proof,
        bytes32[] calldata r,
        bytes32[] calldata s,
        uint8[] calldata v
    ) external requireState(staker, StakerState.UnstakeClaimed) whenNotPaused {
        // solhint-disable-next-line gas-strict-inequalities
        if (latestSxtBlockFulfillmentByStaker[staker] >= sxtBlockNumber) revert InvalidSxtBlockNumber();

        // Validate signature
        if (!_validateSxtFulfillUnstake(staker, amount, sxtBlockNumber, proof, r, s, v)) revert InvalidSignature();

        // State changes first (Effects)
        latestSxtBlockFulfillmentByStaker[staker] = sxtBlockNumber;
        initiateUnstakeRequestsTimestamp[staker] = 0;
        stakerState[staker] = StakerState.Unstaked;

        // Event emission before external calls
        emit Unstaked(staker, amount);

        // External interactions last - direct withdraw to staker
        IStakingPool(STAKING_POOL_ADDRESS).withdraw(staker, amount);
    }

    function unpauseUnstaking() external onlyOwner {
        _unpause();
    }
}
