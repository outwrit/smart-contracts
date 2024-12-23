// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

event ProviderRegistered(address provider, uint256 stake);

event ProviderDeregistered(address provider);

event ProviderWhitelisted(address provider);

event ProviderBlacklisted(address provider);

event ComputeNodeAdded(address provider, address nodekey, string specsURI);

event ComputeNodeRemoved(address provider, address nodekey);

interface IComputeRegistry {
    struct ComputeNode {
        address provider;
        uint256 nodeId;
        string specsURI;
        uint256 benchmarkScore;
        bool isActive;
    }

    struct ComputeProvider {
        address providerAddress;
        uint256 stakeAmount;
        bool isWhitelisted;
        ComputeNode[] nodes;
    }

    function register(address provider) external returns (bool);
    function deregister(address provider) external returns (bool);
    function addComputeNode(address provider, address subkey, string calldata specsURI) external returns (uint256);
    function removeComputeNode(address provider, address subkey) external returns (bool);
    function updateNodeURI(address subkey, string calldata specsURI) external;
    function updateNodeStatus(address subkey, bool isActive) external;
    function updateNodeBenchmark(address provider, uint256 nodeId, uint256 benchmarkScore) external;
    function setWhitelistStatus(address provider, bool status) external;
    function getProvider(address provider) external view returns (ComputeProvider memory);
    function getNodes(address provider, uint256 page) external view returns (ComputeNode[] memory);
}
