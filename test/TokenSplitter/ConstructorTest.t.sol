// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {TokenSplitter} from "../../src/TokenSplitter.sol";
import {TokenSplitterBaseTest} from "./TokenSplitterBaseTest.t.sol";

contract ConstructorTest is TokenSplitterBaseTest {
    function testConstructorValidation() public view {
        // Test that the constructor properly sets up the contract
        (address[] memory _recipients, uint8[] memory _percentages) = splitter.getDistributionInfo();

        assertEq(_recipients.length, recipients.length);
        assertEq(_percentages.length, percentages.length);

        uint256 recipientCount = recipients.length;
        for (uint256 i = 0; i < recipientCount; ++i) {
            assertEq(_recipients[i], recipients[i]);
            assertEq(_percentages[i], percentages[i]);
        }
    }

    function testConstructorWithZeroRecipients() public {
        // Create empty arrays
        address[] memory newRecipients = new address[](0);
        uint8[] memory newPercentages = new uint8[](0);

        // Should revert with NoRecipients
        vm.expectRevert(TokenSplitter.NoRecipients.selector);
        _createNewSplitter(newRecipients, newPercentages);
    }

    function testConstructorWithArrayLengthMismatch() public {
        // Create arrays with different lengths
        address[] memory newRecipients = new address[](2);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;

        uint8[] memory newPercentages = new uint8[](3);
        newPercentages[0] = 30;
        newPercentages[1] = 30;
        newPercentages[2] = 40;

        // Should revert with ArrayLengthMismatch
        vm.expectRevert(TokenSplitter.ArrayLengthMismatch.selector);
        _createNewSplitter(newRecipients, newPercentages);
    }

    function testConstructorWithAddressesNotAscending() public {
        // Create arrays with non-ascending recipient addresses
        address[] memory newRecipients = new address[](3);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;
        newRecipients[2] = address(0x2); // Same as BOB, not ascending

        uint8[] memory newPercentages = new uint8[](3);
        newPercentages[0] = 30;
        newPercentages[1] = 30;
        newPercentages[2] = 40;

        // Should revert with AddressesNotAscending
        vm.expectRevert(TokenSplitter.AddressesNotAscending.selector);
        _createNewSplitter(newRecipients, newPercentages);
    }

    function testConstructorWithAddressesInDescendingOrder() public {
        // Create arrays with addresses in descending order
        address[] memory newRecipients = new address[](3);
        newRecipients[0] = CHARLIE; // 0x3
        newRecipients[1] = BOB; // 0x2
        newRecipients[2] = ALICE; // 0x1

        uint8[] memory newPercentages = new uint8[](3);
        newPercentages[0] = 30;
        newPercentages[1] = 30;
        newPercentages[2] = 40;

        // Should revert with AddressesNotAscending
        vm.expectRevert(TokenSplitter.AddressesNotAscending.selector);
        _createNewSplitter(newRecipients, newPercentages);
    }

    function testConstructorWithMaxRecipients() public {
        // Create arrays with max recipients (32)
        address[] memory maxRecipients = new address[](32);
        uint8[] memory maxPercentages = new uint8[](32);

        // Fill arrays with valid data in ascending order
        uint256 recipientCount = maxRecipients.length;
        for (uint256 i = 0; i < recipientCount; ++i) {
            maxRecipients[i] = address(uint160(i + 1));
            maxPercentages[i] = 3; // 3% each, except last one
        }
        maxPercentages[31] = 7; // Make total 100%

        // This should not revert
        TokenSplitter maxSplitter = _createNewSplitter(maxRecipients, maxPercentages);

        // Verify the distribution info
        (address[] memory _recipients, uint8[] memory _percentages) = maxSplitter.getDistributionInfo();
        assertEq(_recipients.length, 32);
        assertEq(_percentages.length, 32);
    }

    function testConstructorWithTooManyRecipients() public {
        // Create arrays with too many recipients (33)
        address[] memory manyRecipients = new address[](33);
        uint8[] memory manyPercentages = new uint8[](33);

        // Fill arrays with valid data
        uint256 recipientCount = manyRecipients.length;
        for (uint256 i = 0; i < recipientCount; ++i) {
            manyRecipients[i] = address(uint160(i + 1));
            manyPercentages[i] = 3;
        }

        // Should revert with TooManyRecipients
        vm.expectRevert(TokenSplitter.TooManyRecipients.selector);
        _createNewSplitter(manyRecipients, manyPercentages);
    }

    function testConstructorWithPercentageOverflow() public {
        // Create arrays with 2 recipients
        address[] memory newRecipients = new address[](2);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;

        uint8[] memory newPercentages = new uint8[](2);
        newPercentages[0] = 90;
        newPercentages[1] = 90; // Total will be 180, which is > 100

        vm.expectRevert(TokenSplitter.InvalidTotalPercentage.selector);
        new TokenSplitter(address(token), newRecipients, newPercentages);
    }

    function testConstructorWithMaxPercentage() public {
        // Create arrays with 2 recipients
        address[] memory newRecipients = new address[](2);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;

        uint8[] memory newPercentages = new uint8[](2);
        newPercentages[0] = 99;
        newPercentages[1] = 1; // Total should be 100

        TokenSplitter newSplitter = new TokenSplitter(address(token), newRecipients, newPercentages);

        // Verify distribution info
        (address[] memory recipients, uint8[] memory percentages) = newSplitter.getDistributionInfo();
        assertEq(recipients.length, 2);
        assertEq(percentages.length, 2);
        assertEq(recipients[0], ALICE);
        assertEq(recipients[1], BOB);
        assertEq(percentages[0], 99);
        assertEq(percentages[1], 1);
    }

    function testConstructorWithZeroTokenAddress() public {
        vm.expectRevert(TokenSplitter.ZeroAddress.selector);
        new TokenSplitter(address(0), recipients, percentages);
    }

    function testGetDistributionInfoWithMaxRecipients() public {
        address[] memory maxRecipients = new address[](32);
        uint8[] memory maxPercentages = new uint8[](32);

        // Create arrays with 32 recipients
        // Each recipient gets 3% except the last one who gets 7%
        // Total: (31 * 3) + 7 = 100%
        uint8 percentage = 3;
        uint8 remainder = 7;

        uint256 recipientCount = maxRecipients.length;
        for (uint256 i = 0; i < recipientCount; ++i) {
            maxRecipients[i] = address(uint160(i + 1)); // Non-zero addresses
            maxPercentages[i] = percentage;
        }
        // Add remainder to last recipient
        maxPercentages[31] = remainder;

        TokenSplitter maxSplitter = new TokenSplitter(address(token), maxRecipients, maxPercentages);

        // Verify distribution info
        (address[] memory recipients, uint8[] memory percentages) = maxSplitter.getDistributionInfo();
        assertEq(recipients.length, 32);
        assertEq(percentages.length, 32);

        uint8 totalPercentage;
        uint256 recipientCount2 = recipients.length;
        for (uint256 i = 0; i < recipientCount2; ++i) {
            assertEq(recipients[i], maxRecipients[i]);
            assertEq(percentages[i], maxPercentages[i]);
            totalPercentage += percentages[i];
        }
        assertEq(totalPercentage, 100);
    }

    function testConstructorWithTokenAsRecipient() public {
        // Create arrays for 2 recipients
        address[] memory newRecipients = new address[](2);
        newRecipients[0] = ALICE;
        newRecipients[1] = address(token); // Try to use token as recipient

        uint8[] memory newPercentages = new uint8[](2);
        newPercentages[0] = 50;
        newPercentages[1] = 50;

        // Should revert with TokenAsRecipient
        vm.expectRevert(TokenSplitter.TokenAsRecipient.selector);
        new TokenSplitter(address(token), newRecipients, newPercentages);
    }

    function testConstructorWithZeroAddressRecipient() public {
        // Create arrays with one zero address recipient
        address[] memory newRecipients = new address[](3);
        newRecipients[0] = ALICE;
        newRecipients[1] = address(0); // Zero address
        newRecipients[2] = BOB;

        uint8[] memory newPercentages = new uint8[](3);
        newPercentages[0] = 30;
        newPercentages[1] = 30;
        newPercentages[2] = 40;

        // Should revert with ZeroAddress
        vm.expectRevert(TokenSplitter.ZeroAddress.selector);
        new TokenSplitter(address(token), newRecipients, newPercentages);
    }

    function testConstructorWithZeroPercentage() public {
        // Create arrays with one zero percentage
        address[] memory newRecipients = new address[](3);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;
        newRecipients[2] = CHARLIE;

        uint8[] memory newPercentages = new uint8[](3);
        newPercentages[0] = 50;
        newPercentages[1] = 0; // Zero percentage
        newPercentages[2] = 50;

        // Should revert with ZeroPercentage
        vm.expectRevert(TokenSplitter.ZeroPercentage.selector);
        new TokenSplitter(address(token), newRecipients, newPercentages);
    }

    function testConstructorComplexDuplicateScenario() public {
        // Create a more complex test with multiple potential duplicates to test the inner loop
        address[] memory newRecipients = new address[](5);
        newRecipients[0] = address(0x1);
        newRecipients[1] = address(0x2);
        newRecipients[2] = address(0x3);
        newRecipients[3] = address(0x4);
        newRecipients[4] = address(0x3); // Duplicate of index 2

        uint8[] memory newPercentages = new uint8[](5);
        newPercentages[0] = 20;
        newPercentages[1] = 20;
        newPercentages[2] = 20;
        newPercentages[3] = 20;
        newPercentages[4] = 20;

        // Should revert with AddressesNotAscending since we now check for ascending order
        vm.expectRevert(TokenSplitter.AddressesNotAscending.selector);
        new TokenSplitter(address(token), newRecipients, newPercentages);
    }

    function testConstructorWithFewRecipients() public {
        // Create arrays with small number of recipients (3)
        address[] memory recipients = new address[](3);
        uint8[] memory percentages = new uint8[](3);

        // Fill with valid data in ascending order
        recipients[0] = address(0x1);
        recipients[1] = address(0x2);
        recipients[2] = address(0x3);

        percentages[0] = 33;
        percentages[1] = 33;
        percentages[2] = 34;

        // This should not revert
        TokenSplitter newSplitter = new TokenSplitter(address(token), recipients, percentages);

        // Verify the distribution info
        (address[] memory _recipients, uint8[] memory _percentages) = newSplitter.getDistributionInfo();
        assertEq(_recipients.length, 3);
        assertEq(_percentages.length, 3);
        assertEq(_recipients[0], recipients[0]);
        assertEq(_recipients[1], recipients[1]);
        assertEq(_recipients[2], recipients[2]);
        assertEq(_percentages[0], percentages[0]);
        assertEq(_percentages[1], percentages[1]);
        assertEq(_percentages[2], percentages[2]);
    }
}
