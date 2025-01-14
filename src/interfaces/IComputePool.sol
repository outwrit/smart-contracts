// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IComputeRegistry.sol";
import "./IRewardsDistributor.sol";

event ComputePoolCreated(uint256 indexed poolId, uint256 indexed domainId, address indexed creator);

event ComputePoolStarted(uint256 indexed poolId, uint256 timestamp);

event ComputePoolEnded(uint256 indexed poolId);

event ComputePoolURIUpdated(uint256 indexed poolId, string uri);

event ComputePoolJoined(uint256 indexed poolId, address indexed provider, address[] nodekeys);

event ComputePoolLeft(uint256 indexed poolId, address indexed provider, address nodekey);

event ComputePoolProviderBlacklisted(uint256 indexed poolId, address indexed provider);

event ComputePoolNodeBlacklisted(uint256 indexed poolId, address indexed provider, address nodekey);

interface IComputePool {
    enum PoolStatus {
        PENDING,
        ACTIVE,
        COMPLETED
    }

    struct PoolInfo {
        uint256 poolId;
        uint256 domainId;
        string poolName;
        address creator;
        address computeManagerKey;
        uint256 creationTime;
        uint256 startTime;
        uint256 endTime;
        string poolDataURI;
        address poolValidationLogic;
        uint256 totalCompute;
        PoolStatus status;
    }

    struct WorkInterval {
        uint256 joinTime;
        uint256 leaveTime;
    }

    function createComputePool(
        uint256 domainId,
        address computeManagerKey,
        string calldata poolName,
        string calldata poolDataURI
    ) external returns (uint256);
    function startComputePool(uint256 poolId) external;
    function endComputePool(uint256 poolId) external;
    function joinComputePool(uint256 poolId, address provider, address[] memory nodekeys, bytes[] memory signatures)
        external;
    function leaveComputePool(uint256 poolId, address provider, address nodekey) external;
    function changeComputePool(
        uint256 fromPoolId,
        uint256 toPoolId,
        address[] memory nodekeys,
        bytes[] memory signatures
    ) external;
    function updateComputePoolURI(uint256 poolId, string calldata poolDataURI) external;
    function blacklistProvider(uint256 poolId, address provider) external;
    function blacklistNode(uint256 poolId, address provider, address nodekey) external;
    function getComputePool(uint256 poolId) external view returns (PoolInfo memory);
    function getComputePoolProviders(uint256 poolId) external view returns (address[] memory);
    function getComputePoolNodes(uint256 poolId) external view returns (address[] memory);
    function getNodeWork(uint256 poolId, address nodekey) external view returns (WorkInterval[] memory);
    function getProviderActiveNodesInPool(uint256 poolId, address provider) external view returns (uint256);
}
