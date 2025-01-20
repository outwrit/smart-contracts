// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IComputePool.sol";
import "./interfaces/IDomainRegistry.sol";
import "./interfaces/IRewardsDistributor.sol";
import "./RewardsDistributorFactory.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ComputePool is IComputePool, AccessControlEnumerable {
    using MessageHashUtils for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct PoolState {
        mapping(address => uint256) providerActiveNodes;
        EnumerableSet.AddressSet poolProviders;
        EnumerableSet.AddressSet poolNodes;
        EnumerableSet.AddressSet blacklistedProviders;
        EnumerableSet.AddressSet blacklistedNodes;
        IRewardsDistributor rewardsDistributor;
    }

    bytes32 public constant PRIME_ROLE = keccak256("PRIME_ROLE");

    mapping(uint256 => PoolInfo) public pools;
    uint256 public poolIdCounter;
    IComputeRegistry public computeRegistry;
    IDomainRegistry public domainRegistry;
    RewardsDistributorFactory public rewardsDistributorFactory;
    IERC20 public AIToken;

    mapping(uint256 => PoolState) private poolStates;

    constructor(
        address _primeAdmin,
        IDomainRegistry _domainRegistry,
        IComputeRegistry _computeRegistry,
        RewardsDistributorFactory _rewardsDistributorFactory,
        IERC20 _AIToken
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _primeAdmin);
        _grantRole(PRIME_ROLE, _primeAdmin);
        poolIdCounter = 0;
        AIToken = _AIToken;
        computeRegistry = _computeRegistry;
        domainRegistry = _domainRegistry;
        rewardsDistributorFactory = _rewardsDistributorFactory;
    }

    function _copyAddresses(address[] memory source) internal pure returns (address[] memory target) {
        uint256 len = source.length;
        target = new address[](len);
        assembly {
            // Each element is 32 bytes in memory
            let byteLen := mul(len, 32)
            let srcPtr := add(source, 0x20)
            let destPtr := add(target, 0x20)
            let endPtr := add(srcPtr, byteLen)

            for {} lt(srcPtr, endPtr) {} {
                mstore(destPtr, mload(srcPtr))
                srcPtr := add(srcPtr, 32)
                destPtr := add(destPtr, 32)
            }
        }
    }

    function _verifyPoolInvite(
        uint256 domainId,
        uint256 poolId,
        address computeManagerKey,
        address nodekey,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encodePacked(domainId, poolId, nodekey)).toEthSignedMessageHash();
        return SignatureChecker.isValidSignatureNow(computeManagerKey, messageHash, signature);
    }

    function createComputePool(
        uint256 domainId,
        address computeManagerKey,
        string calldata poolName,
        string calldata poolDataURI,
        uint256 computeLimit
    ) external returns (uint256) {
        require(domainRegistry.get(domainId).domainId == domainId, "ComputePool: domain does not exist");

        pools[poolIdCounter] = PoolInfo({
            poolId: poolIdCounter,
            domainId: domainId,
            poolName: poolName,
            creator: msg.sender,
            computeManagerKey: computeManagerKey,
            creationTime: block.timestamp,
            startTime: 0,
            endTime: 0,
            poolDataURI: poolDataURI,
            poolValidationLogic: address(0),
            totalCompute: 0,
            computeLimit: computeLimit,
            status: PoolStatus.PENDING
        });

        poolStates[poolIdCounter].rewardsDistributor =
            rewardsDistributorFactory.createRewardsDistributor(computeRegistry, poolIdCounter);

        poolIdCounter++;

        emit ComputePoolCreated(poolIdCounter - 1, domainId, msg.sender);

        return poolIdCounter - 1;
    }

    function startComputePool(uint256 poolId) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].status == PoolStatus.PENDING, "ComputePool: pool is not pending");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can start pool");

        pools[poolId].startTime = block.timestamp;
        pools[poolId].status = PoolStatus.ACTIVE;

        emit ComputePoolStarted(poolId, block.timestamp);
    }

    function endComputePool(uint256 poolId) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].status == PoolStatus.ACTIVE, "ComputePool: pool is not active");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can end pool");

        pools[poolId].endTime = block.timestamp;
        pools[poolId].status = PoolStatus.COMPLETED;

        poolStates[poolId].rewardsDistributor.endRewards();

        emit ComputePoolEnded(poolId);
    }

    function joinComputePool(uint256 poolId, address provider, address[] memory nodekey, bytes[] memory signatures)
        external
    {
        require(msg.sender == provider || msg.sender == address(this), "ComputePool: only provider can join pool");
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].status == PoolStatus.ACTIVE, "ComputePool: pool is not active");
        require(!poolStates[poolId].blacklistedProviders.contains(provider), "ComputePool: provider is blacklisted");
        require(computeRegistry.getWhitelistStatus(provider), "ComputePool: provider is not whitelisted");

        for (uint256 i = 0; i < nodekey.length; i++) {
            require(!poolStates[poolId].blacklistedNodes.contains(nodekey[i]), "ComputePool: node is blacklisted");
        }

        if (!poolStates[poolId].poolProviders.contains(provider)) {
            poolStates[poolId].poolProviders.add(provider);
        }
        for (uint256 i = 0; i < nodekey.length; i++) {
            IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(provider, nodekey[i]);
            require(node.provider == provider, "ComputePool: node does not exist");
            require(node.isActive == false, "ComputePool: node can only be in one pool at a time");
            require(computeRegistry.getNodeValidationStatus(provider, nodekey[i]), "ComputePool: node is not validated");
            require(
                _verifyPoolInvite(
                    pools[poolId].domainId, poolId, pools[poolId].computeManagerKey, nodekey[i], signatures[i]
                ),
                "ComputePool: invalid invite"
            );
            uint256 addedCompute = pools[poolId].totalCompute + node.computeUnits;
            if (pools[poolId].computeLimit > 0) {
                require(addedCompute < pools[poolId].computeLimit, "ComputePool: pool is at capacity");
            }
            poolStates[poolId].poolNodes.add(nodekey[i]);
            poolStates[poolId].rewardsDistributor.joinPool(nodekey[i], node.computeUnits);
            pools[poolId].totalCompute += node.computeUnits;
            poolStates[poolId].providerActiveNodes[provider]++;
            computeRegistry.updateNodeStatus(provider, nodekey[i], true);
        }
        emit ComputePoolJoined(poolId, provider, nodekey);
    }

    function leaveComputePool(uint256 poolId, address provider, address nodekey) external {
        require(msg.sender == provider || msg.sender == address(this), "ComputePool: only provider can leave pool");
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");

        if (nodekey == address(0)) {
            // Remove all nodes belonging to that provider
            address[] memory nodes = poolStates[poolId].poolNodes.values();
            for (uint256 i = 0; i < nodes.length; ++i) {
                IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(provider, nodes[i]);
                if (node.provider == provider) {
                    poolStates[poolId].poolNodes.remove(nodes[i]);
                    // Mark last interval's leaveTime
                    poolStates[poolId].rewardsDistributor.leavePool(nodes[i]);
                    pools[poolId].totalCompute -= node.computeUnits;
                    poolStates[poolId].providerActiveNodes[provider]--;
                    computeRegistry.updateNodeStatus(provider, nodes[i], false);
                    emit ComputePoolLeft(poolId, provider, nodes[i]);
                }
            }
        } else {
            // Just remove the single node
            IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(provider, nodekey);
            if (node.provider == provider) {
                if (poolStates[poolId].poolNodes.remove(nodekey)) {
                    poolStates[poolId].rewardsDistributor.leavePool(nodekey);
                    pools[poolId].totalCompute -= node.computeUnits;
                    poolStates[poolId].providerActiveNodes[provider]--;
                    computeRegistry.updateNodeStatus(provider, nodekey, false);
                    emit ComputePoolLeft(poolId, provider, nodekey);
                }
            }
        }
        if (poolStates[poolId].providerActiveNodes[provider] == 0) {
            poolStates[poolId].poolProviders.remove(provider);
        }
    }

    function changeComputePool(
        uint256 fromPoolId,
        uint256 toPoolId,
        address[] memory nodekeys,
        bytes[] memory signatures
    ) external {
        require(pools[fromPoolId].poolId == fromPoolId, "ComputePool: source pool does not exist");
        require(pools[toPoolId].poolId == toPoolId, "ComputePool: dest pool does not exist");
        require(pools[toPoolId].status == PoolStatus.ACTIVE, "ComputePool: dest pool is not ready");
        address provider = msg.sender;

        if (nodekeys.length == this.getProviderActiveNodesInPool(fromPoolId, provider)) {
            // If all nodes are being moved, just move the provider
            this.leaveComputePool(fromPoolId, provider, address(0));
        } else {
            for (uint256 i = 0; i < nodekeys.length; i++) {
                this.leaveComputePool(fromPoolId, provider, nodekeys[i]);
            }
        }
        this.joinComputePool(toPoolId, provider, nodekeys, signatures);
    }

    //
    // Management functions
    //
    function updateComputePoolURI(uint256 poolId, string calldata poolDataURI) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can update pool URI");

        pools[poolId].poolDataURI = poolDataURI;

        emit ComputePoolURIUpdated(poolId, poolDataURI);
    }

    function updateComputeLimit(uint256 poolId, uint256 computeLimit) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can update pool limit");

        pools[poolId].computeLimit = computeLimit;

        emit ComputePoolLimitUpdated(poolId, computeLimit);
    }

    function blacklistProvider(uint256 poolId, address provider) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can blacklist provider");

        // Remove from active set
        poolStates[poolId].poolProviders.remove(provider);

        // use memcpy to copy array so we're not iterating over a changing set
        address[] memory nodes = _copyAddresses(poolStates[poolId].poolNodes.values());
        // Remove all nodes for that provider
        for (uint256 i = 0; i < nodes.length; ++i) {
            IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(provider, nodes[i]);
            if (node.provider == provider) {
                poolStates[poolId].poolNodes.remove(nodes[i]);
                // Mark last interval's leaveTime
                poolStates[poolId].rewardsDistributor.leavePool(nodes[i]);
                pools[poolId].totalCompute -= node.computeUnits;
                poolStates[poolId].providerActiveNodes[provider]--;
                computeRegistry.updateNodeStatus(provider, nodes[i], false);
            }
        }

        // Add to blacklist set
        poolStates[poolId].blacklistedProviders.add(provider);
        emit ComputePoolProviderBlacklisted(poolId, provider);
    }

    function blacklistNode(uint256 poolId, address provider, address nodekey) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can blacklist node");

        if (poolStates[poolId].poolNodes.contains(nodekey)) {
            IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(provider, nodekey);
            require(node.provider == provider, "ComputePool: node does not exist");
            poolStates[poolId].rewardsDistributor.leavePool(nodekey);
            poolStates[poolId].poolNodes.remove(nodekey);
            pools[poolId].totalCompute -= node.computeUnits;
            poolStates[poolId].providerActiveNodes[node.provider]--;
            computeRegistry.updateNodeStatus(node.provider, nodekey, false);
            if (poolStates[poolId].providerActiveNodes[node.provider] == 0) {
                poolStates[poolId].poolProviders.remove(node.provider);
            }
        }
        poolStates[poolId].blacklistedNodes.add(nodekey);
        emit ComputePoolNodeBlacklisted(poolId, provider, nodekey);
    }

    //
    // View functions
    //
    function getComputePool(uint256 poolId) external view returns (PoolInfo memory) {
        return pools[poolId];
    }

    function getComputePoolProviders(uint256 poolId) external view returns (address[] memory) {
        return poolStates[poolId].poolProviders.values();
    }

    function getComputePoolNodes(uint256 poolId) external view returns (address[] memory) {
        return poolStates[poolId].poolNodes.values();
    }

    function getProviderActiveNodesInPool(uint256 poolId, address provider) external view returns (uint256) {
        return poolStates[poolId].providerActiveNodes[provider];
    }

    function getRewardToken() external view returns (address) {
        return address(AIToken);
    }

    function getRewardDistributorForPool(uint256 poolId) external view returns (IRewardsDistributor) {
        return poolStates[poolId].rewardsDistributor;
    }

    function getComputePoolTotalCompute(uint256 poolId) external view returns (uint256) {
        return pools[poolId].totalCompute;
    }

    function getComputePoolBlacklistedProviders(uint256 poolId) external view returns (address[] memory) {
        return poolStates[poolId].blacklistedProviders.values();
    }

    function getComputePoolBlacklistedNodes(uint256 poolId) external view returns (address[] memory) {
        return poolStates[poolId].blacklistedNodes.values();
    }

    function isProviderBlacklistedFromPool(uint256 poolId, address provider) external view returns (bool) {
        return poolStates[poolId].blacklistedProviders.contains(provider);
    }

    function isNodeBlacklistedFromPool(uint256 poolId, address nodekey) external view returns (bool) {
        return poolStates[poolId].blacklistedNodes.contains(nodekey);
    }
}
