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

    /// @notice Emitted when a funded message is sent to the SXT Chain
    /// @param sender The address of the sender
    /// @param body The message being sent
    /// @param nonce The nonce of the message
    /// @param target The address receiving the tokens
    /// @param amount The amount of tokens transferred
    event FundedMessage(address sender, bytes body, uint248 nonce, address target, uint248 amount);

    /// @notice Send a message to the SXT Chain
    /// @param body The message to send
    function message(bytes calldata body) external;

    /// @notice Send a funded message to the SXT Chain with ERC20 transfer
    /// @param body The message to send
    /// @param target The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    function fundedMessage(bytes calldata body, address target, uint248 amount) external;

    /// @notice Get the current nonce for a sender
    /// @param sender The address to get the nonce for
    /// @return nonce The current nonce for the sender
    function getNonce(address sender) external view returns (uint248 nonce);
}
