// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

event RewardRate(uint256 indexed jobId, uint256 rate);

event PerformanceRecorded(uint256 indexed jobId, address indexed provider, uint256 performance);

event RewardsClaimed(uint256 indexed jobId);

interface IRewardsDistributor {
    function setRewardRate(uint256 jobId, uint256 rate) external;
    function recordPerformance(uint256 jobId, address provider, uint256 performance) external;
    function claimRewards(uint256 jobId) external;
}
