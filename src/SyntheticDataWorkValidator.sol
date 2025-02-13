// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IWorkValidation.sol";

event WorkSubmitted(uint256 poolId, address provider, address nodeId, bytes32 workKey);

event WorkInvalidated(uint256 poolId, address provider, address nodeId, bytes32 workKey);

contract SyntheticDataWorkValidator is IWorkValidation {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    uint256 domainId;
    address computePool;

    struct WorkState {
        EnumerableSet.Bytes32Set workKeys;
        EnumerableSet.Bytes32Set invalidWorkKeys;
        mapping(bytes32 => WorkInfo) work;
    }

    struct WorkInfo {
        address provider;
        address nodeId;
        uint64 timestamp;
    }

    mapping(uint256 => WorkState) poolWork;

    constructor(uint256 _domainId, address _computePool) {
        domainId = _domainId;
        computePool = _computePool;
    }

    function submitWork(uint256 _domainId, uint256 poolId, address provider, address nodeId, bytes calldata data)
        external
        returns (bool)
    {
        require(msg.sender == computePool, "Unauthorized");
        require(data.length >= 32, "Data too short");
        require(domainId == _domainId, "Invalid domainId");
        bytes32 workKey;
        assembly {
            workKey := calldataload(data.offset)
        }
        require(!poolWork[poolId].workKeys.contains(workKey), "Work already submitted");

        poolWork[poolId].workKeys.add(workKey);
        poolWork[poolId].work[workKey] = WorkInfo(provider, nodeId, uint64(block.timestamp));

        emit WorkSubmitted(poolId, provider, nodeId, workKey);

        return true;
    }

    function invalidateWork(uint256 poolId, bytes calldata data) external returns (address, address) {
        require(msg.sender == computePool, "Unauthorized");
        require(data.length >= 32, "Data too short");
        bytes32 workKey;
        assembly {
            workKey := calldataload(data.offset)
        }
        require(poolWork[poolId].workKeys.contains(workKey), "Work not found");
        require(!poolWork[poolId].invalidWorkKeys.contains(workKey), "Work already invalidated");

        poolWork[poolId].invalidWorkKeys.add(workKey);
        WorkInfo memory info = poolWork[poolId].work[workKey];
        poolWork[poolId].workKeys.remove(workKey);

        emit WorkInvalidated(poolId, info.provider, info.nodeId, workKey);

        return (info.provider, info.nodeId);
    }
}
