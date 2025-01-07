// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IComputePool.sol";
import "./interfaces/IDomainRegistry.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract ComputePoolManager is IComputePoolManager, AccessControl {
    bytes32 public constant PRIME_ROLE = keccak256("PRIME_ROLE");

    mapping(uint256 => PoolInfo) public pools;
    uint256 public poolIdCounter;
    IComputeRegistry public computeRegistry;
    IDomainRegistry public domainRegistry;
    IRewardsDistributor public rewardsDistributor;
    IERC20 public PrimeToken;

    mapping(uint256 => mapping(address => bool)) public blacklistedProviders;
    mapping(uint256 => mapping(address => bool)) public blacklistedNodes;

    mapping(uint256 => address[]) public poolProviders;
    mapping(uint256 => address[]) public poolNodes;

    constructor(
        address _primeAdmin,
        IDomainRegistry _domainRegistry,
        IRewardsDistributor _rewardsDistributor,
        IComputeRegistry _computeRegistry,
        IERC20 _PrimeToken
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _primeAdmin);
        _grantRole(PRIME_ROLE, _primeAdmin);
        poolIdCounter = 0;
        PrimeToken = _PrimeToken;
        computeRegistry = _computeRegistry;
        domainRegistry = _domainRegistry;
        rewardsDistributor = _rewardsDistributor;
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
        uint256 rewardRate,
        string calldata poolDataURI
    ) external {
        require(domainRegistry.get(domainId).domainId == domainId, "ComputePoolManager: domain does not exist");

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
            totalFunds: 0,
            rewardRate: rewardRate,
            status: PoolStatus.PENDING
        });

        poolIdCounter++;
    }

    function startComputePool(uint256 poolId) external {
        require(pools[poolId].poolId == poolId, "ComputePoolManager: pool does not exist");
        require(pools[poolId].status == PoolStatus.PENDING, "ComputePoolManager: pool is not pending");
        require(pools[poolId].creator == msg.sender, "ComputePoolManager: only creator can start pool");

        pools[poolId].startTime = block.timestamp;
        pools[poolId].status = PoolStatus.ACTIVE;
    }

    function endComputePool(uint256 poolId) external {
        require(pools[poolId].poolId == poolId, "ComputePoolManager: pool does not exist");
        require(pools[poolId].status == PoolStatus.ACTIVE, "ComputePoolManager: pool is not active");
        require(pools[poolId].creator == msg.sender, "ComputePoolManager: only creator can end pool");

        pools[poolId].endTime = block.timestamp;
        pools[poolId].status = PoolStatus.COMPLETED;
    }

    function joinComputePool(uint256 poolId, address provider, address[] memory nodekey, bytes[] memory signatures)
        external
    {
        require(pools[poolId].poolId == poolId, "ComputePoolManager: pool does not exist");
        require(pools[poolId].status == PoolStatus.PENDING, "ComputePoolManager: pool is not pending");
        require(!blacklistedProviders[poolId][provider], "ComputePoolManager: provider is blacklisted");
        require(msg.sender == provider, "ComputePoolManager: only provider can join pool");

        for (uint256 i = 0; i < nodekey.length; i++) {
            require(!blacklistedNodes[poolId][nodekey[i]], "ComputePoolManager: node is blacklisted");
        }

        poolProviders[poolId].push(provider);
        for (uint256 i = 0; i < nodekey.length; i++) {
            require(
                computeRegistry.getNode(provider, nodekey[i]).provider == provider,
                "ComputePoolManager: node does not exist"
            );
            require(
                _verifyPoolInvite(
                    pools[poolId].domainId, poolId, pools[poolId].computeManagerKey, nodekey[i], signatures[i]
                ),
                "ComputePoolManager: invalid invite"
            );
            poolNodes[poolId].push(nodekey[i]);
        }
    }

    function leaveComputePool(uint256 poolId, address provider) external {
        require(pools[poolId].poolId == poolId, "ComputePoolManager: pool does not exist");
        require(pools[poolId].status != PoolStatus.COMPLETED, "ComputePoolManager: pool is completed");
        require(msg.sender == provider, "ComputePoolManager: only provider can leave pool");

        for (uint256 i = 0; i < poolProviders[poolId].length; i++) {
            if (poolProviders[poolId][i] == provider) {
                poolProviders[poolId][i] = poolProviders[poolId][poolProviders[poolId].length - 1];
                poolProviders[poolId].pop();
                break;
            }
        }
    }

    //
    // Management functions
    //
    function updateComputePoolURI(uint256 poolId, string calldata poolDataURI) external {
        require(pools[poolId].poolId == poolId, "ComputePoolManager: pool does not exist");
        require(pools[poolId].creator == msg.sender, "ComputePoolManager: only creator can update pool URI");

        pools[poolId].poolDataURI = poolDataURI;
    }

    function blacklistProvider(uint256 poolId, address provider) external {
        require(pools[poolId].poolId == poolId, "ComputePoolManager: pool does not exist");
        require(pools[poolId].creator == msg.sender, "ComputePoolManager: only creator can blacklist provider");

        for (uint256 i = 0; i < poolProviders[poolId].length; i++) {
            if (poolProviders[poolId][i] == provider) {
                poolProviders[poolId][i] = poolProviders[poolId][poolProviders[poolId].length - 1];
                poolProviders[poolId].pop();
                break;
            }
        }

        for (uint256 i = 0; i < poolNodes[poolId].length; i++) {
            if (computeRegistry.getNode(provider, poolNodes[poolId][i]).provider == provider) {
                poolNodes[poolId][i] = poolNodes[poolId][poolNodes[poolId].length - 1];
                poolNodes[poolId].pop();
                break;
            }
        }

        blacklistedProviders[poolId][provider] = true;
    }

    function blacklistNode(uint256 poolId, address nodekey) external {
        require(pools[poolId].poolId == poolId, "ComputePoolManager: pool does not exist");
        require(pools[poolId].creator == msg.sender, "ComputePoolManager: only creator can blacklist node");

        for (uint256 i = 0; i < poolNodes[poolId].length; i++) {
            if (poolNodes[poolId][i] == nodekey) {
                poolNodes[poolId][i] = poolNodes[poolId][poolNodes[poolId].length - 1];
                poolNodes[poolId].pop();
                break;
            }
        }

        blacklistedNodes[poolId][nodekey] = true;
    }

    //
    // View functions
    //
    function getComputePool(uint256 poolId) external view returns (PoolInfo memory) {
        return pools[poolId];
    }

    function getComputePoolProviders(uint256 poolId) external view returns (address[] memory) {
        return poolProviders[poolId];
    }

    function getComputePoolNodes(uint256 poolId) external view returns (address[] memory) {
        return poolNodes[poolId];
    }
}
