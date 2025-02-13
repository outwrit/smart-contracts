// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IStakeManager.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakeManager is IStakeManager, AccessControlEnumerable {
    struct UnbondTracker {
        uint256 offset;
        Unbond[] unbonds;
    }

    bytes32 public constant PRIME_ROLE = keccak256("PRIME_ROLE");
    IERC20 public AIToken;

    mapping(address => uint256) private _stakes;
    mapping(address => UnbondTracker) private _unbonds;
    uint256 private _totalStaked;
    uint256 private _totalUnbonding;
    uint256 private _unbondingPeriod;
    uint256 private _stakeMinimum;

    constructor(address primeAdmin, uint256 unbondingPeriod, IERC20 _AIToken) {
        _unbondingPeriod = unbondingPeriod;
        AIToken = _AIToken;
        _grantRole(DEFAULT_ADMIN_ROLE, primeAdmin);
        _grantRole(PRIME_ROLE, primeAdmin);
    }

    function stake(address staker, uint256 amount) external onlyRole(PRIME_ROLE) {
        _stakes[staker] += amount;
        _totalStaked += amount;
        AIToken.transferFrom(msg.sender, address(this), amount);
        emit Stake(staker, amount);
    }

    function unstake(address staker, uint256 amount) external onlyRole(PRIME_ROLE) {
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
        if (amount == 0) {
            revert("StakeManager: no funds to withdraw");
        }
        AIToken.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function slash(address staker, uint256 amount, bytes calldata reason)
        external
        onlyRole(PRIME_ROLE)
        returns (uint256 slashed)
    {
        reason.length == 0; // silence warning
        if (_stakes[staker] < amount) {
            // look in pending unbonds
            uint256 unbonding_amount = 0;
            UnbondTracker storage pending = _unbonds[staker];
            for (uint256 i = pending.offset; i < pending.unbonds.length; i++) {
                if (pending.unbonds[i].timestamp > block.timestamp) {
                    unbonding_amount += pending.unbonds[i].amount;
                    if (unbonding_amount > amount) {
                        // slash the difference
                        uint256 diff = unbonding_amount - amount;
                        _totalUnbonding -= (pending.unbonds[i].amount - diff);
                        pending.unbonds[i].amount = diff;
                        unbonding_amount = amount;
                        pending.offset = i;
                        break;
                    } else if (unbonding_amount == amount) {
                        // slash the whole unbond
                        _totalUnbonding -= pending.unbonds[i].amount;
                        delete pending.unbonds[i];
                        pending.offset = i + 1;
                        break;
                    } else {
                        // slash the whole unbond and continue
                        _totalUnbonding -= pending.unbonds[i].amount;
                        delete pending.unbonds[i];
                        pending.offset = i + 1;
                    }
                }
            }
            if (unbonding_amount < amount) {
                // slash the remaining amount from the stake
                uint256 amount_left = amount - unbonding_amount;
                if (_stakes[staker] < amount_left) {
                    amount_left = _stakes[staker];
                }
                _stakes[staker] -= amount_left;
                _totalStaked -= amount_left;
                uint256 total = amount_left + unbonding_amount;
                AIToken.transfer(msg.sender, total);
                emit Slashed(staker, total, reason);
                return total;
            } else {
                AIToken.transfer(msg.sender, amount);
                emit Slashed(staker, amount, reason);
                return amount;
            }
        } else {
            _stakes[staker] -= amount;
            _totalStaked -= amount;
            AIToken.transfer(msg.sender, amount);
            emit Slashed(staker, amount, reason);
            return amount;
        }
    }

    function setUnbondingPeriod(uint256 period) external onlyRole(PRIME_ROLE) {
        _unbondingPeriod = period;
        emit UpdateUnbondingPeriod(period);
    }

    function setStakeMinimum(uint256 minimum) external onlyRole(PRIME_ROLE) {
        _stakeMinimum = minimum;
        emit StakeMinimumUpdate(minimum);
    }

    function getStake(address staker) external view returns (uint256) {
        return _stakes[staker];
    }

    function getTotalStaked() external view returns (uint256) {
        return _totalStaked;
    }

    function getPendingUnbonds(address staker) external view returns (Unbond[] memory) {
        return _unbonds[staker].unbonds;
    }

    function getUnbondingPeriod() external view returns (uint256) {
        return _unbondingPeriod;
    }

    function getTotalUnbonding() external view returns (uint256) {
        return _totalUnbonding;
    }

    function getStakeMinimum() external view returns (uint256) {
        return _stakeMinimum;
    }
}
