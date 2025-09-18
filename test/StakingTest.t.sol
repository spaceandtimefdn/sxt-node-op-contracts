// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Staking} from "../src/Staking.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {StakingPool} from "../src/StakingPool.sol";
import {IStaking} from "../src/interfaces/IStaking.sol";
import {SubstrateSignatureValidator} from "../src/SubstrateSignatureValidator.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract StakingTest is Test {
    Staking private staking;
    MockERC20 private token;
    StakingPool private stakingPool;
    uint64 private unstakingUnbondingPeriod = 100;
    address private substrateSignatureValidatorAddress;

    uint256[] private attestorsPrivateKeys;
    address[] private attestors;

    function setUp() public {
        token = new MockERC20();
        token.mint(address(this), 1000e18);

        stakingPool = new StakingPool(address(token), address(this));

        attestorsPrivateKeys = new uint256[](2);
        attestorsPrivateKeys[0] = 0x02;
        attestorsPrivateKeys[1] = 0x03;
        attestors = new address[](2);
        for (uint256 i = 0; i < 2; ++i) {
            attestors[i] = vm.addr(attestorsPrivateKeys[i]);
        }

        if (attestors[0] > attestors[1]) {
            address tempAddress = attestors[0];
            uint256 tempPrivateKey = attestorsPrivateKeys[0];
            attestors[0] = attestors[1];
            attestorsPrivateKeys[0] = attestorsPrivateKeys[1];
            attestors[1] = tempAddress;
            attestorsPrivateKeys[1] = tempPrivateKey;
        }

        uint16 threshold = 2;

        substrateSignatureValidatorAddress = address(new SubstrateSignatureValidator(attestors, threshold));
        staking = new Staking(
            address(token), address(stakingPool), unstakingUnbondingPeriod, substrateSignatureValidatorAddress
        );

        // Add staking contract to stakingPool whitelist
        stakingPool.addStakingContract(address(staking));

        staking.unpauseUnstaking();
    }

    function testTokenAddressZeroAddress() public {
        vm.expectRevert(Staking.ZeroAddress.selector);
        new Staking(address(0), address(stakingPool), unstakingUnbondingPeriod, substrateSignatureValidatorAddress);
    }

    function testStakingPoolZeroAddress() public {
        vm.expectRevert(Staking.ZeroAddress.selector);
        new Staking(address(0x123), address(0), unstakingUnbondingPeriod, substrateSignatureValidatorAddress);
    }

    function testSubstrateSignatureValidatorZeroAddress() public {
        vm.expectRevert(Staking.ZeroAddress.selector);
        new Staking(address(token), address(stakingPool), unstakingUnbondingPeriod, address(0));
    }

    function testStakingZeroAmount() public {
        vm.expectRevert(Staking.StakingZeroAmount.selector);
        staking.stake(0);
    }

    function testUnbondingPeriodZero() public {
        vm.expectRevert(Staking.UnbondingPeriodZero.selector);
        new Staking(address(token), address(stakingPool), 0, substrateSignatureValidatorAddress);
    }

    function testStake() public {
        uint248 amount = 1000e18;
        token.approve(address(staking), amount);

        vm.expectEmit(true, true, true, true);
        emit IStaking.Staked(address(this), amount);

        staking.stake(amount);
        assertEq(token.balanceOf(address(stakingPool)), amount);

        // Verify state is Staked (timestamp is 0 in Staked state)
        assertEq(staking.initiateUnstakeRequestsTimestamp(address(this)), 0);
    }

    function testCancelInitiateUnstakeWhenStaking() public {
        uint248 amount = 1000e18;
        token.mint(address(this), amount * 2);

        token.approve(address(staking), amount);

        // First initiate a stake to enter Staked state
        staking.stake(amount);

        // Verify we're in Staked state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.Staked));

        // Now initiate unstake to enter UnstakeInitiated state
        staking.initiateUnstake(amount);

        // Verify we've moved to UnstakeInitiated state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.UnstakeInitiated));

        // Store the timestamp to verify it gets reset
        uint64 unstakeTimestamp = staking.initiateUnstakeRequestsTimestamp(address(this));
        assertTrue(unstakeTimestamp > 0, "Unstake timestamp should be set");

        // Now apply for more stake, which should cancel the unstake
        token.approve(address(staking), amount);
        vm.expectEmit(true, true, true, true);
        emit IStaking.InitiateUnstakeCancelled(address(this));
        staking.stake(amount);

        // Verify that the unstake was cancelled
        assertEq(staking.initiateUnstakeRequestsTimestamp(address(this)), 0, "Timestamp should be reset");
        assertEq(
            uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.Staked), "Should be Staked state"
        );
    }

    function testFuzzStake(uint248 amount) public {
        token.approve(address(staking), amount);

        if (amount == 0) {
            vm.expectRevert(Staking.StakingZeroAmount.selector);
            staking.stake(amount);
        } else if (amount < staking.MIN_STAKING_AMOUNT()) {
            vm.expectRevert(Staking.StakingBelowMinAmount.selector);
            staking.stake(amount);
        } else {
            token.mint(address(this), amount);
            token.approve(address(staking), amount);

            vm.expectEmit(true, true, true, true);
            emit IStaking.Staked(address(this), amount);
            staking.stake(amount);
            assertEq(token.balanceOf(address(stakingPool)), amount);

            // Verify state is Staked (timestamp is 0)
            assertEq(staking.initiateUnstakeRequestsTimestamp(address(this)), 0);
        }
    }

    function testNominateEmptyNodesList() public {
        vm.expectRevert(Staking.EmptyNodesList.selector);
        staking.nominate(new bytes32[](0));
    }

    function testNominateInvalidNodeEd25519PubKey() public {
        vm.expectRevert(Staking.InvalidNodeEd25519PubKey.selector);
        staking.nominate(new bytes32[](1));
    }

    function testNominateDuplicateNodeEd25519PubKey() public {
        vm.expectRevert(Staking.DuplicateNodeEd25519PubKey.selector);
        bytes32[] memory ed25519PubKeys = new bytes32[](2);
        ed25519PubKeys[0] = bytes32(uint256(1));
        ed25519PubKeys[1] = bytes32(uint256(1));
        staking.nominate(ed25519PubKeys);
    }

    function testNominateValidSingleNode() public {
        bytes32[] memory nodes = new bytes32[](1);
        nodes[0] = bytes32(uint256(1));

        vm.expectEmit(true, true, true, true);
        emit IStaking.Nominated(nodes, address(this));
        staking.nominate(nodes);
    }

    function testNominateValidSortedNodes() public {
        bytes32[] memory nodes = new bytes32[](3);
        nodes[0] = bytes32(uint256(1));
        nodes[1] = bytes32(uint256(2));
        nodes[2] = bytes32(uint256(3));

        vm.expectEmit(true, true, true, true);
        emit IStaking.Nominated(nodes, address(this));
        staking.nominate(nodes);
    }

    function testFuzzNominate(bytes32[] memory nodes) public {
        if (nodes.length == 0) {
            vm.expectRevert(Staking.EmptyNodesList.selector);
            staking.nominate(nodes);
        } else if (nodes[0] == bytes32(0)) {
            vm.expectRevert(Staking.InvalidNodeEd25519PubKey.selector);
            staking.nominate(nodes);
        } else if (nodes.length > 1) {
            uint256 nodesLength = nodes.length;
            for (uint256 i = 1; i < nodesLength; ++i) {
                // solhint-disable-next-line gas-strict-inequalities
                if (nodes[i] <= nodes[i - 1]) {
                    vm.expectRevert(Staking.DuplicateNodeEd25519PubKey.selector);
                    staking.nominate(nodes);
                }
            }
        } else {
            vm.expectEmit(true, true, true, true);
            emit IStaking.Nominated(nodes, address(this));

            staking.nominate(nodes);
        }
    }

    function testStakingBelowMinAmount() public {
        uint248 minStakingAmount = staking.MIN_STAKING_AMOUNT();
        vm.expectRevert(Staking.StakingBelowMinAmount.selector);
        staking.stake(minStakingAmount - 1);
    }

    function testInitiateUnstake() public {
        address staker = address(0x02);

        // First set up the staker with an initial stake to enter Staked state
        uint248 amount = 1000e18;
        token.mint(staker, amount);
        vm.startPrank(staker);
        token.approve(address(staking), amount);
        staking.stake(amount);

        // Verify we're in Staked state
        assertEq(uint8(staking.stakerState(staker)), uint8(IStaking.StakerState.Staked));

        // Now test initiateUnstake
        vm.expectEmit(true, true, true, true);
        emit IStaking.UnstakeInitiated(staker, amount);
        staking.initiateUnstake(amount);
        vm.stopPrank();

        // Verify final state
        assertEq(uint8(staking.stakerState(staker)), uint8(IStaking.StakerState.UnstakeInitiated));
    }

    function testInitiateUnstakeTwice() public {
        uint248 amount = 1000e18;
        token.mint(address(this), amount);
        token.approve(address(staking), amount);
        staking.stake(amount);

        // Verify we're in Staked state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.Staked));

        staking.initiateUnstake(amount);

        // Now expecting InvalidStakerState instead of UnstakeAlreadyInitiated
        vm.expectRevert(
            abi.encodeWithSelector(
                Staking.InvalidStakerState.selector, IStaking.StakerState.UnstakeInitiated, IStaking.StakerState.Staked
            )
        );
        staking.initiateUnstake(amount);
    }

    function testCancelInitiateUnstake() public {
        uint248 amount = 1000e18;
        token.mint(address(this), amount);
        token.approve(address(staking), amount);
        staking.stake(amount);

        // Verify we're in Staked state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.Staked));

        // initiate unstake
        staking.initiateUnstake(amount);

        // Verify we're in UnstakeInitiated state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.UnstakeInitiated));

        vm.expectEmit(true, true, true, true);
        emit IStaking.InitiateUnstakeCancelled(address(this));
        staking.cancelInitiateUnstake();

        // Verify we're back in Staked state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.Staked));
    }

    function testCancelInitiateUnstakeRevertsInitiateUnstakeNotFound() public {
        // Now expecting InvalidStakerState instead of InitiateUnstakeNotFound
        vm.expectRevert(
            abi.encodeWithSelector(
                Staking.InvalidStakerState.selector,
                IStaking.StakerState.Unstaked,
                IStaking.StakerState.UnstakeInitiated
            )
        );
        staking.cancelInitiateUnstake();
    }

    function testClaimUnstakeRevertsInitiateUnstakeNotFound() public {
        // Now expecting InvalidStakerState instead of InitiateUnstakeNotFound
        vm.expectRevert(
            abi.encodeWithSelector(
                Staking.InvalidStakerState.selector,
                IStaking.StakerState.Unstaked,
                IStaking.StakerState.UnstakeInitiated
            )
        );
        staking.claimUnstake();
    }

    function testClaimUnstakeRevertsUnstakeNotUnbonded() public {
        uint248 amount = 1000e18;
        token.mint(address(this), amount);
        token.approve(address(staking), amount);
        staking.stake(amount);

        staking.initiateUnstake(amount);

        // Verify we're in UnstakeInitiated state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.UnstakeInitiated));

        vm.expectRevert(Staking.UnstakeNotUnbonded.selector);
        staking.claimUnstake();
    }

    function testClaimUnstake() public {
        uint248 amount = 1000e18;
        token.mint(address(this), amount);
        token.approve(address(staking), amount);
        staking.stake(amount);

        staking.initiateUnstake(amount);

        // Verify we're in UnstakeInitiated state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.UnstakeInitiated));

        vm.warp(block.timestamp + unstakingUnbondingPeriod);
        vm.expectEmit(true, true, true, true);
        emit IStaking.UnstakeClaimed(address(this));
        staking.claimUnstake();

        // Verify we're in UnstakeClaimed state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.UnstakeClaimed));
    }

    function testSxtFulfillUnstake() public {
        // stake
        uint248 amount = 1000e18;
        token.mint(address(this), amount);
        token.approve(address(staking), amount);
        staking.stake(amount);

        // Verify we're in Staked state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.Staked));

        // initiate unstake
        staking.initiateUnstake(amount);

        // Verify we're in UnstakeInitiated state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.UnstakeInitiated));

        vm.warp(block.timestamp + unstakingUnbondingPeriod);

        // claim unstake
        staking.claimUnstake();

        // Verify we're in UnstakeClaimed state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.UnstakeClaimed));

        // fulfill unstake
        // Note: In a real system, generateProof would use staker and amount to create a valid proof
        bytes32[] memory proof = generateProof();

        address staker = address(this);
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encodePacked(uint256(uint160(staker)), amount, block.chainid, address(staking))))
        );

        bytes32 rootHash = MerkleProof.processProof(proof, leaf);
        uint64 sxtBlockNumber = 20;
        bytes memory messageBody = abi.encodePacked(rootHash, sxtBlockNumber);
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(messageBody.length), messageBody)
        );

        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);
        uint8[] memory v = new uint8[](2);
        for (uint256 i = 0; i < 2; ++i) {
            (v[i], r[i], s[i]) = vm.sign(attestorsPrivateKeys[i], messageHash);
        }

        // Mint tokens to the staking pool for withdrawal
        token.mint(address(stakingPool), amount);

        vm.expectEmit(true, true, true, true);
        emit IStaking.Unstaked(staker, amount);
        staking.sxtFulfillUnstake(staker, amount, sxtBlockNumber, proof, r, s, v);

        // Verify we're back to Unstaked state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.Unstaked));

        // After fulfilling unstake, we need to stake again and run through the process
        // to test the InvalidSxtBlockNumber case
        token.mint(address(this), amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.initiateUnstake(amount);
        vm.warp(block.timestamp + unstakingUnbondingPeriod);
        staking.claimUnstake();

        // Now attempt with the same block number
        vm.expectRevert(Staking.InvalidSxtBlockNumber.selector);
        staking.sxtFulfillUnstake(staker, amount, sxtBlockNumber, proof, r, s, v);
    }

    function testSxtFulfillUnstakeWithTwoContractsFails() public {
        Staking staking2 = new Staking(
            address(token), address(stakingPool), unstakingUnbondingPeriod, substrateSignatureValidatorAddress
        );
        stakingPool.addStakingContract(address(staking2));
        staking2.unpauseUnstaking();

        uint248 amount = 1000e18;
        token.mint(address(this), amount * 2);
        token.approve(address(staking), amount);
        token.approve(address(staking2), amount / 2);
        staking.stake(amount);
        staking2.stake(amount / 2);
        staking.initiateUnstake(amount);
        staking2.initiateUnstake(amount);
        vm.warp(block.timestamp + unstakingUnbondingPeriod);
        staking.claimUnstake();
        staking2.claimUnstake();

        bytes32[] memory proof = generateProof();
        address staker = address(this);
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encodePacked(uint256(uint160(staker)), amount, block.chainid, address(staking))))
        );

        bytes32 rootHash = MerkleProof.processProof(proof, leaf);
        uint64 sxtBlockNumber = 20;
        bytes memory messageBody = abi.encodePacked(rootHash, sxtBlockNumber);
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(messageBody.length), messageBody)
        );

        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);
        uint8[] memory v = new uint8[](2);
        for (uint256 i = 0; i < 2; ++i) {
            (v[i], r[i], s[i]) = vm.sign(attestorsPrivateKeys[i], messageHash);
        }

        // Mint tokens to the staking pool for withdrawal
        token.mint(address(stakingPool), amount);

        vm.expectEmit(true, true, true, true);
        emit IStaking.Unstaked(staker, amount);
        staking.sxtFulfillUnstake(staker, amount, sxtBlockNumber, proof, r, s, v);

        vm.expectRevert(Staking.InvalidSignature.selector);
        staking2.sxtFulfillUnstake(staker, amount, sxtBlockNumber, proof, r, s, v);
    }

    function testSxtFulfillUnstakeInitiateUnstakeNotFound() public {
        address staker = address(0x02);
        uint248 amount = 1000e18;
        // Note: In a real system, generateProof would use staker and amount to create a valid proof
        bytes32[] memory proof = generateProof();
        uint64 sxtBlockNumber = 20;

        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);
        uint8[] memory v = new uint8[](2);
        for (uint256 i = 0; i < 2; ++i) {
            (v[i], r[i], s[i]) = (27, bytes32(uint256(1)), bytes32(uint256(1)));
        }

        // Now expecting InvalidStakerState instead of InitiateUnstakeNotFound
        vm.expectRevert(
            abi.encodeWithSelector(
                Staking.InvalidStakerState.selector, IStaking.StakerState.Unstaked, IStaking.StakerState.UnstakeClaimed
            )
        );
        staking.sxtFulfillUnstake(staker, amount, sxtBlockNumber, proof, r, s, v);
    }

    function testSxtFulfillUnstakeInvalidSignature() public {
        uint248 amount = 1000e18;
        token.mint(address(this), amount);
        token.approve(address(staking), amount);
        staking.stake(amount);

        staking.initiateUnstake(amount);
        vm.warp(block.timestamp + unstakingUnbondingPeriod + 1);
        staking.claimUnstake();

        // Verify we're in UnstakeClaimed state
        assertEq(uint8(staking.stakerState(address(this))), uint8(IStaking.StakerState.UnstakeClaimed));

        address staker = address(this);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1));
        uint64 sxtBlockNumber = 20;

        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);
        uint8[] memory v = new uint8[](2);
        for (uint256 i = 0; i < 2; ++i) {
            (v[i], r[i], s[i]) = (27, bytes32(uint256(1)), bytes32(uint256(1)));
        }

        vm.expectRevert(Staking.InvalidSignature.selector);
        staking.sxtFulfillUnstake(staker, amount, sxtBlockNumber, proof, r, s, v);
    }

    function testSxtFulfillUnstakeUnstakeNotUnbonded() public {
        address staker = address(0x02);
        uint248 amount = 1000e18;
        token.mint(staker, amount);

        vm.startPrank(staker);
        token.approve(address(staking), amount);
        staking.stake(amount);

        // Verify we're in Staked state
        assertEq(uint8(staking.stakerState(staker)), uint8(IStaking.StakerState.Staked));

        staking.initiateUnstake(amount);

        // Verify we're in UnstakeInitiated state
        assertEq(uint8(staking.stakerState(staker)), uint8(IStaking.StakerState.UnstakeInitiated));
        vm.stopPrank();

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1));
        uint64 sxtBlockNumber = 20;

        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);
        uint8[] memory v = new uint8[](2);
        for (uint256 i = 0; i < 2; ++i) {
            (v[i], r[i], s[i]) = (27, bytes32(uint256(1)), bytes32(uint256(1)));
        }

        // Should now expect InvalidStakerState because the staker is in UnstakeInitiated but should be in UnstakeClaimed
        vm.expectRevert(
            abi.encodeWithSelector(
                Staking.InvalidStakerState.selector,
                IStaking.StakerState.UnstakeInitiated,
                IStaking.StakerState.UnstakeClaimed
            )
        );
        staking.sxtFulfillUnstake(staker, amount, sxtBlockNumber, proof, r, s, v);
    }

    /**
     * @notice Test that verifies the initial state for any address is Unstaked
     * @dev This confirms the default initialization behavior of the state machine
     * using fuzzing to test multiple random addresses
     */
    function testFuzzInitialStateIsUnstaked(address newUser) public view {
        // Verify the initial state is Unstaked for any address
        assertEq(uint8(staking.stakerState(newUser)), uint8(IStaking.StakerState.Unstaked));

        // Also verify the timestamp is 0 for consistency
        assertEq(staking.initiateUnstakeRequestsTimestamp(newUser), 0);
    }

    /**
     * @notice Helper function to generate a simple Merkle proof for testing
     * @dev This is a mock implementation for testing purposes only
     * @return proof A bytes32 array representing a Merkle proof
     */
    function generateProof() internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1));
        return proof;
    }

    function testStakingWithUnstakeClaimed() public {
        // Arrange
        // First stake
        token.mint(address(this), 1000e18);
        token.approve(address(staking), 1000e18);
        staking.stake(1000e18);

        // Initiate unstake
        staking.initiateUnstake(1000e18);

        // Fast forward past the unbonding period
        vm.warp(block.timestamp + staking.UNSTAKING_UNBONDING_PERIOD() + 1);

        // Claim unstake (which puts user in UnstakeClaimed state)
        staking.claimUnstake();

        // Act & Assert
        // Try to stake again - should revert because user is in UnstakeClaimed state
        token.mint(address(this), 1000e18);
        token.approve(address(staking), 1000e18);
        vm.expectRevert(Staking.PendingUnstakeFulfillment.selector);
        staking.stake(1000e18);
    }
}
