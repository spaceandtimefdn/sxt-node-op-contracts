// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TokenSplitter} from "../../src/TokenSplitter.sol";
import {TokenSplitterBaseTest} from "./TokenSplitterBaseTest.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Tests for TokenSplitter transfer failure scenarios
contract TransferFailureTest is TokenSplitterBaseTest {
    error TransferReverted();

    function testDistributionWithFailedTransfer() public {
        // Setup new splitter with 2 recipients
        address[] memory newRecipients = new address[](2);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;

        uint8[] memory newPercentages = new uint8[](2);
        newPercentages[0] = 50;
        newPercentages[1] = 50;

        TokenSplitter newSplitter = _createNewSplitter(newRecipients, newPercentages);

        // Mint tokens to the splitter - using 200 to ensure it's a multiple of 100
        token.mint(address(newSplitter), 200);

        // Mock transfer to return false
        vm.mockCall(address(token), abi.encodeWithSelector(IERC20.transfer.selector, ALICE, 100), abi.encode(false));

        // Should revert with SafeERC20's transfer failure message
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        newSplitter.distribute();

        vm.clearMockedCalls();
    }

    function testDistributionWithFailedTransferAndRemainder() public {
        // Create arrays for 2 recipients
        address[] memory newRecipients = new address[](2);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;

        uint8[] memory newPercentages = new uint8[](2);
        newPercentages[0] = 50;
        newPercentages[1] = 50;

        TokenSplitter newSplitter = _createNewSplitter(newRecipients, newPercentages);

        // Mock initial balanceOf to return 212 (200 will be distributed, 12 will remain)
        vm.mockCall(
            address(token), abi.encodeWithSelector(IERC20.balanceOf.selector, address(newSplitter)), abi.encode(212)
        );

        // Break up the long string to avoid solhint warning
        string memory part1 = "ERC20InsufficientBalance";
        string memory part2 = "(address,uint256,uint256)";
        string memory errorSignature = string.concat(part1, part2);
        bytes memory revertData = abi.encodeWithSignature(errorSignature, address(newSplitter), 0, 100);
        vm.mockCallRevert(address(token), abi.encodeWithSelector(IERC20.transfer.selector, ALICE, 100), revertData);

        // Should revert with insufficient balance error
        vm.expectRevert(revertData);
        newSplitter.distribute();

        vm.clearMockedCalls();
    }

    function testDistributionWithMixedTransferResults() public {
        // Create a splitter with 3 recipients
        address[] memory newRecipients = new address[](3);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;
        newRecipients[2] = CHARLIE;

        uint8[] memory newPercentages = new uint8[](3);
        newPercentages[0] = 33; // 33%
        newPercentages[1] = 33; // 33%
        newPercentages[2] = 34; // 34%

        TokenSplitter newSplitter = _createNewSplitter(newRecipients, newPercentages);

        // Mint tokens to the splitter - using 300 to ensure it's a multiple of 100
        token.mint(address(newSplitter), 300);

        // Make transfer fail for BOB but succeed for others
        token.setTransferShouldRevert(BOB, true);

        // Distribution should revert since BOB's transfer fails
        vm.expectRevert(TransferReverted.selector);
        newSplitter.distribute();

        // Verify that no tokens were transferred to any recipient
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(CHARLIE), 0);
        assertEq(token.balanceOf(address(newSplitter)), 300);
    }
}
