// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SubstrateSignatureValidator} from "../src/SubstrateSignatureValidator.sol";

contract SubstrateSignatureValidatorTest is Test {
    SubstrateSignatureValidator private validator;
    address[] private attestors;
    bytes32 private message;

    event AttestorsUpdated(address[] attestors);
    event ThresholdUpdated(uint16 threshold);

    function setUp() public {
        message = keccak256("test");

        attestors = new address[](2);
        attestors[0] = ecrecover(message, 27, bytes32(uint256(0x1)), bytes32(uint256(0x3)));
        attestors[1] = ecrecover(message, 27, bytes32(uint256(0x2)), bytes32(uint256(0x4)));

        validator = new SubstrateSignatureValidator(attestors, 1);
    }

    function testValidateMessage() public view {
        bytes32[] memory r = new bytes32[](2);
        r[0] = bytes32(uint256(0x1));
        r[1] = bytes32(uint256(0x2));
        bytes32[] memory s = new bytes32[](2);
        s[0] = bytes32(uint256(0x3));
        s[1] = bytes32(uint256(0x4));
        uint8[] memory v = new uint8[](2);
        v[0] = 27;
        v[1] = 27;

        assertEq(validator.validateMessage(message, r, s, v), true);
    }

    function testValidatedRejectsDuplicateSignatures() public {
        SubstrateSignatureValidator validator2 = new SubstrateSignatureValidator(attestors, 2);

        bytes32[] memory r = new bytes32[](2);
        r[0] = bytes32(uint256(0x1));
        r[1] = bytes32(uint256(0x1));
        bytes32[] memory s = new bytes32[](2);
        s[0] = bytes32(uint256(0x3));
        s[1] = bytes32(uint256(0x3));
        uint8[] memory v = new uint8[](2);
        v[0] = 27;
        v[1] = 27;

        assert(!validator2.validateMessage(message, r, s, v));
    }

    function testValidateMessageWithNotEnoughSignatures() public {
        SubstrateSignatureValidator validator2 = new SubstrateSignatureValidator(attestors, 2);

        bytes32[] memory r = new bytes32[](2);
        r[0] = bytes32(uint256(0x1));
        r[1] = bytes32(uint256(0x2));
        bytes32[] memory s = new bytes32[](2);
        s[0] = bytes32(uint256(0x3));
        s[1] = bytes32(uint256(0x5));
        uint8[] memory v = new uint8[](2);
        v[0] = 27;
        v[1] = 27;

        assertEq(validator2.validateMessage(message, r, s, v), false);
    }

    function testEmptyAttestorsList() public {
        address[] memory emptyAttestors = new address[](0);

        vm.expectRevert(SubstrateSignatureValidator.EmptyAttestorsList.selector);
        new SubstrateSignatureValidator(emptyAttestors, 1);
    }

    function testShortAttestorsListInConstructor() public {
        vm.expectRevert(SubstrateSignatureValidator.AttestorsLengthLessThanThreshold.selector);
        new SubstrateSignatureValidator(attestors, 3);
    }

    function testInvalidAttestorAddress() public {
        address[] memory invalidAttestors = new address[](2);
        invalidAttestors[0] = address(0x0);
        invalidAttestors[1] = address(0x8b14cE504aC5BE70E619a191C4Ec47C85B82FC1d);

        vm.expectRevert(SubstrateSignatureValidator.InvalidAttestorAddress.selector);
        new SubstrateSignatureValidator(invalidAttestors, 1);
    }

    function testGetThreshold() public view {
        assertEq(validator.getThreshold(), 1);
    }

    function testGetAttestors() public view {
        address[] memory result = validator.getAttestors();
        assertEq(result.length, 2);
        assertEq(result[0], attestors[0]);
        assertEq(result[1], attestors[1]);
    }

    function testIsAttestor() public view {
        assertEq(validator.isAttestor(attestors[0]), true);
        assertEq(validator.isAttestor(attestors[1]), true);
        assertEq(validator.isAttestor(address(0x0)), false);
        assertEq(validator.isAttestor(address(0x1)), false);
    }

    function testFuzzUpdateAttestorsAndThreshold(address[] memory newAttestors, uint16 newThreshold) public {
        if (newThreshold == 0) {
            vm.expectRevert(SubstrateSignatureValidator.InvalidThreshold.selector);
            validator.updateAttestorsAndThreshold(newAttestors, newThreshold);
        } else if (newAttestors.length == 0) {
            vm.expectRevert(SubstrateSignatureValidator.EmptyAttestorsList.selector);
            validator.updateAttestorsAndThreshold(newAttestors, newThreshold);
        } else if (newAttestors[0] == address(0)) {
            vm.expectRevert(SubstrateSignatureValidator.InvalidAttestorAddress.selector);
            validator.updateAttestorsAndThreshold(newAttestors, newThreshold);
        } else if (newAttestors.length < newThreshold) {
            vm.expectRevert(SubstrateSignatureValidator.AttestorsLengthLessThanThreshold.selector);
            validator.updateAttestorsAndThreshold(newAttestors, newThreshold);
        } else if (!isSorted(newAttestors)) {
            vm.expectRevert(SubstrateSignatureValidator.InvalidAttestorList.selector);
            validator.updateAttestorsAndThreshold(newAttestors, newThreshold);
        } else {
            vm.expectEmit();
            emit AttestorsUpdated(newAttestors);
            emit ThresholdUpdated(newThreshold);
            validator.updateAttestorsAndThreshold(newAttestors, newThreshold);
        }
    }

    function isSorted(address[] memory arr) internal pure returns (bool result) {
        result = true;
        uint256 listLength = arr.length;
        for (uint256 i = 1; i < listLength; ++i) {
            // solhint-disable-next-line gas-strict-inequalities
            if (arr[i] <= arr[i - 1]) result = false;
        }
    }
}
