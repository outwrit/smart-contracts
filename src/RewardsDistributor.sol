// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IRewardsDistributor.sol";
import "./interfaces/IComputePool.sol";
import "./interfaces/IComputeRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

contract RewardsDistributor is IRewardsDistributor, AccessControlEnumerable {
    bytes32 public constant PRIME_ROLE = keccak256("PRIME_ROLE");
    bytes32 public constant FEDERATOR_ROLE = keccak256("FEDERATOR_ROLE");
    bytes32 public constant REWARDS_MANAGER_ROLE = keccak256("REWARDS_MANAGER_ROLE");
    bytes32 public constant COMPUTE_POOL_ROLE = keccak256("COMPUTE_POOL_ROLE");
    IComputePool public computePool;
    IComputeRegistry public computeRegistry;
    uint256 public poolId;
    IERC20 public rewardToken; // Token to distribute
    uint256 public rewardRatePerSecond; // Adjustable reward rate
    uint256 public globalRewardIndex; // Cumulative reward per computeUnit
    uint256 public lastUpdateTime; // Last time we updated globalRewardIndex
    uint256 public totalActiveComputeUnits;
    uint256 public endTime;

    struct NodeData {
        uint256 computeUnits;
        uint256 nodeRewardIndex; // Snapshot of globalRewardIndex at the time of last update
        uint256 unclaimedRewards; // Accumulated but not claimed
        bool isActive;
    }

    mapping(address => NodeData) public nodeInfo;

    constructor(IComputePool _computePool, IComputeRegistry _computeRegistry, uint256 _poolId) {
        computePool = _computePool;
        computeRegistry = _computeRegistry;
        poolId = _poolId;
        rewardRatePerSecond = 0;
        globalRewardIndex = 0;
        lastUpdateTime = block.timestamp;
        totalActiveComputeUnits = 0;
        rewardToken = IERC20(computePool.getRewardToken());
        lastUpdateTime = block.timestamp;
        _grantRole(COMPUTE_POOL_ROLE, address(computePool));
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // for now... we set the rewards manager to be federator by walking up the contract tree
        address primeContract = computePool.getRoleMember(PRIME_ROLE, 0);
        address federator = IAccessControlEnumerable(primeContract).getRoleMember(FEDERATOR_ROLE, 0);
        _grantRole(REWARDS_MANAGER_ROLE, federator);
    }

    function _updateGlobalIndex() internal {
        if (endTime > 0) {
            return; // no update if ended
        }
        uint256 currentTime = block.timestamp;
        if (currentTime == lastUpdateTime) {
            return; // no update if no time passed
        }

        uint256 timeDelta = currentTime - lastUpdateTime;
        // e.g. timeDelta * rewardRatePerSecond
        uint256 rewardToDistribute = timeDelta * rewardRatePerSecond;

        if (totalActiveComputeUnits > 0) {
            uint256 additionalIndex = rewardToDistribute / totalActiveComputeUnits;
            globalRewardIndex += additionalIndex;
        }

        lastUpdateTime = currentTime;
    }

    // Change the emission rate
    function setRewardRate(uint256 newRate) external onlyRole(REWARDS_MANAGER_ROLE) {
        _updateGlobalIndex();
        rewardRatePerSecond = newRate;
    }

    // Node joining
    function joinPool(address node, uint256 nodeComputeUnits) external onlyRole(COMPUTE_POOL_ROLE) {
        if (endTime > 0) {
            return; // no joining if ended
        }
        // Possibly require validations, checks, etc.
        _updateGlobalIndex();

        NodeData storage nd = nodeInfo[node];
        require(!nd.isActive, "Node already active");

        // Synchronize node index with the current global
        nd.nodeRewardIndex = globalRewardIndex;
        nd.computeUnits = nodeComputeUnits;
        nd.isActive = true;
        totalActiveComputeUnits += nodeComputeUnits;
    }

    // Node leaving
    function leavePool(address node) external onlyRole(COMPUTE_POOL_ROLE) {
        _updateGlobalIndex();

        NodeData storage nd = nodeInfo[node];
        require(nd.isActive, "Node not active");

        // Calculate newly accrued since last time
        uint256 delta = globalRewardIndex - nd.nodeRewardIndex;
        nd.unclaimedRewards += (delta * nd.computeUnits);

        // Remove from totals
        totalActiveComputeUnits -= nd.computeUnits;
        nd.isActive = false;
        nd.computeUnits = 0;
        nd.nodeRewardIndex = 0; // optional reset
    }

    // Claim
    function claimRewards(address node) external {
        _updateGlobalIndex();
        require(msg.sender == computeRegistry.getNodeProvider(node), "Unauthorized");

        NodeData storage nd = nodeInfo[node];

        // If still active, sync the newest portion
        if (nd.isActive) {
            uint256 delta = globalRewardIndex - nd.nodeRewardIndex;
            nd.unclaimedRewards += (delta * nd.computeUnits);
            nd.nodeRewardIndex = globalRewardIndex;
        }

        uint256 payableAmount = nd.unclaimedRewards;
        nd.unclaimedRewards = 0;

        // Transfer out (require contract has enough tokens)
        rewardToken.transfer(node, payableAmount);
    }

    function calculateRewards(address node) external view returns (uint256) {
        NodeData memory nd = nodeInfo[node];
        uint256 timeDelta;

        // If the node has never joined, or there are no active computeUnits in total, no extra rewards to calculate.
        if (!nd.isActive && nd.unclaimedRewards == 0) {
            return 0;
        }

        // 1. Calculate how many rewards would be distributed if we updated the global index now
        if (endTime > 0) {
            timeDelta = endTime - lastUpdateTime;
        } else {
            timeDelta = block.timestamp - lastUpdateTime;
        }
        uint256 rewardToDistribute = timeDelta * rewardRatePerSecond;

        // 2. Compute what the global reward index would be if we updated it this instant
        //    (without actually storing it).
        uint256 hypotheticalGlobalIndex = globalRewardIndex;
        if (totalActiveComputeUnits > 0) {
            uint256 additionalIndex = rewardToDistribute / totalActiveComputeUnits;
            hypotheticalGlobalIndex += additionalIndex;
        }

        // 3. Start from node's stored unclaimedRewards
        uint256 pending = nd.unclaimedRewards;

        // 4. If node is active, add newly accrued portion
        if (nd.isActive) {
            uint256 indexDelta = hypotheticalGlobalIndex - nd.nodeRewardIndex;
            uint256 newlyAccrued = indexDelta * nd.computeUnits;
            pending += newlyAccrued;
        }

        return pending;
    }

    function endRewards() external onlyRole(COMPUTE_POOL_ROLE) {
        _updateGlobalIndex();
        endTime = block.timestamp;
    }
}
