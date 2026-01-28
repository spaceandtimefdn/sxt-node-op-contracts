// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISubstrateSignatureValidator} from "./interfaces/ISubstrateSignatureValidator.sol";

/// @title SubstrateSignatureValidator
/// @notice A contract that validates signatures from the Substrate blockchain
contract SubstrateSignatureValidator is ISubstrateSignatureValidator, Ownable {
    /// @notice The list of attestor wallets
    address[] private _attestors;
    /// @notice The threshold of the attestors
    uint16 private _threshold;

    /// @notice The error emitted when the threshold is invalid
    error InvalidThreshold();
    /// @notice The error emitted when the attestors list is empty
    error EmptyAttestorsList();
    /// @notice The error emitted when the attestor address is invalid
    error InvalidAttestorAddress();
    /// @notice The error emitted when the attestor list is invalid
    error InvalidAttestorList();
    /// @notice The error emitted when the attestors length is less than the threshold
    error AttestorsLengthLessThanThreshold();

    constructor(address[] memory attestors, uint16 threshold) Ownable(msg.sender) {
        _updateThreshold(threshold);
        _updateAttestors(attestors);
    }

    function _updateAttestors(address[] memory attestors) internal {
        if (attestors.length == 0) revert EmptyAttestorsList();
        if (attestors[0] == address(0)) revert InvalidAttestorAddress();
        if (attestors.length < _threshold) revert AttestorsLengthLessThanThreshold();

        uint256 attestorsLength = attestors.length;
        for (uint256 i = 1; i < attestorsLength; ++i) {
            // solhint-disable-next-line gas-strict-inequalities
            if (attestors[i] <= attestors[i - 1]) revert InvalidAttestorList();
        }

        _attestors = attestors;
        emit AttestorsUpdated(attestors);
    }

    function _updateThreshold(uint16 threshold) internal {
        if (threshold == 0) revert InvalidThreshold();

        _threshold = threshold;
        emit ThresholdUpdated(threshold);
    }

    /// @inheritdoc ISubstrateSignatureValidator
    function getAttestors() external view returns (address[] memory attestors) {
        return _attestors;
    }

    /// @inheritdoc ISubstrateSignatureValidator
    function isAttestor(address attestor) external view returns (bool result) {
        uint256 attestorsLength = _attestors.length;
        for (uint256 i = 0; i < attestorsLength; ++i) {
            if (_attestors[i] == attestor) return true;
        }
        return false;
    }

    /// @inheritdoc ISubstrateSignatureValidator
    function getThreshold() external view returns (uint16 threshold) {
        return _threshold;
    }

    /// @inheritdoc ISubstrateSignatureValidator
    function updateAttestorsAndThreshold(address[] calldata attestors, uint16 threshold) external onlyOwner {
        _updateThreshold(threshold);
        _updateAttestors(attestors);
    }

    /// @inheritdoc ISubstrateSignatureValidator
    function validateMessage(bytes32 message, bytes32[] calldata r, bytes32[] calldata s, uint8[] calldata v)
        external
        view
        returns (bool result)
    {
        if (r.length != s.length || s.length != v.length || r.length == 0) return false;

        uint256 attestorsLength = _attestors.length;
        uint256 signaturesLength = r.length;

        uint256 validSignaturesCount = 0;
        uint256 attestorIndex = 0;

        for (uint256 i = 0; i < signaturesLength; ++i) {
            address recoveredAddress = ecrecover(message, v[i], r[i], s[i]);

            while (attestorIndex < attestorsLength && _attestors[attestorIndex] < recoveredAddress) {
                ++attestorIndex;
            }

            if (attestorIndex < attestorsLength && _attestors[attestorIndex] == recoveredAddress) {
                ++validSignaturesCount;
                ++attestorIndex;
            }

            if (validSignaturesCount == _threshold) return true;
        }

        return false;
    }
}
