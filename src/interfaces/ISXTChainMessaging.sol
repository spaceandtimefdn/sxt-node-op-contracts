// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ISXTChainMessaging
/// @notice Interface for sending messages to the SXT Chain
interface ISXTChainMessaging {
    /// @notice Emitted when a message is sent to the SXT Chain
    /// @param sender The address of the sender
    /// @param body The message being sent
    /// @param nonce The nonce of the message
    event Message(address sender, bytes body, uint248 nonce);

    /// @notice Send a message to the SXT Chain
    /// @param body The message to send
    function message(bytes calldata body) external;

    /// @notice Get the current nonce for a sender
    /// @param sender The address to get the nonce for
    /// @return nonce The current nonce for the sender
    function getNonce(address sender) external view returns (uint248 nonce);
}
