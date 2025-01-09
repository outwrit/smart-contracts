// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IComputeRegistry.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract ComputeRegistry is IComputeRegistry, AccessControl {
    bytes32 public constant PRIME_ROLE = keccak256("PRIME_ROLE");
    bytes32 public constant COMPUTE_POOL_ROLE = keccak256("COMPUTE_POOL_ROLE");

    using EnumerableMap for EnumerableMap.AddressToUintMap;

    mapping(address => ComputeProvider) public providers;
    EnumerableMap.AddressToUintMap private nodeSubkeyToIndex;

    constructor(address primeAdmin) {
        _grantRole(DEFAULT_ADMIN_ROLE, primeAdmin);
        _grantRole(PRIME_ROLE, primeAdmin);
    }

    function setComputePool(address computePool) external onlyRole(PRIME_ROLE) {
        _grantRole(COMPUTE_POOL_ROLE, computePool);
    }

    function register(address provider) external onlyRole(PRIME_ROLE) returns (bool) {
        ComputeProvider storage cp = providers[provider];
        if (cp.providerAddress == address(0)) {
            cp.providerAddress = provider;
            cp.isWhitelisted = false;
            cp.activeNodes = 0;
            cp.nodes = new ComputeNode[](0);
            return true;
        }
        return false;
    }

    function deregister(address provider) external onlyRole(PRIME_ROLE) returns (bool) {
        if (providers[provider].providerAddress == address(0)) {
            return false;
        } else {
            delete providers[provider];
            return true;
        }
    }

    function addComputeNode(address provider, address subkey, uint256 computeUnits, string calldata specsURI)
        external
        onlyRole(PRIME_ROLE)
        returns (uint256)
    {
        ComputeProvider storage cp = providers[provider];
        ComputeNode memory cn;
        cn.provider = provider;
        cn.computeUnits = uint32(computeUnits);
        cn.specsURI = specsURI;
        cn.benchmarkScore = 0;
        cn.isActive = true;
        cn.subkey = subkey;
        cp.nodes.push(cn);
        uint256 index = cp.nodes.length - 1;
        nodeSubkeyToIndex.set(subkey, index);
        return index;
    }

    function removeComputeNode(address provider, address subkey) external onlyRole(PRIME_ROLE) returns (bool) {
        ComputeProvider storage cp = providers[provider];
        uint256 index = nodeSubkeyToIndex.get(subkey);
        ComputeNode memory cn = cp.nodes[index];
        // should throw if subkey doesn't exist, but we'll check anyway
        if (cn.subkey != subkey) {
            return false;
        }
        require(cn.isActive == false, "ComputeRegistry: node must be inactive to remove");
        // swap node we're removing with last node
        cp.nodes[index] = cp.nodes[cp.nodes.length - 1];
        // update index of the node we swapped
        nodeSubkeyToIndex.set(cp.nodes[index].subkey, index);
        // remove last node
        cp.nodes.pop();
        nodeSubkeyToIndex.remove(subkey);
        return true;
    }

    function updateNodeURI(address provider, address subkey, string calldata specsURI) external onlyRole(PRIME_ROLE) {
        ComputeNode storage cn = providers[provider].nodes[nodeSubkeyToIndex.get(subkey)];
        cn.specsURI = specsURI;
    }

    function updateNodeStatus(address provider, address subkey, bool isActive) external onlyRole(COMPUTE_POOL_ROLE) {
        ComputeNode storage cn = providers[provider].nodes[nodeSubkeyToIndex.get(subkey)];
        cn.isActive = isActive;
        if (isActive) {
            providers[provider].activeNodes++;
        } else {
            providers[provider].activeNodes--;
        }
    }

    function updateNodeBenchmark(address provider, address subkey, uint256 benchmarkScore)
        external
        onlyRole(PRIME_ROLE)
    {
        ComputeNode storage cn = providers[provider].nodes[nodeSubkeyToIndex.get(subkey)];
        cn.benchmarkScore = uint32(benchmarkScore);
    }

    function setWhitelistStatus(address provider, bool status) external onlyRole(PRIME_ROLE) {
        providers[provider].isWhitelisted = status;
    }

    function getWhitelistStatus(address provider) external view returns (bool) {
        return providers[provider].isWhitelisted;
    }

    function setNodeValidationStatus(address provider, address subkey, bool status) external onlyRole(PRIME_ROLE) {
        providers[provider].nodes[nodeSubkeyToIndex.get(subkey)].isValidated = status;
    }

    function getNodeValidationStatus(address provider, address subkey) external view returns (bool) {
        return providers[provider].nodes[nodeSubkeyToIndex.get(subkey)].isValidated;
    }

    function getProvider(address provider) external view returns (ComputeProvider memory) {
        return providers[provider];
    }

    function getNodes(address provider, uint256 page, uint256 limit) external view returns (ComputeNode[] memory) {
        if (page == 0 && limit == 0) {
            return providers[provider].nodes;
        } else {
            uint256 start = (page - 1) * limit;
            uint256 end = start + limit;
            if (end > providers[provider].nodes.length) {
                end = providers[provider].nodes.length;
            }
            ComputeNode[] memory result = new ComputeNode[](end - start);
            for (uint256 i = start; i < end; i++) {
                result[i - start] = providers[provider].nodes[i];
            }
            return result;
        }
    }

    function getNode(address provider, address subkey) external view returns (ComputeNode memory) {
        return providers[provider].nodes[nodeSubkeyToIndex.get(subkey)];
    }
}
