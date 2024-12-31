// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IComputeRegistry.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract ComputeRegistry is IComputeRegistry {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    mapping(address => ComputeProvider) public providers;
    EnumerableMap.AddressToUintMap private nodeSubkeyToIndex;

    function register(address _provider) external returns (bool) {
        ComputeProvider storage cp = providers[_provider];
        if (cp.providerAddress == address(0)) {
            cp.providerAddress = _provider;
            cp.isWhitelisted = false;
            cp.nodes = new ComputeNode[](0);
            return true;
        }
        return false;
    }

    function deregister(address _provider) external returns (bool) {
        if (providers[_provider].providerAddress == address(0)) {
            return false;
        } else {
            delete providers[_provider];
            return true;
        }
    }

    function addComputeNode(address provider, address subkey, string calldata specsURI) external returns (uint256) {
        ComputeProvider storage cp = providers[provider];
        ComputeNode memory cn;
        cn.specsURI = specsURI;
        cn.benchmarkScore = 0;
        cn.isActive = true;
        cn.subkey = subkey;
        cp.nodes.push(cn);
        uint256 index = cp.nodes.length - 1;
        nodeSubkeyToIndex.set(subkey, index);
        return index;
    }

    function removeComputeNode(address provider, address subkey) external returns (bool) {
        ComputeProvider storage cp = providers[provider];
        uint256 index = nodeSubkeyToIndex.get(subkey);
        ComputeNode memory cn = cp.nodes[index];
        // should throw if subkey doesn't exist, but we'll check anyway
        if (cn.subkey != subkey) {
            return false;
        }
        // swap node we're removing with last node
        cp.nodes[index] = cp.nodes[cp.nodes.length - 1];
        // update index of the node we swapped
        nodeSubkeyToIndex.set(cp.nodes[index].subkey, index);
        // remove last node
        cp.nodes.pop();
        nodeSubkeyToIndex.remove(subkey);
        return true;
    }

    function updateNodeURI(address provider, address subkey, string calldata specsURI) external {
        ComputeNode storage cn = providers[provider].nodes[nodeSubkeyToIndex.get(subkey)];
        cn.specsURI = specsURI;
    }

    function updateNodeStatus(address provider, address subkey, bool isActive) external {
        ComputeNode storage cn = providers[provider].nodes[nodeSubkeyToIndex.get(subkey)];
        cn.isActive = isActive;
    }

    function updateNodeBenchmark(address provider, address subkey, uint256 benchmarkScore) external {
        ComputeNode storage cn = providers[provider].nodes[nodeSubkeyToIndex.get(subkey)];
        cn.benchmarkScore = benchmarkScore;
    }

    function setWhitelistStatus(address provider, bool status) external {
        providers[provider].isWhitelisted = status;
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
