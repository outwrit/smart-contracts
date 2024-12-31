// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

abstract contract IWorkValidation {
    function validateWork(uint256 domainId, uint256 jobId, address provider, uint256 nodeId, bytes calldata data)
        external
        virtual
        returns (bool);
}
