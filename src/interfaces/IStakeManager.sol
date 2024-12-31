// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

event Stake(address staker, uint256 amount);

event Unstake(address staker, uint256 amount);

event Withdraw(address staker, uint256 amount);

event UpdateUnbondingPeriod(uint256 period);

interface IStakeManager {
    struct Unbond {
        uint256 amount;
        uint256 timestamp;
    }

    function stake(address staker, uint256 amount) external;
    function unstake(address staker, uint256 amount) external;
    function withdraw() external;
    function slash(address staker, uint256 amount, bytes calldata reason) external;

    function setUnbondingPeriod(uint256 period) external;

    function getStake(address staker) external view returns (uint256);
    function getTotalStaked() external view returns (uint256);
    function getPendingUnbonds(address staker) external view returns (Unbond[] memory);
    function getUnnbondingPeriod() external view returns (uint256);
}
