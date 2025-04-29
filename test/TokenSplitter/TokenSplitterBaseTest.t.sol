// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TokenSplitter} from "../../src/TokenSplitter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Base test contract for TokenSplitter tests
abstract contract TokenSplitterBaseTest is Test {
    TokenSplitter public splitter;
    MockERC20 public token;

    address[] public recipients;
    uint8[] public percentages;

    address public constant ALICE = address(0x1);
    address public constant BOB = address(0x2);
    address public constant CHARLIE = address(0x3);
    address public constant DAVID = address(0x4);

    uint8 public constant MAX_RECIPIENTS = 32;

    function setUp() public virtual {
        // Create mock token
        token = new MockERC20();

        // Setup recipients and percentages
        recipients = new address[](3);
        recipients[0] = ALICE;
        recipients[1] = BOB;
        recipients[2] = CHARLIE;

        percentages = new uint8[](3);
        percentages[0] = 20; // 20%
        percentages[1] = 30; // 30%
        percentages[2] = 50; // 50%

        // Deploy splitter
        splitter = new TokenSplitter(address(token), recipients, percentages);
    }

    function _createNewSplitter(address[] memory _recipients, uint8[] memory _percentages)
        internal
        returns (TokenSplitter newSplitter)
    {
        return new TokenSplitter(address(token), _recipients, _percentages);
    }

    // Helper to emit Transfer events for testing
    event Transfer(address indexed from, address indexed to, uint256 value);
}
