// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISXTChainMessaging} from "./interfaces/ISXTChainMessaging.sol";

/// @title SXTChainMessaging
/// @notice Implementation for sending messages to the SXT Chain
contract SXTChainMessaging is ISXTChainMessaging {
    /// @notice Mapping of sender address to their message nonce
    mapping(address => uint248) private _nonces;

    /// @inheritdoc ISXTChainMessaging
    function message(bytes calldata body) external {
        ++_nonces[msg.sender];
        emit Message(msg.sender, body, _nonces[msg.sender]);
    }

    /// @inheritdoc ISXTChainMessaging
    function getNonce(address sender) external view returns (uint248 nonce) {
        nonce = _nonces[sender];
    }
}
