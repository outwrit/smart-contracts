// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

event Stake(address staker, uint256 amount);

event Unstake(address staker, uint256 amount);

event Withdraw(address staker, uint256 amount);

event UpdateUnbondingPeriod(uint256 period);

interface IStakeManager {
    function stake(address staker, uint256 amount) external;
    function unstake(address staker, uint256 amount) external;
    function withdraw(uint256 amount) external;
    function slash(address staker, uint256 amount, bytes calldata reason) external;

    function setUnbondingPeriod(uint256 period) external;

    function getStake(address staker) external view returns (uint256);
    function getTotalStaked() external view returns (uint256);
    function getPendingUnbonds(address staker) external view returns (uint256, uint256);
    function getUnnbondingPeriod() external view returns (uint256);
}
