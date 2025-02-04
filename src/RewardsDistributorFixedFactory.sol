// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./RewardsDistributorFixed.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IRewardsDistributorFactory.sol";

contract RewardsDistributorFixedFactory is AccessControl, IRewardsDistributorFactory {
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
        returns (IRewardsDistributor)
    {
        return new RewardsDistributorFixed(computePool, _computeRegistry, _poolId);
    }
}
