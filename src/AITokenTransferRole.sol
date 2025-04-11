// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20TransferRole.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract AITokenTransferRole is IERC20TransferRole, AccessControl, ERC20Permit {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");

    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    function transfer(address to, uint256 amount) public override onlyRole(TRANSFER_ROLE) returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        override
        onlyRole(TRANSFER_ROLE)
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        override
        onlyRole(TRANSFER_ROLE)
    {
        super.permit(owner, spender, value, deadline, v, r, s);
    }

    function approveTransferAddress(address transferAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(TRANSFER_ROLE, transferAddress);
    }

    function revokeTransferAddress(address transferAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(TRANSFER_ROLE, transferAddress);
    }
}
