// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStaking} from "./interfaces/IStaking.sol";

/// @title Collaborative Staking Proxy Contract
/// @notice This contract facilitates collaborative staking by allowing funders, stakers, and beneficiaries to interact with a staking pool.
/// @dev Implements role-based access control using OpenZeppelin's AccessControl.
///
/// ## Overview
/// - **Funders**: Funders can deposit any amount of tokens into the contract. They can withdraw up to the amount they have deposited, provided the contract has sufficient balance.
/// - **Stakers**: Stakers can stake all the funds in this contract into the staking contract. They can also nominate nodes and initiate or cancel unstaking.
/// - **Beneficiaries**: Beneficiaries can withdraw any surplus in the contract that exceeds the total deposits made by funders.
///
/// ## Example Workflow
/// 1. A funder deposits 1000 tokens into the contract.
/// 2. A staker calls `stake`, which moves the 1000 tokens to the staking contract.
///    - At this point, no one can withdraw tokens from the contract.
/// 3. Over time, the staking contract accumulates rewards, increasing the total stake to 1100 tokens.
/// 4. The staker initiates an unstake of 500 tokens, which moves 500 tokens back to this contract.
/// 5. The funder can now withdraw up to 250 tokens, leaving 750 tokens as their outstanding deposit.
///    - The contract balance is 250 tokens, and the staking contract still holds 600 tokens.
///    - The beneficiary cannot withdraw any tokens because the contract balance does not exceed the total deposits (750 tokens).
/// 6. The staker unstakes the remaining 600 tokens, increasing the contract balance to 850 tokens.
/// 7. At this point, the beneficiary can withdraw 100 tokens (850 - 750), leaving 750 tokens in the contract.
/// 8. The staker can restake the funds at any time, sending the balance back to the staking pool.
contract CollaborativeStaking is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant FUNDER_ROLE = keccak256("FUNDER_ROLE");
    bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");
    bytes32 public constant BENEFICIARY_ROLE = keccak256("BENEFICIARY_ROLE");

    /// @notice Address of the ERC20 token used for staking.
    address public immutable TOKEN_ADDRESS;

    /// @notice Address of the staking contract.
    address public immutable STAKING_ADDRESS;

    /// @notice Total deposits made by all funders.
    uint256 public totalDeposits;

    /// @notice Mapping of funder addresses to their deposit balances.
    mapping(address => uint256) public funderDeposits;

    /// @notice Delay for staking operation.
    uint256 public immutable STAKING_DELAY_LENGTH;

    /// @notice Timestamp of the last staking delay start.
    uint256 public stakingDelayStartTime;

    /// @dev Error thrown when a zero address is provided.
    error ZeroAddress();

    /// @dev Error thrown when a deposit amount is zero.
    error DepositAmountZero();

    /// @dev Error thrown when a funder tries to withdraw more than their deposit balance.
    error InsufficientDepositBalance();

    /// @dev Error thrown when a staking operation is attempted before the staking delay expires.
    error StakingDelayNotExpired();

    /// @dev Error thrown when there is no surplus to withdraw.
    error NoSurplusToWithdraw();

    /// @dev Error thrown when the contract has insufficient balance for a withdrawal.
    error InsufficientWithdrawableBalance();

    /// @dev Error thrown when token approval fails.
    error TokenApprovalFailed();

    /// @notice Emitted when a funder deposits tokens.
    /// @param funder The address of the funder.
    /// @param amount The amount of tokens deposited.
    event Deposit(address indexed funder, uint256 amount);

    /// @notice Emitted when a funder withdraws tokens.
    /// @param funder The address of the funder.
    /// @param amount The amount of tokens withdrawn.
    event Withdrawal(address indexed funder, uint256 amount);

    /// @notice Emitted when tokens are staked.
    /// @param amount The amount of tokens staked.
    event Stake(uint256 amount);

    /// @notice Emitted when a beneficiary withdraws surplus tokens.
    /// @param beneficiary The address of the beneficiary.
    /// @param amount The amount of surplus tokens withdrawn.
    event SurplusWithdrawn(address indexed beneficiary, uint256 amount);

    /// @notice Emitted when nodes are nominated.
    /// @param nodesEd25519PubKeys The public keys of the nominated nodes.
    event Nominate(bytes32[] nodesEd25519PubKeys);

    /// @notice Emitted when unstaking is initiated.
    /// @param amount The amount of tokens to unstake.
    event InitiateUnstake(uint256 amount);

    /// @notice Emitted when unstaking is canceled.
    event CancelInitiateUnstake();

    /// @notice Emitted when unstaked tokens are claimed.
    event ClaimUnstake();

    /// @notice Constructor to initialize the contract.
    /// @param tokenAddress The address of the ERC20 token used for staking.
    /// @param stakingAddress The address of the staking contract.
    /// @param stakingDelayLength The staking delay length.
    constructor(address tokenAddress, address stakingAddress, uint256 stakingDelayLength) {
        if (tokenAddress == address(0)) revert ZeroAddress();
        if (stakingAddress == address(0)) revert ZeroAddress();
        if (stakingDelayLength == 0) revert ZeroAddress();

        TOKEN_ADDRESS = tokenAddress;
        STAKING_ADDRESS = stakingAddress;
        STAKING_DELAY_LENGTH = stakingDelayLength;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Modifier to enforce staking delay
    modifier withStakingDelay() {
        if (block.timestamp < stakingDelayStartTime + STAKING_DELAY_LENGTH) {
            revert StakingDelayNotExpired();
        }
        _;
    }

    /// @dev Internal function to start the staking delay.
    function _startStakingDelay() internal {
        stakingDelayStartTime = block.timestamp;
    }

    /// @notice Allows funders to deposit tokens.
    /// @param amount The amount of tokens to deposit.
    function deposit(uint248 amount) external onlyRole(FUNDER_ROLE) {
        if (amount == 0) revert DepositAmountZero();
        IERC20(TOKEN_ADDRESS).safeTransferFrom(msg.sender, address(this), amount);
        funderDeposits[msg.sender] += amount;
        totalDeposits += amount;

        emit Deposit(msg.sender, amount);
    }

    /// @notice Allows funders to withdraw their deposited tokens.
    /// @param amount The amount of tokens to withdraw.
    function withdraw(uint248 amount) external onlyRole(FUNDER_ROLE) {
        if (funderDeposits[msg.sender] < amount) revert InsufficientDepositBalance();

        uint256 availableBalance = IERC20(TOKEN_ADDRESS).balanceOf(address(this));
        if (availableBalance < amount) revert InsufficientWithdrawableBalance();

        funderDeposits[msg.sender] -= amount;
        totalDeposits -= amount;
        IERC20(TOKEN_ADDRESS).safeTransfer(msg.sender, amount);

        emit Withdrawal(msg.sender, amount);
    }

    /// @notice Allows stakers to stake tokens.
    function stake() external onlyRole(STAKER_ROLE) withStakingDelay {
        uint256 stakeableAmount = IERC20(TOKEN_ADDRESS).balanceOf(address(this));

        emit Stake(stakeableAmount);

        bool success = IERC20(TOKEN_ADDRESS).approve(STAKING_ADDRESS, stakeableAmount);
        if (!success) revert TokenApprovalFailed();

        IStaking(STAKING_ADDRESS).stake(uint248(stakeableAmount));
    }

    /// @notice Allows stakers to nominate nodes.
    /// @param nodesEd25519PubKeys The public keys of the nodes to nominate.
    function nominate(bytes32[] calldata nodesEd25519PubKeys) external onlyRole(STAKER_ROLE) {
        emit Nominate(nodesEd25519PubKeys);

        IStaking(STAKING_ADDRESS).nominate(nodesEd25519PubKeys);
    }

    /// @notice Allows stakers to initiate unstaking.
    /// @param amount The amount of tokens to unstake.
    function initiateUnstake(uint248 amount) external onlyRole(STAKER_ROLE) {
        _startStakingDelay();

        emit InitiateUnstake(amount);

        IStaking(STAKING_ADDRESS).initiateUnstake(amount);
    }

    /// @notice Allows stakers to cancel an initiated unstaking.
    function cancelInitiateUnstake() external onlyRole(STAKER_ROLE) withStakingDelay {
        emit CancelInitiateUnstake();

        IStaking(STAKING_ADDRESS).cancelInitiateUnstake();
    }

    /// @notice Allows stakers to claim unstaked tokens.
    function claimUnstake() external onlyRole(STAKER_ROLE) {
        stakingDelayStartTime = 0;
        emit ClaimUnstake();

        IStaking(STAKING_ADDRESS).claimUnstake();
    }

    function _getCurrentSurplus() internal view returns (uint256 surplus) {
        surplus = 0;
        uint256 availableBalance = IERC20(TOKEN_ADDRESS).balanceOf(address(this));
        if (availableBalance > totalDeposits) {
            surplus = availableBalance - totalDeposits;
        }
    }

    /// @notice Allows beneficiaries to withdraw surplus tokens.
    function withdrawSurplus() external onlyRole(BENEFICIARY_ROLE) {
        uint256 surplus = _getCurrentSurplus();
        // slither-disable-next-line incorrect-equality
        if (surplus == 0) revert NoSurplusToWithdraw();

        IERC20(TOKEN_ADDRESS).safeTransfer(msg.sender, surplus);

        emit SurplusWithdrawn(msg.sender, surplus);
    }

    /// @notice Returns the current deposit balance of a funder.
    /// @param funder The address of the funder.
    /// @return balance The current deposit balance of the funder.
    function getFunderDepositBalance(address funder) external view returns (uint256 balance) {
        balance = funderDeposits[funder];
    }

    /// @notice Returns the current surplus available for the beneficiary.
    /// @return surplus The current surplus in the contract.
    function getCurrentSurplus() external view returns (uint256 surplus) {
        surplus = _getCurrentSurplus();
    }

    /// @notice Returns the total deposits made by all funders.
    /// @return balance The total deposit balance in the contract.
    function getTotalDepositBalance() external view returns (uint256 balance) {
        balance = totalDeposits;
    }
}
