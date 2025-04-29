// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IStakingPool} from "./interfaces/IStakingPool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StakingPool is IStakingPool, Ownable {
    using SafeERC20 for IERC20;

    /// @notice The error emitted when the staking contract is zero address
    error InvalidStakingContract();
    /// @notice The error emitted when the staking contract is already added
    error StakingContractAlreadyAdded();
    /// @notice The error emitted when the staking contract is not found
    error StakingContractNotFound();
    /// @notice The error emitted when the staking token is the zero address
    error InvalidTokenAddress();
    /// @notice The error emitted when the withdraw amount is invalid
    error InvalidWithdrawAmount();
    /// @notice The error emitted when the caller is not a staking contract
    error CallerIsNotStakingContract();
    /// @notice The error emitted when the staker is the zero address
    error InvalidStakerAddress();
    /// @notice The error emitted when the pool has insufficient balance
    error InsufficientPoolBalance();

    /// @notice list of staking contracts
    mapping(address => bool) public _stakingContracts;

    /// @notice the staking token
    address public immutable TOKEN_ADDRESS;

    constructor(address tokenAddress, address owner) Ownable(owner) {
        if (tokenAddress == address(0)) revert InvalidTokenAddress();
        // The Ownable constructor already checks for zero owner address

        TOKEN_ADDRESS = tokenAddress;
        emit StakingTokenSet(tokenAddress);
    }

    /// @notice Modifier to check if the caller is a staking contract
    modifier onlyStakingContract() {
        if (!_stakingContracts[msg.sender]) revert CallerIsNotStakingContract();
        _;
    }

    // @inheritdoc IStakingPool
    function addStakingContract(address stakingContractAddress) external onlyOwner {
        if (stakingContractAddress == address(0)) revert InvalidStakingContract();
        if (_stakingContracts[stakingContractAddress]) revert StakingContractAlreadyAdded();

        _stakingContracts[stakingContractAddress] = true;
        emit StakingContractAdded(stakingContractAddress);
    }

    // @inheritdoc IStakingPool
    function removeStakingContract(address stakingContractAddress) external onlyOwner {
        if (!_stakingContracts[stakingContractAddress]) revert StakingContractNotFound();

        _stakingContracts[stakingContractAddress] = false;
        emit StakingContractRemoved(stakingContractAddress);
    }

    // @inheritdoc IStakingPool
    function withdraw(address staker, uint248 amount) external onlyStakingContract {
        if (amount == 0) revert InvalidWithdrawAmount();
        if (staker == address(0)) revert InvalidStakerAddress();

        // Check if the pool has sufficient balance
        if (IERC20(TOKEN_ADDRESS).balanceOf(address(this)) < amount) revert InsufficientPoolBalance();

        // SafeERC20 expects uint256, so we need to convert
        IERC20(TOKEN_ADDRESS).safeTransfer(staker, uint256(amount));
        emit AmountWithdrawn(amount, staker, msg.sender);
    }
}
