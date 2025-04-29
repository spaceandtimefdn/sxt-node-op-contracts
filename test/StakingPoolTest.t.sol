// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {StakingPool} from "../src/StakingPool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IStakingPool} from "../src/interfaces/IStakingPool.sol";

contract StakingPoolTest is Test {
    StakingPool private stakingPool;
    MockERC20 private token;
    address private owner;
    address private stakingContract;
    address private nonStakingContract;
    address private staker;

    function setUp() public {
        // Set up accounts
        owner = address(this);
        stakingContract = address(0x1);
        nonStakingContract = address(0x2);
        staker = address(0x3);

        // Create token and mint tokens to stakingPool
        token = new MockERC20();
        // Note: 'ether' here is used as a unit suffix representing 10^18,
        // not the native ETH currency. This follows ERC-20 token convention of 18 decimal places.
        token.mint(owner, 1000 ether);

        // Deploy StakingPool
        stakingPool = new StakingPool(address(token), owner);

        // Transfer tokens to staking pool for use in tests
        token.transfer(address(stakingPool), 500 ether);

        // Add stakingContract to the whitelist in most tests
        stakingPool.addStakingContract(stakingContract);
    }

    function testConstructor() public view {
        // Token address was properly set during constructor
        assertEq(address(stakingPool.TOKEN_ADDRESS()), address(token));
    }

    function testConstructorWithZeroAddress() public {
        vm.expectRevert(StakingPool.InvalidTokenAddress.selector);
        new StakingPool(address(0), owner);
    }

    function testConstructorWithZeroOwnerAddress() public {
        // The error comes from OpenZeppelin's Ownable
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        new StakingPool(address(token), address(0));
    }

    function testStakingTokenSetEvent() public {
        // Use expectEmit to check for the event
        vm.expectEmit(true, false, false, false);
        emit IStakingPool.StakingTokenSet(address(token));

        // Deploy a new StakingPool to trigger the event
        new StakingPool(address(token), owner);
    }

    function testAddStakingContract() public {
        address newStakingContract = address(0x4);
        stakingPool.addStakingContract(newStakingContract);

        // Check if the staking contract was added
        assertTrue(stakingPool._stakingContracts(newStakingContract));
    }

    function testAddStakingContractZeroAddress() public {
        vm.expectRevert(StakingPool.InvalidStakingContract.selector);
        stakingPool.addStakingContract(address(0));
    }

    function testAddStakingContractAlreadyAdded() public {
        vm.expectRevert(StakingPool.StakingContractAlreadyAdded.selector);
        stakingPool.addStakingContract(stakingContract);
    }

    function testAddStakingContractNonOwner() public {
        vm.prank(nonStakingContract);
        vm.expectRevert();
        stakingPool.addStakingContract(address(0x4));
    }

    function testStakingContractAddedEvent() public {
        address newStakingContract = address(0x4);
        vm.expectEmit(true, false, false, false);
        emit IStakingPool.StakingContractAdded(newStakingContract);

        stakingPool.addStakingContract(newStakingContract);
    }

    function testRemoveStakingContract() public {
        stakingPool.removeStakingContract(stakingContract);

        // Check if the staking contract was removed
        assertFalse(stakingPool._stakingContracts(stakingContract));
    }

    function testRemoveStakingContractNotFound() public {
        address nonExistentContract = address(0x5);
        vm.expectRevert(StakingPool.StakingContractNotFound.selector);
        stakingPool.removeStakingContract(nonExistentContract);
    }

    function testRemoveStakingContractNonOwner() public {
        vm.prank(nonStakingContract);
        vm.expectRevert();
        stakingPool.removeStakingContract(stakingContract);
    }

    function testStakingContractRemovedEvent() public {
        vm.expectEmit(true, false, false, false);
        emit IStakingPool.StakingContractRemoved(stakingContract);

        stakingPool.removeStakingContract(stakingContract);
    }

    // Tests for withdraw function
    function testWithdraw() public {
        uint248 withdrawAmount = 50 ether;
        uint256 stakerBalanceBefore = token.balanceOf(staker);
        uint256 poolBalanceBefore = token.balanceOf(address(stakingPool));

        // Call withdraw as the staking contract
        vm.prank(stakingContract);
        stakingPool.withdraw(staker, withdrawAmount);

        // Verify tokens were transferred
        assertEq(token.balanceOf(staker), stakerBalanceBefore + withdrawAmount);
        assertEq(token.balanceOf(address(stakingPool)), poolBalanceBefore - withdrawAmount);
    }

    function testWithdrawInsufficientPoolBalance() public {
        uint248 withdrawAmount = 1000 ether; // More than the pool has

        // Try to withdraw more than the pool has
        vm.prank(stakingContract);
        vm.expectRevert(StakingPool.InsufficientPoolBalance.selector);
        stakingPool.withdraw(staker, withdrawAmount);
    }

    function testWithdrawInvalidAmount() public {
        // Should revert when amount is zero
        vm.prank(stakingContract);
        vm.expectRevert(StakingPool.InvalidWithdrawAmount.selector);
        stakingPool.withdraw(staker, 0);
    }

    function testWithdrawNonStakingContract() public {
        // Should revert when called by a non-staking contract
        vm.prank(nonStakingContract);
        vm.expectRevert(StakingPool.CallerIsNotStakingContract.selector);
        stakingPool.withdraw(staker, 100 ether);
    }

    function testWithdrawInvalidStaker() public {
        // Should revert when staker is the zero address
        vm.prank(stakingContract);
        vm.expectRevert(StakingPool.InvalidStakerAddress.selector);
        stakingPool.withdraw(address(0), 100 ether);
    }

    //------------------//
    // Security Tests   //
    //------------------//

    function testCannotDrainPoolWithoutPermission() public {
        // Setup
        address attacker = address(0xBAADF00D);

        // Try to drain the pool without being a staking contract
        vm.prank(attacker);
        vm.expectRevert(StakingPool.CallerIsNotStakingContract.selector);
        stakingPool.withdraw(attacker, 100 ether);
    }

    function testAmountWithdrawnEvent() public {
        uint248 withdrawAmount = 50 ether;

        vm.expectEmit(true, true, true, true);
        emit IStakingPool.AmountWithdrawn(withdrawAmount, staker, stakingContract);

        vm.prank(stakingContract);
        stakingPool.withdraw(staker, withdrawAmount);
    }
}
