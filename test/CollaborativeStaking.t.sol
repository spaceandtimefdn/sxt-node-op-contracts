// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CollaborativeStaking} from "../src/CollaborativeStaking.sol";
import {MockStaking} from "./mocks/MockStaking.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract CollaborativeStakingTest is Test {
    CollaborativeStaking internal collaborativeStaking;
    MockERC20 internal token;
    MockStaking internal staking;

    address internal admin = address(0x1);
    address internal funder = address(0x2);
    address internal staker = address(0x3);
    address internal beneficiary = address(0x4);

    function setUp() public {
        token = new MockERC20();
        staking = new MockStaking(address(token));

        collaborativeStaking = new CollaborativeStaking(address(token), address(staking), 1 days);
        vm.warp(block.timestamp + 2 days);

        collaborativeStaking.grantRole(collaborativeStaking.DEFAULT_ADMIN_ROLE(), admin);
        collaborativeStaking.grantRole(collaborativeStaking.FUNDER_ROLE(), funder);
        collaborativeStaking.grantRole(collaborativeStaking.STAKER_ROLE(), staker);
        collaborativeStaking.grantRole(collaborativeStaking.BENEFICIARY_ROLE(), beneficiary);

        token.mint(admin, 1_000_000 ether);
        token.mint(funder, 100 ether);
    }

    function testDeposit() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);

        assertEq(collaborativeStaking.totalDeposits(), 50 ether);
        assertEq(collaborativeStaking.funderDeposits(funder), 50 ether);
        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        collaborativeStaking.withdraw(20 ether);

        assertEq(collaborativeStaking.totalDeposits(), 30 ether);
        assertEq(collaborativeStaking.funderDeposits(funder), 30 ether);
        assertEq(token.balanceOf(funder), 70 ether);
        vm.stopPrank();
    }

    function testStake() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        collaborativeStaking.stake();

        assertEq(staking.stakedAmount(), 50 ether);
        vm.stopPrank();
    }

    function testNominate() public {
        bytes32[] memory nodes = new bytes32[](2);
        nodes[0] = keccak256("node1");
        nodes[1] = keccak256("node2");

        vm.startPrank(staker);
        collaborativeStaking.nominate(nodes);
        vm.stopPrank();
    }

    function testInitiateUnstake() public {
        vm.startPrank(staker);
        collaborativeStaking.initiateUnstake(10 ether);
        //assertEq(collaborativeStaking.stakingDelayStartTime, block.timestamp);
        vm.stopPrank();
    }

    function testCancelInitiateUnstake() public {
        vm.startPrank(staker);
        collaborativeStaking.initiateUnstake(10 ether);
        vm.warp(block.timestamp + 1 days);
        collaborativeStaking.cancelInitiateUnstake();
        vm.stopPrank();
    }

    function testClaimUnstake() public {
        vm.startPrank(staker);
        collaborativeStaking.claimUnstake();
        vm.stopPrank();
    }

    function testWithdrawSurplus() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.stopPrank();

        vm.startPrank(admin);
        token.transfer(address(collaborativeStaking), 10 ether);
        vm.stopPrank();

        vm.startPrank(beneficiary);
        collaborativeStaking.withdrawSurplus();

        assertEq(token.balanceOf(beneficiary), 10 ether);
        vm.stopPrank();
    }

    function testWithdrawSurplusRevertsWhenNoSurplus() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.stopPrank();

        vm.startPrank(beneficiary);
        vm.expectRevert(CollaborativeStaking.NoSurplusToWithdraw.selector);
        collaborativeStaking.withdrawSurplus();
        vm.stopPrank();
    }

    function testConstructorRevertsOnZeroTokenAddress() public {
        vm.expectRevert(CollaborativeStaking.ZeroAddress.selector);
        new CollaborativeStaking(address(0), address(staking), 1 days);
    }

    function testConstructorRevertsOnZeroStakingAddress() public {
        vm.expectRevert(CollaborativeStaking.ZeroAddress.selector);
        new CollaborativeStaking(address(token), address(0), 1 days);
    }

    function testConstructorRevertsOnZeroTimelockDelay() public {
        vm.expectRevert(CollaborativeStaking.ZeroAddress.selector);
        new CollaborativeStaking(address(token), address(staking), 0);
    }

    function testStakeRevertsIfTimelockNotExpired() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        collaborativeStaking.initiateUnstake(10 ether);
        vm.expectRevert(CollaborativeStaking.StakingDelayNotExpired.selector);
        collaborativeStaking.stake();
        vm.stopPrank();
    }

    function testDepositRevertsOnZeroAmount() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        vm.expectRevert(CollaborativeStaking.DepositAmountZero.selector);
        collaborativeStaking.deposit(0);
        vm.stopPrank();
    }

    function testWithdrawRevertsOnInsufficientDepositBalance() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.expectRevert(CollaborativeStaking.InsufficientDepositBalance.selector);
        collaborativeStaking.withdraw(60 ether);
        vm.stopPrank();
    }

    function testWithdrawRevertsOnInsufficientContractBalance() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        collaborativeStaking.stake();
        vm.stopPrank();

        vm.startPrank(funder);
        vm.expectRevert(CollaborativeStaking.InsufficientWithdrawableBalance.selector);
        collaborativeStaking.withdraw(50 ether);
        vm.stopPrank();
    }

    function testGetFunderDepositBalance() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.stopPrank();

        uint256 funderBalance = collaborativeStaking.getFunderDepositBalance(funder);
        assertEq(funderBalance, 50 ether);
    }

    function testGetCurrentSurplusWhenNoSurplus() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.stopPrank();

        uint256 surplus = collaborativeStaking.getCurrentSurplus();
        assertEq(surplus, 0);
    }

    function testGetCurrentSurplusWhenSurplusExists() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.stopPrank();

        vm.startPrank(admin);
        token.transfer(address(collaborativeStaking), 10 ether);
        vm.stopPrank();

        uint256 surplus = collaborativeStaking.getCurrentSurplus();
        assertEq(surplus, 10 ether);
    }

    function testGetTotalDepositBalance() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.stopPrank();

        uint256 totalDeposits = collaborativeStaking.getTotalDepositBalance();
        assertEq(totalDeposits, 50 ether);
    }

    function testStakeRevertsOnApprovalFailure() public {
        vm.startPrank(funder);
        token.approve(address(collaborativeStaking), 50 ether);
        collaborativeStaking.deposit(50 ether);
        vm.stopPrank();

        token.setApprovalFailure(true);

        vm.startPrank(staker);
        vm.expectRevert(CollaborativeStaking.TokenApprovalFailed.selector);
        collaborativeStaking.stake();
        vm.stopPrank();
    }

    function testClaimUnstakeResetsStakingDelayStartTime() public {
        // set variable to 1 day
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(staker);
        collaborativeStaking.initiateUnstake(10 ether);
        collaborativeStaking.claimUnstake();
        vm.stopPrank();

        assertEq(collaborativeStaking.stakingDelayStartTime(), 0);
    }
}
