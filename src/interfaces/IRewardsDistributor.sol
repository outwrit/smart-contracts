// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

event RewardRate(uint256 indexed poolId, uint256 rate);

event RewardsClaimed(uint256 indexed poolId, address indexed provider, address indexed nodekey, uint256 reward);

interface IRewardsDistributor {
    function calculateRewards(address node) external view returns (uint256);
    function claimRewards(address node) external;
    function setRewardRate(uint256 newRate) external;
    function endRewards() external;
    function joinPool(address node, uint256 computeUnits) external;
    function leavePool(address node) external;
}
