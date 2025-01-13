// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IRewardsDistributor.sol";
import "./interfaces/IComputePool.sol";
import "./interfaces/IComputeRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RewardsDistributor {
    IComputePool public computePool;
    IComputeRegistry public computeRegistry;
    uint256 public poolId;
    mapping(address => uint256) public lastClaimed;
    IERC20 public AIToken;
    uint256 public rewardRate;

    constructor(IComputePool _computePool, IComputeRegistry _computeRegistry, uint256 _poolId) {
        computePool = _computePool;
        computeRegistry = _computeRegistry;
        poolId = _poolId;
    }

    function claimRewards(address provider, address nodekey) external {
        IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(provider, nodekey);
        require(node.provider == msg.sender, "Only provider can claim rewards");
        IComputePool.WorkInterval[] memory nodeWork = computePool.getNodeWork(poolId, nodekey);
        uint256 totalTime = 0;
        uint256 latestNewClaim = 0;

        for (uint256 i = nodeWork.length - 1; i >= 0; i--) {
            IComputePool.WorkInterval memory workSpan = nodeWork[i];
            if (nodeWork[i].leaveTime > lastClaimed[nodekey]) {
                totalTime += workSpan.leaveTime - workSpan.joinTime;
                latestNewClaim = workSpan.leaveTime;
            } else {
                break;
            }
        }

        lastClaimed[nodekey] = latestNewClaim;

        uint256 reward = totalTime * rewardRate * node.computeUnits;

        emit RewardsClaimed(poolId, provider, nodekey, reward);
    }
}
