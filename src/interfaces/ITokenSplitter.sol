// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ITokenSplitter Interface
/// @notice Interface for a contract that splits ERC20 tokens among predefined recipients
interface ITokenSplitter {
    /// @notice Distributes the entire token balance to predefined recipients
    /// @dev Anyone can call this function to trigger the distribution
    function distribute() external;

    /// @notice View function to get all recipients and their percentages
    /// @return recipients Array of recipient addresses
    /// @return percentages Array of corresponding percentage allocations (1-100)
    function getDistributionInfo() external view returns (address[] memory recipients, uint8[] memory percentages);
}
