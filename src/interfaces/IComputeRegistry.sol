// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

event ProviderRegistered(address provider, uint256 stake);

event ProviderDeregistered(address provider);

event ProviderWhitelisted(address provider);

event ProviderBlacklisted(address provider);

event ComputeNodeAdded(address provider, address nodekey, string specsURI);

event ComputeNodeRemoved(address provider, address nodekey);

event ComputeNodeValidated(address provider, address nodekey);

event ComputeNodeInvalidated(address provider, address nodekey);

interface IComputeRegistry is IAccessControlEnumerable {
    struct ComputeNode {
        address provider;
        address subkey;
        string specsURI;
        uint32 computeUnits; // H100 equivalents
        uint32 benchmarkScore; // some fidelity metric
        bool isActive;
        bool isValidated;
    }

    struct ComputeProvider {
        address providerAddress;
        bool isWhitelisted;
        uint32 activeNodes;
        ComputeNode[] nodes;
    }

    function setComputePool(address computePool) external;
    function register(address provider) external returns (bool);
    function deregister(address provider) external returns (bool);
    function addComputeNode(address provider, address subkey, uint256 computeUnits, string calldata specsURI)
        external
        returns (uint256);
    function removeComputeNode(address provider, address subkey) external returns (bool);
    function updateNodeURI(address provider, address subkey, string calldata specsURI) external;
    function updateNodeStatus(address provider, address subkey, bool isActive) external;
    function updateNodeBenchmark(address provider, address subkey, uint256 benchmarkScore) external;
    function setWhitelistStatus(address provider, bool status) external;
    function getWhitelistStatus(address provider) external view returns (bool);
    function setNodeValidationStatus(address provider, address subkey, bool status) external;
    function getNodeValidationStatus(address provider, address subkey) external returns (bool);
    function getProvider(address provider) external view returns (ComputeProvider memory);
    function getProviderActiveNodes(address provider) external view returns (uint32);
    function getProviderTotalNodes(address provider) external view returns (uint32);
    function getProviderAddressList() external view returns (address[] memory);
    function getProviderValidatedNodes(address provider, bool filterForActive)
        external
        view
        returns (address[] memory);
    function getNodes(address provider, uint256 page, uint256 limit) external view returns (ComputeNode[] memory);
    function getNode(address provider, address subkey) external view returns (ComputeNode memory);
    function getNode(address subkey) external view returns (ComputeNode memory);
    function getNodeComputeUnits(address subkey) external view returns (uint256);
    function getNodeProvider(address subkey) external view returns (address);
    function getNodeContractData(address subkey) external view returns (address, uint32, bool, bool);
    function checkProviderExists(address provider) external view returns (bool);
    function getProviderTotalCompute(address provider) external view returns (uint256);
}
