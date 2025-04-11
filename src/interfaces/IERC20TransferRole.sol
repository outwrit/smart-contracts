// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface IERC20TransferRole {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function approveTransferAddress(address transferAddress) external;

    function revokeTransferAddress(address transferAddress) external;
}
