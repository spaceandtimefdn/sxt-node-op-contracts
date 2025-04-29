// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SXTChainMessaging} from "../src/SXTChainMessaging.sol";

contract SXTChainMessagingTest is Test {
    SXTChainMessaging private messaging;

    event Message(address sender, bytes body, uint248 nonce);

    function setUp() public {
        messaging = new SXTChainMessaging();
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
}
