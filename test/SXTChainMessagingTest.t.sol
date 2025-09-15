// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SXTChainMessaging} from "../src/SXTChainMessaging.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SXTChainMessagingTest is Test {
    SXTChainMessaging private messaging;
    MockERC20 private token;

    event Message(address sender, bytes body, uint248 nonce);
    event FundedMessage(address sender, bytes body, uint248 nonce, address target, uint248 amount);

    function setUp() public {
        token = new MockERC20();
        messaging = new SXTChainMessaging(address(token));
    }

    function testMessageNonceIncrement() public {
        // Send first message and capture nonce
        vm.expectEmit(true, true, true, true);
        emit Message(address(this), "first", 1);
        messaging.message("first");

        // Send second message and verify nonce increments
        vm.expectEmit(true, true, true, true);
        emit Message(address(this), "second", 2);
        messaging.message("second");
    }

    function testMessageEmitsCorrectValues() public {
        bytes memory testMessage = "test message";

        vm.expectEmit(true, true, true, true);
        emit Message(address(this), testMessage, 1);

        messaging.message(testMessage);
    }

    function testFuzzSenderAndMessage(address sender, bytes calldata testMessage) public {
        vm.assume(sender != address(0));

        vm.startPrank(sender);
        vm.expectEmit(true, true, true, true);
        emit Message(sender, testMessage, 1);

        messaging.message(testMessage);
        vm.stopPrank();
    }

    function testNonceNeverZero(uint8 numMessages) public {
        // Send multiple messages
        for (uint8 i = 0; i < numMessages; ++i) {
            vm.expectEmit(true, true, true, true);
            emit Message(address(this), "test", uint248(i + 1));
            messaging.message("test");
        }
    }

    function testMessageNoncePerSender() public {
        address sender1 = address(1);
        address sender2 = address(2);

        // First message from sender1
        vm.prank(sender1);
        vm.expectEmit(true, true, true, true);
        emit Message(sender1, "first", 1);
        messaging.message("first");

        // First message from sender2
        vm.prank(sender2);
        vm.expectEmit(true, true, true, true);
        emit Message(sender2, "first", 1);
        messaging.message("first");

        // Second message from sender1
        vm.prank(sender1);
        vm.expectEmit(true, true, true, true);
        emit Message(sender1, "second", 2);
        messaging.message("second");
    }

    function testGetNonceInitialZero() public {
        assertEq(messaging.getNonce(address(this)), 0);
        assertEq(messaging.getNonce(address(0)), 0);
        assertEq(messaging.getNonce(address(1234)), 0);
    }

    function testGetNonceAfterMessage() public {
        messaging.message("test");
        assertEq(messaging.getNonce(address(this)), 1);

        messaging.message("test2");
        assertEq(messaging.getNonce(address(this)), 2);

        // Other addresses should still be zero
        assertEq(messaging.getNonce(address(1234)), 0);
    }

    function testGetNonceMultipleSenders() public {
        address sender1 = address(1);
        address sender2 = address(2);

        vm.prank(sender1);
        messaging.message("test1");
        assertEq(messaging.getNonce(sender1), 1);
        assertEq(messaging.getNonce(sender2), 0);

        vm.prank(sender2);
        messaging.message("test2");
        assertEq(messaging.getNonce(sender1), 1);
        assertEq(messaging.getNonce(sender2), 1);
    }

    function testFundedMessageEmitsCorrectEvent() public {
        address target = address(0x123);
        uint248 amount = 100;
        bytes memory testMessage = "funded test";

        token.mint(address(this), amount);
        token.approve(address(messaging), amount);

        vm.expectEmit(true, true, true, true);
        emit FundedMessage(address(this), testMessage, 1, target, amount);

        messaging.fundedMessage(testMessage, target, amount);
    }

    function testFundedMessageTransfersTokens() public {
        address target = address(0x123);
        uint248 amount = 100;

        token.mint(address(this), amount);
        token.approve(address(messaging), amount);

        uint256 initialSenderBalance = token.balanceOf(address(this));
        uint256 initialTargetBalance = token.balanceOf(target);

        messaging.fundedMessage("test", target, amount);

        assertEq(token.balanceOf(address(this)), initialSenderBalance - amount);
        assertEq(token.balanceOf(target), initialTargetBalance + amount);
    }

    function testFundedMessageIncrementsNonce() public {
        address target = address(0x123);
        uint248 amount = 100;

        token.mint(address(this), amount * 2);
        token.approve(address(messaging), amount * 2);

        assertEq(messaging.getNonce(address(this)), 0);

        messaging.fundedMessage("first", target, amount);
        assertEq(messaging.getNonce(address(this)), 1);

        messaging.fundedMessage("second", target, amount);
        assertEq(messaging.getNonce(address(this)), 2);
    }

    function testFundedMessageNoncePerSender() public {
        address sender1 = address(0x1);
        address sender2 = address(0x2);
        address target = address(0x123);
        uint248 amount = 100;

        token.mint(sender1, amount * 2);
        token.mint(sender2, amount * 2);

        vm.startPrank(sender1);
        token.approve(address(messaging), amount * 2);
        vm.expectEmit(true, true, true, true);
        emit FundedMessage(sender1, "first", 1, target, amount);
        messaging.fundedMessage("first", target, amount);
        vm.stopPrank();

        vm.startPrank(sender2);
        token.approve(address(messaging), amount * 2);
        vm.expectEmit(true, true, true, true);
        emit FundedMessage(sender2, "first", 1, target, amount);
        messaging.fundedMessage("first", target, amount);
        vm.stopPrank();

        vm.prank(sender1);
        vm.expectEmit(true, true, true, true);
        emit FundedMessage(sender1, "second", 2, target, amount);
        messaging.fundedMessage("second", target, amount);

        assertEq(messaging.getNonce(sender1), 2);
        assertEq(messaging.getNonce(sender2), 1);
    }

    function testFundedMessageRevertsInsufficientAllowance() public {
        address target = address(0x123);
        uint248 amount = 100;

        token.mint(address(this), amount);
        token.approve(address(messaging), amount - 1);

        vm.expectRevert();
        messaging.fundedMessage("test", target, amount);
    }

    function testFundedMessageRevertsInsufficientBalance() public {
        address target = address(0x123);
        uint248 amount = 100;

        token.approve(address(messaging), amount);

        vm.expectRevert();
        messaging.fundedMessage("test", target, amount);
    }

    function testFundedMessageWithZeroAmount() public {
        address target = address(0x123);
        uint248 amount = 0;

        vm.expectEmit(true, true, true, true);
        emit FundedMessage(address(this), "zero amount", 1, target, amount);

        messaging.fundedMessage("zero amount", target, amount);

        assertEq(messaging.getNonce(address(this)), 1);
    }

    function testFuzzFundedMessage(address sender, address target, bytes calldata testMessage, uint248 amount) public {
        vm.assume(sender != address(0) && target != address(0) && sender != target);
        vm.assume(amount > 0 && amount < type(uint128).max); // Reasonable amount bounds

        token.mint(sender, amount);

        vm.startPrank(sender);
        token.approve(address(messaging), amount);

        vm.expectEmit(true, true, true, true);
        emit FundedMessage(sender, testMessage, 1, target, amount);

        messaging.fundedMessage(testMessage, target, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(target), amount);
        assertEq(messaging.getNonce(sender), 1);
    }

    function testTokenAddressIsSet() public {
        assertEq(messaging.TOKEN_ADDRESS(), address(token));
    }

    function testConstructorRevertsZeroAddress() public {
        vm.expectRevert(SXTChainMessaging.ZeroAddress.selector);
        new SXTChainMessaging(address(0));
    }
}
