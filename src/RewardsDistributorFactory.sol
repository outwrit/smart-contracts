// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./RewardsDistributor.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract RewardsDistributorFactory is AccessControl {
    bytes32 public constant REWARD_CREATOR = keccak256("REWARD_CREATOR");
    IComputePool computePool;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REWARD_CREATOR, msg.sender);
    }

    function setComputePool(IComputePool _computePool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(REWARD_CREATOR, address(_computePool));
        computePool = _computePool;
    }

    function createRewardsDistributor(IComputeRegistry _computeRegistry, uint256 _poolId)
        external
        onlyRole(REWARD_CREATOR)
        returns (RewardsDistributor)
    {
        return new RewardsDistributor(computePool, _computeRegistry, _poolId);
    }
}
