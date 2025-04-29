// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IStaking} from "../../src/interfaces/IStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockStaking is IStaking {
    uint256 public stakedAmount;
    address public immutable TOKEN_ADDRESS;

    constructor(address tokenAddress) {
        TOKEN_ADDRESS = tokenAddress;
    }

    function stake(uint248 amount) external override {
        // Transfer tokens from the caller to the MockStaking contract
        IERC20(TOKEN_ADDRESS).transferFrom(msg.sender, address(this), amount);
        stakedAmount += amount;
    }

    function nominate(bytes32[] calldata) external override {} // solhint-disable-line no-empty-blocks

    function initiateUnstake(uint248) external override {} // solhint-disable-line no-empty-blocks

    function cancelInitiateUnstake() external override {} // solhint-disable-line no-empty-blocks

    function claimUnstake() external override {} // solhint-disable-line no-empty-blocks

    function sxtFulfillUnstake(
        address staker,
        uint248 amount,
        uint64 sxtBlockNumber,
        bytes32[] calldata proof,
        bytes32[] calldata r,
        bytes32[] calldata s,
        uint8[] calldata v
    ) external override {} // solhint-disable-line no-empty-blocks

    function unpauseUnstaking() external override {} // solhint-disable-line no-empty-blocks
}
