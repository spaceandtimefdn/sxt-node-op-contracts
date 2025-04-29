// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    error TransferFailed();
    error TransferReverted();

    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    address private _failTransferTo;

    function setFailTransferTo(address recipient) external {
        _failTransferTo = recipient;
    }

    /// @notice Mapping to track which addresses should have their transfers reverted
    mapping(address => bool) private _shouldRevertTransfer;

    /// @notice Set whether transfers to a specific address should revert
    function setTransferShouldRevert(address to, bool shouldRevert) external {
        _shouldRevertTransfer[to] = shouldRevert;
    }

    /// @notice Override transfer to allow simulating failures
    function transfer(address to, uint256 amount) public virtual override returns (bool success) {
        if (_shouldRevertTransfer[to]) {
            revert TransferReverted();
        }
        if (to == _failTransferTo) {
            revert TransferFailed();
        }
        return super.transfer(to, amount);
    }

    /// @notice Flag to simulate approval failures
    bool private _approvalFailure;

    /// @notice Set whether approvals should fail
    function setApprovalFailure(bool shouldFail) external {
        _approvalFailure = shouldFail;
    }

    /// @notice Override approve to allow simulating failures
    function approve(address spender, uint256 amount) public virtual override returns (bool success) {
        if (_approvalFailure) {
            success = false;
        } else {
            success = super.approve(spender, amount);
        }
    }
}
