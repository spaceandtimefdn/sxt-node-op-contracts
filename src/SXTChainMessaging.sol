// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISXTChainMessaging} from "./interfaces/ISXTChainMessaging.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SXTChainMessaging
/// @notice Implementation for sending messages to the SXT Chain
contract SXTChainMessaging is ISXTChainMessaging {
    using SafeERC20 for IERC20;

    /// @notice Error thrown when a zero address is provided where not allowed
    error ZeroAddress();

    /// @notice The ERC20 token used for funded messages
    address public immutable TOKEN_ADDRESS;

    /// @notice Mapping of sender address to their message nonce
    mapping(address => uint248) private _nonces;

    /// @notice Constructor to set the token address
    /// @param tokenAddress The address of the ERC20 token
    constructor(address tokenAddress) {
        if (tokenAddress == address(0)) revert ZeroAddress();
        TOKEN_ADDRESS = tokenAddress;
    }

    /// @inheritdoc ISXTChainMessaging
    function message(bytes calldata body) external {
        ++_nonces[msg.sender];
        emit Message(msg.sender, body, _nonces[msg.sender]);
    }

    /// @inheritdoc ISXTChainMessaging
    function fundedMessage(bytes calldata body, address target, uint248 amount) external {
        ++_nonces[msg.sender];

        SafeERC20.safeTransferFrom(IERC20(TOKEN_ADDRESS), msg.sender, target, amount);

        emit FundedMessage(msg.sender, body, _nonces[msg.sender], target, amount);
    }

    /// @inheritdoc ISXTChainMessaging
    function getNonce(address sender) external view returns (uint248 nonce) {
        nonce = _nonces[sender];
    }
}
