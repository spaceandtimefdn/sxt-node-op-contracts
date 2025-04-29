// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CollaborativeStakingFactory} from "../src/CollaborativeStakingFactory.sol";
import {CollaborativeStaking} from "../src/CollaborativeStaking.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract CollaborativeStakingFactoryTest is Test {
    CollaborativeStakingFactory internal factory;
    MockERC20 internal token;
    address internal stakingContract = address(0x1234);
    uint256 internal stakingDelayLength = 1 days;

    function setUp() public {
        factory = new CollaborativeStakingFactory();
        token = new MockERC20();
    }

    function testDeployCollaborativeStaking() public {
        address collaborativeStakingAddress =
            factory.deployCollaborativeStaking(address(token), stakingContract, stakingDelayLength);

        CollaborativeStaking collaborativeStaking = CollaborativeStaking(collaborativeStakingAddress);

        assertEq(collaborativeStaking.TOKEN_ADDRESS(), address(token));
        assertEq(collaborativeStaking.STAKING_ADDRESS(), stakingContract);
        assertEq(collaborativeStaking.STAKING_DELAY_LENGTH(), stakingDelayLength);
    }

    function testEmitCollaborativeStakingDeployedEvent() public {
        vm.expectEmit(false, true, false, false);
        emit CollaborativeStakingFactory.CollaborativeStakingDeployed(address(0), address(this));

        factory.deployCollaborativeStaking(address(token), stakingContract, stakingDelayLength);
    }

    function testRevertOnZeroTokenAddress() public {
        vm.expectRevert(CollaborativeStaking.ZeroAddress.selector);
        factory.deployCollaborativeStaking(address(0), stakingContract, stakingDelayLength);
    }

    function testRevertOnZeroStakingAddress() public {
        vm.expectRevert(CollaborativeStaking.ZeroAddress.selector);
        factory.deployCollaborativeStaking(address(token), address(0), stakingDelayLength);
    }

    function testRevertOnZeroStakingDelay() public {
        vm.expectRevert(CollaborativeStaking.ZeroAddress.selector);
        factory.deployCollaborativeStaking(address(token), stakingContract, 0);
    }

    function testDeployCollaborativeStakingWithDefaults() public {
        address funder = address(0x5678);
        address beneficiary = address(0x9ABC);

        address collaborativeStakingAddress =
            factory.deployCollaborativeStakingWithDefaults(address(token), stakingContract, funder, beneficiary);

        CollaborativeStaking collaborativeStaking = CollaborativeStaking(collaborativeStakingAddress);

        assertEq(collaborativeStaking.TOKEN_ADDRESS(), address(token));
        assertEq(collaborativeStaking.STAKING_ADDRESS(), stakingContract);
        assertEq(collaborativeStaking.STAKING_DELAY_LENGTH(), 10 days);

        // Verify roles
        assertTrue(collaborativeStaking.hasRole(collaborativeStaking.FUNDER_ROLE(), funder));
        assertTrue(collaborativeStaking.hasRole(collaborativeStaking.STAKER_ROLE(), funder));
        assertTrue(collaborativeStaking.hasRole(collaborativeStaking.FUNDER_ROLE(), beneficiary));
        assertTrue(collaborativeStaking.hasRole(collaborativeStaking.STAKER_ROLE(), beneficiary));
        assertTrue(collaborativeStaking.hasRole(collaborativeStaking.BENEFICIARY_ROLE(), beneficiary));
    }
}
