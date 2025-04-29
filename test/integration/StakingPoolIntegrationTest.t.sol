// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Staking} from "../../src/Staking.sol";
import {StakingPool} from "../../src/StakingPool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IStakingPool} from "../../src/interfaces/IStakingPool.sol";
import {SubstrateSignatureValidator} from "../../src/SubstrateSignatureValidator.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title StakingPoolIntegrationTest
 * @notice Integration test suite that validates the interactions between Staking and StakingPool contracts
 * @dev Tests the full lifecycle from staking through unstaking, ensuring proper token flow between contracts
 */
contract StakingPoolIntegrationTest is Test {
    // Contracts
    Staking private staking;
    StakingPool private stakingPool;
    MockERC20 private token;
    SubstrateSignatureValidator private signatureValidator;

    // Test accounts
    address private deployer = address(this);
    address private user1 = address(0xABCD);
    address private user2 = address(0xBCDE);

    // Constants
    uint64 private constant UNBONDING_PERIOD = 7 days;
    uint248 private constant STAKE_AMOUNT = 1000 * 10 ** 18;

    // Test data
    uint256[] private attestorsPrivateKeys;
    address[] private attestors;

    function setUp() public {
        // Create tokens
        token = new MockERC20();

        // Setup attestors for signature validation using the same approach as StakingTest
        attestorsPrivateKeys = new uint256[](2);
        attestorsPrivateKeys[0] = 0x02;
        attestorsPrivateKeys[1] = 0x03;
        attestors = new address[](2);

        for (uint256 i = 0; i < 2; ++i) {
            attestors[i] = vm.addr(attestorsPrivateKeys[i]);
        }

        // Sort attestors (critical for SubstrateSignatureValidator)
        if (attestors[0] > attestors[1]) {
            address tempAddress = attestors[0];
            uint256 tempPrivateKey = attestorsPrivateKeys[0];
            attestors[0] = attestors[1];
            attestorsPrivateKeys[0] = attestorsPrivateKeys[1];
            attestors[1] = tempAddress;
            attestorsPrivateKeys[1] = tempPrivateKey;
        }

        // Deploy contracts
        signatureValidator = new SubstrateSignatureValidator(attestors, 2); // Require both signatures
        stakingPool = new StakingPool(address(token), address(this));
        staking = new Staking(address(token), address(stakingPool), UNBONDING_PERIOD, address(signatureValidator));

        // Add staking contract to staking pool
        stakingPool.addStakingContract(address(staking));

        // Fund test accounts
        _fundAccount(user1, STAKE_AMOUNT * 2);
        _fundAccount(user2, STAKE_AMOUNT * 2);

        // Fund staking pool for withdrawals
        token.mint(address(stakingPool), STAKE_AMOUNT * 10);

        staking.unpauseUnstaking();
    }

    /**
     * @notice Tests the full lifecycle of staking and unstaking for a user
     * @dev This covers the flow of tokens from user to staking pool and back to user
     */
    function testFullStakingUnstakingLifecycle() public {
        // Initial state - funds are with the user
        assertEq(token.balanceOf(user1), STAKE_AMOUNT * 2);
        assertEq(token.balanceOf(address(stakingPool)), STAKE_AMOUNT * 10);

        // User stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Check balances after staking
        assertEq(token.balanceOf(user1), STAKE_AMOUNT);
        assertEq(token.balanceOf(address(stakingPool)), STAKE_AMOUNT * 11);
        // StakingPool no longer tracks individual balances

        // Tokens should now be in staking pool, not in staking contract
        assertEq(token.balanceOf(address(staking)), 0, "Staking contract empty");

        // User initiates unstake
        vm.startPrank(user1);
        staking.initiateUnstake(STAKE_AMOUNT);
        vm.stopPrank();

        // Wait for unbonding period
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);

        // User claims unstake
        vm.startPrank(user1);
        staking.claimUnstake();
        vm.stopPrank();

        // Need to generate proof, signatures, etc. for fulfillment
        uint64 sxtBlockNumber = 1;
        bytes32[] memory proof = generateProof();

        // Build the exact message hash that Staking contract will build internally
        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(abi.encodePacked(uint256(uint160(user1)), STAKE_AMOUNT, block.chainid, address(staking)))
            )
        );
        bytes32 rootHash = MerkleProof.processProof(proof, leaf);
        bytes memory messageBody = abi.encodePacked(rootHash, sxtBlockNumber);
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(messageBody.length), messageBody)
        );

        // Generate signatures from the attestors using their private keys
        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);
        uint8[] memory v = new uint8[](2);

        for (uint256 i = 0; i < 2; ++i) {
            (v[i], r[i], s[i]) = vm.sign(attestorsPrivateKeys[i], messageHash);
        }

        // SXT fulfills unstake with valid signatures
        staking.sxtFulfillUnstake(user1, STAKE_AMOUNT, sxtBlockNumber, proof, r, s, v);

        // Check balances after unstake
        assertEq(token.balanceOf(user1), STAKE_AMOUNT * 2);
        assertEq(token.balanceOf(address(stakingPool)), STAKE_AMOUNT * 10);
        // StakingPool no longer tracks individual balances
    }

    /**
     * @notice Tests the ability for a user to stake additional tokens while having an unstake in progress
     * @dev This validates the cancellation of unstake requests when staking again
     */
    function testStakeWhileUnstaking() public {
        // User stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);

        // User initiates unstake
        staking.initiateUnstake(STAKE_AMOUNT);

        // Record the unstake timestamp
        uint64 unstakeTimestamp = staking.initiateUnstakeRequestsTimestamp(user1);
        assertTrue(unstakeTimestamp > 0, "Unstake timestamp should be set");

        // User decides to stake more, which should cancel the unstake
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Unstake should be cancelled
        assertEq(staking.initiateUnstakeRequestsTimestamp(user1), 0, "Unstake should be cancelled");

        // User should have zero balance, pool should have both stake amounts
        assertEq(token.balanceOf(user1), 0, "User has no tokens");
        assertEq(token.balanceOf(address(stakingPool)), STAKE_AMOUNT * 12, "Pool has all tokens");
        // StakingPool no longer tracks individual balances
    }

    /**
     * @notice Tests the case where an unauthorized contract tries to interact with the staking pool
     * @dev Only whitelisted staking contracts should be able to call withdraw
     */
    function testUnauthorizedAccessToStakingPool() public {
        // Deploy a malicious contract (simulated by deployer)
        address malicious = address(0xBAD);

        // Attempt to withdraw from staking pool directly
        vm.startPrank(malicious);
        vm.expectRevert(); // Should revert as malicious is not a whitelisted contract
        IStakingPool(address(stakingPool)).withdraw(user1, STAKE_AMOUNT);
        vm.stopPrank();

        // Confirm balances are unchanged
        assertEq(token.balanceOf(user1), STAKE_AMOUNT * 2, "User1 balance unchanged");
        assertEq(token.balanceOf(address(stakingPool)), STAKE_AMOUNT * 10, "Pool balance unchanged");
        // StakingPool no longer tracks individual balances
    }

    /**
     * @notice Tests that multiple users can stake and unstake independently
     * @dev Validates that the system properly tracks state per user
     */
    function testMultipleUsersStakingUnstaking() public {
        // Users stake tokens
        vm.startPrank(user1);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Check balances after staking
        // StakingPool no longer tracks individual balances
        // StakingPool no longer tracks individual balances

        // Verify pool has all the tokens
        assertEq(token.balanceOf(address(stakingPool)), STAKE_AMOUNT * 12, "Pool has all tokens");

        // User 1 initiates unstake
        vm.startPrank(user1);
        staking.initiateUnstake(STAKE_AMOUNT);
        vm.stopPrank();

        // User 2 should be unaffected
        assertEq(staking.initiateUnstakeRequestsTimestamp(user2), 0, "User2 unstake not initiated");

        // Fast forward to complete unbonding
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);

        // User 1 claims unstake
        vm.startPrank(user1);
        staking.claimUnstake();
        vm.stopPrank();

        // Process unstake for user1 (need proof, signatures, etc.)
        bytes32[] memory proof = generateProof();
        uint64 sxtBlockNumber = 1;

        // Build the exact message hash that Staking contract will build internally
        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(abi.encodePacked(uint256(uint160(user1)), STAKE_AMOUNT, block.chainid, address(staking)))
            )
        );
        bytes32 rootHash = MerkleProof.processProof(proof, leaf);
        bytes memory messageBody = abi.encodePacked(rootHash, sxtBlockNumber);
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(messageBody.length), messageBody)
        );

        // Generate signatures from the attestors using their private keys
        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);
        uint8[] memory v = new uint8[](2);

        for (uint256 i = 0; i < 2; ++i) {
            (v[i], r[i], s[i]) = vm.sign(attestorsPrivateKeys[i], messageHash);
        }

        // SXT fulfills unstake with valid signatures
        staking.sxtFulfillUnstake(user1, STAKE_AMOUNT, sxtBlockNumber, proof, r, s, v);

        // Check balances after user1's unstake
        // StakingPool no longer tracks individual balances
        // StakingPool no longer tracks individual balances
    }

    /**
     * @notice Tests that an attacker cannot drain the pool using a whitelisted staking contract
     * @dev Validates the security of the balance tracking mechanism
     */
    function testAttemptedBalanceDrain() public {
        // Initial setup - user1 stakes
        vm.startPrank(user1);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // User2 initiates unstake without staking
        vm.startPrank(user2);
        token.approve(address(staking), STAKE_AMOUNT / 2); // Stake half the amount
        staking.stake(STAKE_AMOUNT / 2);
        staking.initiateUnstake(STAKE_AMOUNT);
        vm.stopPrank();

        // Fast forward to after unbonding period
        vm.warp(block.timestamp + UNBONDING_PERIOD);

        // Claim unstake to move to UnstakeClaimed state
        vm.startPrank(user2);
        staking.claimUnstake();
        vm.stopPrank();

        // Try to drain more funds than the pool has
        bytes32[] memory proofArray = generateProof();
        uint64 sxtBlockNumber = 1;

        // Build message hash for signatures
        // Use a larger amount than what's in the pool
        uint248 excessiveAmount = STAKE_AMOUNT * 100; // Much larger than what's in the pool
        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(abi.encodePacked(uint256(uint160(user2)), excessiveAmount, block.chainid, address(staking)))
            )
        );
        bytes32 rootHash = MerkleProof.processProof(proofArray, leaf);
        bytes memory messageBody = abi.encodePacked(rootHash, sxtBlockNumber);
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(messageBody.length), messageBody)
        );

        // Generate signatures
        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);
        uint8[] memory v = new uint8[](2);

        for (uint256 i = 0; i < 2; ++i) {
            (v[i], r[i], s[i]) = vm.sign(attestorsPrivateKeys[i], messageHash);
        }

        // Attempt withdraw should fail due to insufficient pool balance
        vm.expectRevert(StakingPool.InsufficientPoolBalance.selector);
        staking.sxtFulfillUnstake(user2, excessiveAmount, sxtBlockNumber, proofArray, r, s, v);

        // Balances should remain unchanged
        assertEq(
            token.balanceOf(address(stakingPool)),
            STAKE_AMOUNT * 10 + STAKE_AMOUNT + STAKE_AMOUNT / 2,
            "StakingPool balance incorrect"
        );
        assertEq(token.balanceOf(user2), STAKE_AMOUNT * 2 - STAKE_AMOUNT / 2, "User2 balance incorrect"); // Original balance minus staked amount
    }

    // ==================== Helper Functions ====================

    /**
     * @notice Generates a proof for unstaking
     * @dev In a real system, this would be generated by the SXT system using the staker's address
     *      and amount to create a proper Merkle proof. This is simplified for testing purposes.
     * @return proof A dummy proof array for testing
     */
    function _generateProof() internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1));
        return proof;
    }

    /**
     * @notice Generates a proof for unstaking
     * @dev In a real system, this would be generated by the SXT system using the staker's address
     *      and amount to create a proper Merkle proof. This is simplified for testing purposes.
     * @return proof A dummy proof bytes for testing
     */
    function generateProof() internal pure returns (bytes32[] memory proof) {
        // Return a simple proof array for testing
        proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1));
        return proof;
    }

    /**
     * @notice Deserializes a proof from bytes to bytes32[]
     * @param proof The proof in bytes format
     * @return proofArray The proof converted to bytes32[]
     */
    function _deserializeProof(bytes memory proof) internal pure returns (bytes32[] memory proofArray) {
        // For simplicity, we assume the proof contains exactly one bytes32 element
        proofArray = new bytes32[](1);
        bytes32 element;

        assembly {
            element := mload(add(proof, 32))
        }

        proofArray[0] = element;
        return proofArray;
    }

    /**
     * @notice Fund a test account with tokens
     */
    function _fundAccount(address account, uint256 amount) internal {
        token.mint(account, amount);
    }
}
