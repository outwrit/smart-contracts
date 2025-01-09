// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IComputePool.sol";
import "./interfaces/IDomainRegistry.sol";
import "./RewardsDistributor.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ComputePool is IComputePool, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant PRIME_ROLE = keccak256("PRIME_ROLE");

    mapping(uint256 => PoolInfo) public pools;
    uint256 public poolIdCounter;
    IComputeRegistry public computeRegistry;
    IDomainRegistry public domainRegistry;
    RewardsDistributor public rewardsDistributor;
    IERC20 public PrimeToken;

    mapping(uint256 => mapping(address => WorkInterval[])) public nodeWork;

    mapping(uint256 => EnumerableSet.AddressSet) private _poolProviders;
    mapping(uint256 => EnumerableSet.AddressSet) private _poolNodes;

    mapping(uint256 => EnumerableSet.AddressSet) private _blacklistedProviders;
    mapping(uint256 => EnumerableSet.AddressSet) private _blacklistedNodes;

    mapping(address => uint256) public providerActiveNodes;

    constructor(
        address _primeAdmin,
        IDomainRegistry _domainRegistry,
        IComputeRegistry _computeRegistry,
        IERC20 _PrimeToken
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _primeAdmin);
        _grantRole(PRIME_ROLE, _primeAdmin);
        poolIdCounter = 0;
        PrimeToken = _PrimeToken;
        computeRegistry = _computeRegistry;
        domainRegistry = _domainRegistry;
    }

    function _verifyPoolInvite(
        uint256 domainId,
        uint256 poolId,
        address computeManagerKey,
        address nodekey,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encodePacked(domainId, poolId, nodekey));
        return SignatureChecker.isValidERC1271SignatureNow(computeManagerKey, messageHash, signature);
    }

    function createComputePool(
        uint256 domainId,
        address creator,
        address computeManagerKey,
        string calldata poolDataURI
    ) external {
        require(domainRegistry.get(domainId).domainId == domainId, "ComputePool: domain does not exist");

        pools[poolIdCounter] = PoolInfo({
            poolId: poolIdCounter,
            domainId: domainId,
            creator: creator,
            computeManagerKey: computeManagerKey,
            creationTime: block.timestamp,
            startTime: 0,
            endTime: 0,
            poolDataURI: poolDataURI,
            poolValidationLogic: address(0),
            totalCompute: 0,
            status: PoolStatus.PENDING
        });

        rewardsDistributor = new RewardsDistributor(IComputePool(address(this)), computeRegistry, poolIdCounter);

        poolIdCounter++;
    }

    function startComputePool(uint256 poolId) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].status == PoolStatus.PENDING, "ComputePool: pool is not pending");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can start pool");

        pools[poolId].startTime = block.timestamp;
        pools[poolId].status = PoolStatus.ACTIVE;
    }

    function endComputePool(uint256 poolId) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].status == PoolStatus.ACTIVE, "ComputePool: pool is not active");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can end pool");

        pools[poolId].endTime = block.timestamp;
        pools[poolId].status = PoolStatus.COMPLETED;
    }

    function joinComputePool(uint256 poolId, address provider, address[] memory nodekey, bytes[] memory signatures)
        external
    {
        require(msg.sender == provider, "ComputePool: only provider can join pool");
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].status == PoolStatus.PENDING, "ComputePool: pool is not pending");
        require(!_blacklistedProviders[poolId].contains(provider), "ComputePool: provider is blacklisted");
        require(computeRegistry.getWhitelistStatus(provider), "ComputePool: provider is not whitelisted");

        for (uint256 i = 0; i < nodekey.length; i++) {
            require(!_blacklistedNodes[poolId].contains(nodekey[i]), "ComputePool: node is blacklisted");
        }

        _poolProviders[poolId].add(provider);
        for (uint256 i = 0; i < nodekey.length; i++) {
            IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(provider, nodekey[i]);
            require(node.provider == provider, "ComputePool: node does not exist");
            require(computeRegistry.getNodeValidationStatus(provider, nodekey[i]), "ComputePool: node is not validated");
            require(
                _verifyPoolInvite(
                    pools[poolId].domainId, poolId, pools[poolId].computeManagerKey, nodekey[i], signatures[i]
                ),
                "ComputePool: invalid invite"
            );
            _poolNodes[poolId].add(nodekey[i]);
            _addJoinTime(poolId, nodekey[i]);
            pools[poolId].totalCompute += node.computeUnits;
            providerActiveNodes[provider]++;
            computeRegistry.updateNodeStatus(provider, nodekey[i], true);
        }
    }

    function leaveComputePool(uint256 poolId, address provider, address nodekey) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].status != PoolStatus.COMPLETED, "ComputePool: pool is completed");
        require(msg.sender == provider, "ComputePool: only provider can leave pool");

        if (nodekey == address(0)) {
            _poolProviders[poolId].remove(provider);

            // Remove all nodes belonging to that provider
            address[] memory nodes = _poolNodes[poolId].values();
            for (uint256 i = 0; i < nodes.length;) {
                IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(provider, nodes[i]);
                if (node.provider == provider) {
                    _poolNodes[poolId].remove(nodes[i]);
                    // Mark last interval's leaveTime
                    _updateLeaveTime(poolId, nodekey);
                    pools[poolId].totalCompute -= node.computeUnits;
                    providerActiveNodes[provider]--;
                    computeRegistry.updateNodeStatus(provider, nodes[i], false);
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            // Just remove the single node
            IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(provider, nodekey);
            if (node.provider == provider) {
                if (_poolNodes[poolId].remove(nodekey)) {
                    _updateLeaveTime(poolId, nodekey);
                    pools[poolId].totalCompute -= node.computeUnits;
                    providerActiveNodes[provider]--;
                    computeRegistry.updateNodeStatus(provider, nodekey, false);
                }
            }
        }
    }

    //
    // Management functions
    //
    function updateComputePoolURI(uint256 poolId, string calldata poolDataURI) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can update pool URI");

        pools[poolId].poolDataURI = poolDataURI;
    }

    function blacklistProvider(uint256 poolId, address provider) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can blacklist provider");

        // Remove from active set
        _poolProviders[poolId].remove(provider);

        // Remove all nodes for that provider
        address[] memory nodes = _poolNodes[poolId].values();
        for (uint256 i = 0; i < nodes.length;) {
            IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(provider, nodes[i]);
            if (node.provider == provider) {
                _poolNodes[poolId].remove(nodes[i]);
                // Mark last interval's leaveTime
                _updateLeaveTime(poolId, nodes[i]);
                pools[poolId].totalCompute -= node.computeUnits;
                providerActiveNodes[provider]--;
                computeRegistry.updateNodeStatus(provider, nodes[i], false);
            }
            unchecked {
                ++i;
            }
        }

        // Add to blacklist set
        _blacklistedProviders[poolId].add(provider);
    }

    function blacklistNode(uint256 poolId, address nodekey) external {
        require(pools[poolId].poolId == poolId, "ComputePool: pool does not exist");
        require(pools[poolId].creator == msg.sender, "ComputePool: only creator can blacklist node");

        _poolNodes[poolId].remove(nodekey);
        _blacklistedNodes[poolId].add(nodekey);
        _updateLeaveTime(poolId, nodekey);
        IComputeRegistry.ComputeNode memory node = computeRegistry.getNode(msg.sender, nodekey);
        pools[poolId].totalCompute -= node.computeUnits;
        providerActiveNodes[node.provider]--;
        computeRegistry.updateNodeStatus(msg.sender, nodekey, false);
    }

    //
    // View functions
    //
    function getComputePool(uint256 poolId) external view returns (PoolInfo memory) {
        return pools[poolId];
    }

    function getComputePoolProviders(uint256 poolId) external view returns (address[] memory) {
        return _poolProviders[poolId].values();
    }

    function getComputePoolNodes(uint256 poolId) external view returns (address[] memory) {
        return _poolNodes[poolId].values();
    }

    function getNodeWork(uint256 poolId, address nodekey) external view returns (WorkInterval[] memory) {
        return nodeWork[poolId][nodekey];
    }

    function getProviderActiveNodes(address provider) external view returns (uint256) {
        return providerActiveNodes[provider];
    }

    function _updateLeaveTime(uint256 poolId, address nodekey) private {
        nodeWork[poolId][nodekey][nodeWork[poolId][nodekey].length - 1].leaveTime = block.timestamp;
    }

    function _addJoinTime(uint256 poolId, address nodekey) private {
        nodeWork[poolId][nodekey].push(WorkInterval({poolId: 0, joinTime: block.timestamp, leaveTime: 0}));
    }
}
