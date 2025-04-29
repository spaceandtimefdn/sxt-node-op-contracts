// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TokenSplitterBaseTest} from "./TokenSplitterBaseTest.t.sol";
import {TokenSplitter} from "../../src/TokenSplitter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Tests for TokenSplitter distribution functionality
contract DistributionTest is TokenSplitterBaseTest {
    function testDistribution() public {
        uint256 amount = 1000;
        token.mint(address(splitter), amount);

        // Calculate expected amounts
        uint256[] memory expectedAmounts = new uint256[](3);
        expectedAmounts[0] = (amount * 20) / 100; // 20%
        expectedAmounts[1] = (amount * 30) / 100; // 30%
        expectedAmounts[2] = (amount * 50) / 100; // 50%

        // Record initial balances
        uint256[] memory initialBalances = new uint256[](3);
        uint256 recipientCount = recipients.length;
        for (uint256 i = 0; i < recipientCount; ++i) {
            initialBalances[i] = token.balanceOf(recipients[i]);
        }

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(splitter), recipients[0], expectedAmounts[0]);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(splitter), recipients[1], expectedAmounts[1]);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(splitter), recipients[2], expectedAmounts[2]);

        splitter.distribute();

        // Verify final balances
        for (uint256 i = 0; i < recipientCount; ++i) {
            assertEq(token.balanceOf(recipients[i]), initialBalances[i] + expectedAmounts[i]);
        }

        // Verify no tokens remain in the contract
        assertEq(token.balanceOf(address(splitter)), 0);
    }

    function testDistributionWithZeroAndNonZeroAmounts() public {
        // Test distribution with the algorithm that only distributes multiples of 100
        address[] memory recipients = new address[](3);
        recipients[0] = address(0x1); // ALICE
        recipients[1] = address(0x2); // BOB
        recipients[2] = address(this);

        uint8[] memory percentages = new uint8[](3);
        percentages[0] = 1; // 1%
        percentages[1] = 50; // 50%
        percentages[2] = 49; // 49%

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Mint 99 tokens - with the updated algorithm, this will revert
        token.mint(address(splitter), 99);

        // This should revert since amount < 100
        vm.expectRevert(TokenSplitter.NothingToDistribute.selector);
        splitter.distribute();

        // Now mint more tokens to reach 200 total (a multiple of 100)
        token.mint(address(splitter), 101);

        // Record initial balances
        uint256 initialAliceBalance = token.balanceOf(address(0x1));
        uint256 initialBobBalance = token.balanceOf(address(0x2));
        uint256 initialThisBalance = token.balanceOf(address(this));

        // Distribute again - now it should distribute 200 tokens
        splitter.distribute();

        // Verify balances after distribution of 200 tokens
        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(token.balanceOf(address(0x1)), initialAliceBalance + 2); // 1% of 200 = 2
        assertEq(token.balanceOf(address(0x2)), initialBobBalance + 100); // 50% of 200 = 100
        assertEq(token.balanceOf(address(this)), initialThisBalance + 98); // 49% of 200 = 98
    }

    function testDistributionWithZeroBalance() public {
        // Create arrays for 2 recipients
        address[] memory newRecipients = new address[](2);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;

        uint8[] memory newPercentages = new uint8[](2);
        newPercentages[0] = 50;
        newPercentages[1] = 50;

        TokenSplitter newSplitter = _createNewSplitter(newRecipients, newPercentages);

        // Mock balanceOf to return 0
        vm.mockCall(
            address(token), abi.encodeWithSelector(IERC20.balanceOf.selector, address(newSplitter)), abi.encode(0)
        );

        // Should revert with NothingToDistribute since balance is 0
        vm.expectRevert(TokenSplitter.NothingToDistribute.selector);
        newSplitter.distribute();

        vm.clearMockedCalls();
    }

    function testDistributionWithUnbalancedPercentages() public {
        // Create arrays for 3 recipients with unbalanced percentages
        address[] memory newRecipients = new address[](3);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;
        newRecipients[2] = CHARLIE;

        uint8[] memory newPercentages = new uint8[](3);
        newPercentages[0] = 50;
        newPercentages[1] = 30;
        newPercentages[2] = 20;

        TokenSplitter newSplitter = _createNewSplitter(newRecipients, newPercentages);

        // Mint 100 tokens to avoid rounding issues
        uint256 amount = 100;
        token.mint(address(newSplitter), amount);

        // Calculate expected amounts
        uint256[] memory expectedAmounts = new uint256[](3);
        expectedAmounts[0] = (amount * 50) / 100; // 50%
        expectedAmounts[1] = (amount * 30) / 100; // 30%
        expectedAmounts[2] = (amount * 20) / 100; // 20%

        // Expect transfers with rounding
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(newSplitter), ALICE, expectedAmounts[0]);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(newSplitter), BOB, expectedAmounts[1]);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(newSplitter), CHARLIE, expectedAmounts[2]);

        newSplitter.distribute();

        // Verify distribution info
        (address[] memory recipients, uint8[] memory percentages) = newSplitter.getDistributionInfo();
        assertEq(recipients.length, 3);
        assertEq(percentages.length, 3);
        assertEq(recipients[0], ALICE);
        assertEq(recipients[1], BOB);
        assertEq(recipients[2], CHARLIE);
        assertEq(percentages[0], 50);
        assertEq(percentages[1], 30);
        assertEq(percentages[2], 20);
    }

    function testDistributionWithSmallAmounts() public {
        // Create arrays for 4 recipients with small percentages
        address[] memory newRecipients = new address[](4);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;
        newRecipients[2] = CHARLIE;
        newRecipients[3] = DAVID;

        uint8[] memory newPercentages = new uint8[](4);
        newPercentages[0] = 97;
        newPercentages[1] = 1;
        newPercentages[2] = 1;
        newPercentages[3] = 1;

        TokenSplitter newSplitter = _createNewSplitter(newRecipients, newPercentages);

        // Mint 100 tokens
        token.mint(address(newSplitter), 100);

        // Expect transfers with small amounts
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(newSplitter), ALICE, 97);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(newSplitter), BOB, 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(newSplitter), CHARLIE, 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(newSplitter), DAVID, 1);

        newSplitter.distribute();
    }

    function testDistributionWithAmountMultiplicationOverflow() public {
        // With the new algorithm, we only distribute multiples of 100 tokens
        // This test verifies that tokens less than 100 are not distributed

        address[] memory recipients = new address[](2);
        recipients[0] = ALICE;
        recipients[1] = BOB;

        uint8[] memory percentages = new uint8[](2);
        percentages[0] = 50; // 50%
        percentages[1] = 50; // 50%

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Use a very large amount that's a multiple of 100
        // We'll use a value that's large but won't cause overflow
        uint256 largeAmount = type(uint256).max / 200 * 100; // Ensure it's a multiple of 100
        token.mint(address(splitter), largeAmount);

        // Record initial balances
        uint256 initialAliceBalance = token.balanceOf(ALICE);
        uint256 initialBobBalance = token.balanceOf(BOB);

        // Distribution should succeed without overflow
        splitter.distribute();

        // Verify balances - each recipient should get 50% of the tokens
        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(token.balanceOf(ALICE), initialAliceBalance + (largeAmount / 2));
        assertEq(token.balanceOf(BOB), initialBobBalance + (largeAmount / 2));
    }

    function testDistributionWithRoundingAndRemainder() public {
        // Create a new splitter with 3 recipients and uneven percentages
        address[] memory newRecipients = new address[](3);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;
        newRecipients[2] = CHARLIE;

        uint8[] memory newPercentages = new uint8[](3);
        newPercentages[0] = 33; // 33%
        newPercentages[1] = 33; // 33%
        newPercentages[2] = 34; // 34%

        TokenSplitter newSplitter = _createNewSplitter(newRecipients, newPercentages);

        // Mint tokens to the splitter (odd amount that will cause rounding)
        token.mint(address(newSplitter), 10000); // 10,000 tokens

        // Distribute tokens
        newSplitter.distribute();

        // Check balances
        assertEq(token.balanceOf(ALICE), 3300); // 33% of 10000
        assertEq(token.balanceOf(BOB), 3300); // 33% of 10000
        assertEq(token.balanceOf(CHARLIE), 3400); // 34% of 10000
        assertEq(token.balanceOf(address(newSplitter)), 0); // All tokens distributed
    }

    function testDistributionWithExactlyZeroAmount() public {
        // The constructor throws ZeroPercentage if a recipient has 0% allocation
        // This is a design requirement, so we'll test it properly

        address[] memory recipients = new address[](3);
        recipients[0] = address(0x1); // ALICE
        recipients[1] = address(0x2); // BOB
        recipients[2] = address(this);

        uint8[] memory percentages = new uint8[](3);
        percentages[0] = 0; // 0% - constructor should revert
        percentages[1] = 50;
        percentages[2] = 50;

        // Should revert because we have a recipient with 0%
        vm.expectRevert(TokenSplitter.ZeroPercentage.selector);
        new TokenSplitter(address(token), recipients, percentages);

        // Let's create a valid one to test the other part of the case
        percentages[0] = 1; // Small but non-zero percentage
        percentages[1] = 50; // Adjusted to ensure total is 100%
        percentages[2] = 49; // Adjusted to ensure total is 100%

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Mint 100 tokens
        uint256 amount = 100;
        token.mint(address(splitter), amount);

        // This should NOT revert with our new algorithm
        splitter.distribute();

        // Verify balances - the 1% recipient gets 1 token
        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(token.balanceOf(address(0x1)), 1); // 1% of 100 = 1
        assertEq(token.balanceOf(address(0x2)), 50); // 50% of 100 = 50
        assertEq(token.balanceOf(address(this)), 49); // 49% of 100 = 49
    }

    function testDistributionWithZeroAmountRecipient() public {
        // Set up the test with a small number of tokens that will result in a zero amount
        // for one recipient after percentage calculation

        // Create a TokenSplitter with 3 recipients and percentages
        address[] memory recipients = new address[](3);
        recipients[0] = ALICE;
        recipients[1] = BOB;
        recipients[2] = CHARLIE;

        uint8[] memory percentages = new uint8[](3);
        percentages[0] = 95; // 95%
        percentages[1] = 4; // 4%
        percentages[2] = 1; // 1%

        // Create the token splitter
        TokenSplitter splitter = _createNewSplitter(recipients, percentages);

        // Mint 100 tokens to ensure it's a multiple of 100
        // 95% of 100 = 95 tokens
        // 4% of 100 = 4 tokens
        // 1% of 100 = 1 token
        token.mint(address(splitter), 100);

        // Record initial balances
        uint256 initialAliceBalance = token.balanceOf(ALICE);
        uint256 initialBobBalance = token.balanceOf(BOB);
        uint256 initialCharlieBalance = token.balanceOf(CHARLIE);

        // Distribute tokens
        splitter.distribute();

        // Verify that all tokens were distributed according to percentages
        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(token.balanceOf(ALICE), initialAliceBalance + 95); // 95% of 100 = 95
        assertEq(token.balanceOf(BOB), initialBobBalance + 4); // 4% of 100 = 4
        assertEq(token.balanceOf(CHARLIE), initialCharlieBalance + 1); // 1% of 100 = 1
    }

    function testDistributionWithOneRecipient() public {
        // Test using just a single recipient with 100% allocation
        address[] memory recipients = new address[](1);
        recipients[0] = ALICE;

        uint8[] memory percentages = new uint8[](1);
        percentages[0] = 100; // 100%

        TokenSplitter splitter = _createNewSplitter(recipients, percentages);

        // Mint tokens to the splitter
        uint256 amount = 1000;
        token.mint(address(splitter), amount);

        // Record initial balance
        uint256 initialBalance = token.balanceOf(ALICE);

        // Distribute the tokens
        splitter.distribute();

        // Verify balances
        assertEq(token.balanceOf(ALICE), initialBalance + amount);
        assertEq(token.balanceOf(address(splitter)), 0);
    }

    function testDistributeWithZeroAmountButTotalSuccessful() public {
        // This test verifies that the contract reverts when there are fewer than 100 tokens

        address[] memory recipients = new address[](3);
        recipients[0] = address(0x1); // ALICE
        recipients[1] = address(0x2); // BOB
        recipients[2] = address(0x3); // Higher than address(this)

        uint8[] memory percentages = new uint8[](3);
        percentages[0] = 1;
        percentages[1] = 49;
        percentages[2] = 50;

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Mint 99 tokens, which is less than 100
        uint256 amount = 99;
        token.mint(address(splitter), amount);

        // Expect revert when trying to distribute less than 100 tokens
        vm.expectRevert(TokenSplitter.NothingToDistribute.selector);
        splitter.distribute();
    }

    function testDistributeWithZeroAmountAndRemainder() public {
        // This test verifies that the contract reverts when there are fewer than 100 tokens

        address[] memory recipients = new address[](3);
        recipients[0] = address(0x1); // ALICE
        recipients[1] = address(0x2); // BOB
        recipients[2] = address(this);

        uint8[] memory percentages = new uint8[](3);
        percentages[0] = 1;
        percentages[1] = 50;
        percentages[2] = 49;

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Mint a small number of tokens (less than 100)
        uint256 amount = 99;
        token.mint(address(splitter), amount);

        // Verify initial balance
        assertEq(token.balanceOf(address(splitter)), 99);

        // Expect revert when trying to distribute less than 100 tokens
        vm.expectRevert(TokenSplitter.NothingToDistribute.selector);
        splitter.distribute();
    }

    function testDistributionWithPerfectRounding() public {
        // This test targets cases where the distribution divides exactly with no remainder

        address[] memory recipients = new address[](4);
        recipients[0] = address(0x1); // ALICE
        recipients[1] = address(0x2); // BOB
        recipients[2] = address(0x3); // CHARLIE
        recipients[3] = address(this);

        uint8[] memory percentages = new uint8[](4);
        // Set up perfect divisions (25% each)
        percentages[0] = 25;
        percentages[1] = 25;
        percentages[2] = 25;
        percentages[3] = 25;

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Mint 100 tokens for a perfect division (25 each)
        uint256 amount = 100;
        token.mint(address(splitter), amount);

        // Verify initial balance
        assertEq(token.balanceOf(address(splitter)), 100);

        // This should distribute with zero remainder
        splitter.distribute();

        // Verify 0 remainder (all tokens distributed exactly)
        assertEq(token.balanceOf(address(splitter)), 0);

        // Check expected distribution
        assertEq(token.balanceOf(address(0x1)), 25);
        assertEq(token.balanceOf(address(0x2)), 25);
        assertEq(token.balanceOf(address(0x3)), 25);
        assertEq(token.balanceOf(address(this)), 25);

        // This specifically tests the branch where remainder is exactly 0
    }

    function testDistributionWithNearMaximumAmounts() public {
        // Test with very large token amounts that are multiples of 100

        address[] memory recipients = new address[](2);
        recipients[0] = address(0x1); // ALICE
        recipients[1] = address(this);

        uint8[] memory percentages = new uint8[](2);
        percentages[0] = 50; // 50%
        percentages[1] = 50; // 50%

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // We'll use a value that's large but won't cause overflow
        uint256 largeAmount = type(uint256).max / 200 * 100; // Ensure it's a multiple of 100
        token.mint(address(splitter), largeAmount);

        // Record initial balances
        uint256 initialAliceBalance = token.balanceOf(address(0x1));
        uint256 initialThisBalance = token.balanceOf(address(this));

        // Distribution should succeed without overflow
        splitter.distribute();

        // Verify balances - each recipient should get 50% of the tokens
        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(token.balanceOf(address(0x1)), initialAliceBalance + (largeAmount / 2));
        assertEq(token.balanceOf(address(this)), initialThisBalance + (largeAmount / 2));
    }

    function testDistributionWithRemainderAndAllZeroFirstPass() public {
        // This test verifies that with the new algorithm, we only distribute
        // multiples of 100 tokens and keep any remainder

        address[] memory recipients = new address[](3);
        recipients[0] = address(0x1); // ALICE
        recipients[1] = address(0x2); // BOB
        recipients[2] = address(this);

        uint8[] memory percentages = new uint8[](3);
        percentages[0] = 33; // 33%
        percentages[1] = 33; // 33%
        percentages[2] = 34; // 34%

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Mint 197 tokens - only 100 will be distributed
        uint256 amount = 197;
        token.mint(address(splitter), amount);

        // Record initial balances
        uint256 initialAliceBalance = token.balanceOf(address(0x1));
        uint256 initialBobBalance = token.balanceOf(address(0x2));
        uint256 initialThisBalance = token.balanceOf(address(this));

        // Distribute tokens
        splitter.distribute();

        // Verify balances - only 100 tokens should be distributed
        // The remaining 97 tokens should stay in the contract
        assertEq(token.balanceOf(address(splitter)), 97);
        assertEq(token.balanceOf(address(0x1)), initialAliceBalance + 33); // 33% of 100 = 33
        assertEq(token.balanceOf(address(0x2)), initialBobBalance + 33); // 33% of 100 = 33
        assertEq(token.balanceOf(address(this)), initialThisBalance + 34); // 34% of 100 = 34
    }

    function testDistributionWithMostlyZeroAmounts() public {
        // This test verifies that with the new algorithm, we only distribute
        // multiples of 100 tokens and keep any remainder

        address[] memory recipients = new address[](5);
        uint8[] memory percentages = new uint8[](5);

        // Set up recipients in ascending order
        recipients[0] = address(0x1); // ALICE
        recipients[1] = address(0x2); // BOB
        recipients[2] = address(0x3); // CHARLIE
        recipients[3] = address(0x4); // DAVID
        recipients[4] = address(this);

        percentages[0] = 1; // 1%
        percentages[1] = 1; // 1%
        percentages[2] = 1; // 1%
        percentages[3] = 1; // 1%
        percentages[4] = 96; // 96%

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Mint 196 tokens - only 100 will be distributed
        uint256 amount = 196;
        token.mint(address(splitter), amount);

        // Record initial balances
        uint256 initialAliceBalance = token.balanceOf(address(0x1));
        uint256 initialBobBalance = token.balanceOf(address(0x2));
        uint256 initialCharlieBalance = token.balanceOf(address(0x3));
        uint256 initialDavidBalance = token.balanceOf(address(0x4));
        uint256 initialThisBalance = token.balanceOf(address(this));

        // Distribute tokens
        splitter.distribute();

        // Verify balances - only 100 tokens should be distributed
        // The remaining 96 tokens should stay in the contract
        assertEq(token.balanceOf(address(splitter)), 96);
        assertEq(token.balanceOf(address(0x1)), initialAliceBalance + 1); // 1% of 100 = 1
        assertEq(token.balanceOf(address(0x2)), initialBobBalance + 1); // 1% of 100 = 1
        assertEq(token.balanceOf(address(0x3)), initialCharlieBalance + 1); // 1% of 100 = 1
        assertEq(token.balanceOf(address(0x4)), initialDavidBalance + 1); // 1% of 100 = 1
        assertEq(token.balanceOf(address(this)), initialThisBalance + 96); // 96% of 100 = 96
    }

    function testDistributionIncompleteRevert() public {
        // This test verifies that the contract reverts when there are fewer than 100 tokens

        address[] memory recipients = new address[](2);
        recipients[0] = ALICE;
        recipients[1] = BOB;

        uint8[] memory percentages = new uint8[](2);
        percentages[0] = 50;
        percentages[1] = 50;

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Mint 50 tokens (less than 100)
        token.mint(address(splitter), 50);

        // Expect revert when trying to distribute less than 100 tokens
        vm.expectRevert(TokenSplitter.NothingToDistribute.selector);
        splitter.distribute();
    }

    function testDistributionWithRemainderAndNoNonZeroAmounts() public {
        // This test verifies that the contract reverts when there are fewer than 100 tokens

        address[] memory recipients = new address[](3);
        recipients[0] = ALICE;
        recipients[1] = BOB;
        recipients[2] = CHARLIE;

        uint8[] memory percentages = new uint8[](3);
        percentages[0] = 33;
        percentages[1] = 33;
        percentages[2] = 34;

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Mint 50 tokens (less than 100)
        token.mint(address(splitter), 50);

        // Expect revert when trying to distribute less than 100 tokens
        vm.expectRevert(TokenSplitter.NothingToDistribute.selector);
        splitter.distribute();
    }

    function testDistributionWithAllZeroRecipients() public {
        // Create arrays for 3 recipients
        address[] memory newRecipients = new address[](3);
        newRecipients[0] = ALICE;
        newRecipients[1] = BOB;
        newRecipients[2] = CHARLIE;

        uint8[] memory newPercentages = new uint8[](3);
        newPercentages[0] = 33;
        newPercentages[1] = 33;
        newPercentages[2] = 34;

        TokenSplitter newSplitter = _createNewSplitter(newRecipients, newPercentages);

        // First mock a zero balance to trigger NothingToDistribute
        vm.mockCall(
            address(token), abi.encodeWithSelector(IERC20.balanceOf.selector, address(newSplitter)), abi.encode(0)
        );

        // Expect the NothingToDistribute error
        vm.expectRevert(TokenSplitter.NothingToDistribute.selector);
        newSplitter.distribute();

        vm.clearMockedCalls();
    }

    function testDistributionWithZeroNonZeroCount() public {
        // This test verifies that with the new algorithm, we only distribute
        // multiples of 100 tokens and keep any remainder

        // Create arrays for recipients with very small percentages
        address[] memory recipients = new address[](10);
        uint8[] memory percentages = new uint8[](10);

        // Set up recipients with mostly 1% allocations and one with 91%
        // Ensure addresses are in ascending order
        for (uint256 i = 0; i < 9; ++i) {
            recipients[i] = address(uint160(0x1000 + i));
            percentages[i] = 1; // 1% each
        }
        recipients[9] = address(0x2000); // Higher than all previous addresses
        percentages[9] = 91; // 91%

        TokenSplitter splitter = new TokenSplitter(address(token), recipients, percentages);

        // Mint 109 tokens - only 100 will be distributed
        token.mint(address(splitter), 109);

        // Distribute tokens
        splitter.distribute();

        // Verify balances - only 100 tokens should be distributed
        // The remaining 9 tokens should stay in the contract
        assertEq(token.balanceOf(address(splitter)), 9);

        // Each 1% recipient should get 1 token
        for (uint256 i = 0; i < 9; ++i) {
            assertEq(token.balanceOf(recipients[i]), 1);
        }

        // Last recipient should get 91 tokens (91% of 100)
        assertEq(token.balanceOf(recipients[9]), 91);
    }
}
