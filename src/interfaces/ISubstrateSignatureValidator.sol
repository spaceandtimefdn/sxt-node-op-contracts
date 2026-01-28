// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ISubstrateSignatureValidator
/// @notice Interface for the SubstrateSignatureValidator contract
/// @notice This contract is used to validate messages signed by the substrate SXT Chain attestors.
interface ISubstrateSignatureValidator {
    /*  ********** events ********** */

    /// @notice Emitted when the attestors are updated
    /// @param attestors The addresses of the attestors
    event AttestorsUpdated(address[] attestors);

    /// @notice Emitted when the threshold is updated
    /// @param threshold The threshold
    event ThresholdUpdated(uint16 threshold);

    /*  ********** functions ********** */

    /// @notice Get the attestors
    /// @return attestors The addresses of the attestors
    function getAttestors() external view returns (address[] memory attestors);

    /// @notice Check if an address is an attestor
    /// @param attestor The address to check
    /// @return result True if the address is an attestor, false otherwise
    function isAttestor(address attestor) external view returns (bool result);

    /// @notice Get the threshold
    /// @return threshold The threshold
    function getThreshold() external view returns (uint16 threshold);

    /// @notice Atomic method to update both attestors and threshold
    /// @param attestors The addresses of the attestors
    /// @param threshold The threshold
    /// @dev this function can only be called by the owner [Multisig Safe]
    /// @dev the attestors addresses should be unique and sorted in ascending order
    function updateAttestorsAndThreshold(address[] calldata attestors, uint16 threshold) external;

    /// @notice Validate a message signed by the substrate SXT Chain attestors
    /// @param message The message to validate
    /// @param r The r values of the signatures
    /// @param s The s values of the signatures
    /// @param v The v values of the signatures
    /// @dev the signed attestors should be ordered in ascending order
    function validateMessage(bytes32 message, bytes32[] calldata r, bytes32[] calldata s, uint8[] calldata v)
        external
        view
        returns (bool result);
}
