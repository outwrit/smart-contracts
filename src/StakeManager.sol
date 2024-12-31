// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IStakeManager.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakeManager is IStakeManager, AccessControl {
    struct UnbondTracker {
        uint256 offset;
        Unbond[] unbonds;
    }

    bytes32 public constant PRIME_ROLE = keccak256("PRIME_ROLE");
    IERC20 public PrimeToken;

    mapping(address => uint256) private _stakes;
    mapping(address => UnbondTracker) private _unbonds;
    uint256 private _totalStaked;
    uint256 private _totalUnbonding;
    uint256 private _unbondingPeriod;
    uint256 private _stakeMinimum;

    constructor(address primeAdmin, uint256 unbondingPeriod, IERC20 primeToken) {
        _unbondingPeriod = unbondingPeriod;
        PrimeToken = primeToken;
        _grantRole(DEFAULT_ADMIN_ROLE, primeAdmin);
        _grantRole(PRIME_ROLE, primeAdmin);
    }

    function stake(address staker, uint256 amount) external onlyRole(PRIME_ROLE) {
        _stakes[staker] += amount;
        _totalStaked += amount;
        PrimeToken.transferFrom(msg.sender, address(this), amount);
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
        require(_stakes[msg.sender] >= amount, "StakeManager: insufficient balance");
        _stakes[msg.sender] -= amount;
        _totalStaked -= amount;
        PrimeToken.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function slash(address staker, uint256 amount, bytes calldata reason) external onlyRole(PRIME_ROLE) {
        require(_stakes[staker] >= amount, "StakeManager: insufficient balance");
        reason.length == 0; // silence warning
        _stakes[staker] -= amount;
        _totalStaked -= amount;
        emit Unstake(staker, amount);
    }

    function setUnbondingPeriod(uint256 period) external onlyRole(PRIME_ROLE) {
        _unbondingPeriod = period;
        emit UpdateUnbondingPeriod(period);
    }

    function setStakeMinimum(uint256 minimum) external onlyRole(PRIME_ROLE) {
        _stakeMinimum = minimum;
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

    function getUnnbondingPeriod() external view returns (uint256) {
        return _unbondingPeriod;
    }

    function getStakeMinimum() external view returns (uint256) {
        return _stakeMinimum;
    }
}
