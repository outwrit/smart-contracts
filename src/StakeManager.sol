// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IStakeManager.sol";

contract StakeManager is IStakeManager {
    struct UnbondTracker {
        uint256 offset;
        Unbond[] unbonds;
    }

    mapping(address => uint256) private _stakes;
    mapping(address => UnbondTracker) private _unbonds;
    uint256 private _totalStaked;
    uint256 private _totalUnbonding;
    uint256 private _unbondingPeriod;

    function stake(address staker, uint256 amount) external override {
        _stakes[staker] += amount;
        _totalStaked += amount;
        emit Stake(staker, amount);
    }

    function unstake(address staker, uint256 amount) external override {
        require(_stakes[staker] >= amount, "StakeManager: insufficient balance");
        _stakes[staker] -= amount;
        _totalStaked -= amount;
        _totalUnbonding += amount;
        // add unbonding
        _unbonds[staker].unbonds.push(Unbond(amount, block.timestamp + _unbondingPeriod));
        emit Unstake(staker, amount);
    }

    function withdraw() external {
        // calculate amount that can be withdrawn
        uint256 amount = 0;
        Unbond[] storage pending = _unbonds[msg.sender].unbonds;
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i].timestamp <= block.timestamp) {
                amount += pending[i].amount;
                _totalUnbonding -= pending[i].amount;
                delete pending[i];
            } else {
                _unbonds[msg.sender].offset = i;
                break;
            }
        }
        require(_stakes[msg.sender] >= amount, "StakeManager: insufficient balance");
        _stakes[msg.sender] -= amount;
        _totalStaked -= amount;
        emit Withdraw(msg.sender, amount);
    }

    function slash(address staker, uint256 amount, bytes calldata reason) external override {
        require(_stakes[staker] >= amount, "StakeManager: insufficient balance");
        _stakes[staker] -= amount;
        _totalStaked -= amount;
        emit Unstake(staker, amount);
    }

    function setUnbondingPeriod(uint256 period) external override {
        _unbondingPeriod = period;
        emit UpdateUnbondingPeriod(period);
    }

    function getStake(address staker) external view override returns (uint256) {
        return _stakes[staker];
    }

    function getTotalStaked() external view override returns (uint256) {
        return _totalStaked;
    }

    function getPendingUnbonds(address staker) external view override returns (Unbond[] memory) {
        return _unbonds[staker].unbonds;
    }

    function getUnnbondingPeriod() external view override returns (uint256) {
        return _unbondingPeriod;
    }
}
