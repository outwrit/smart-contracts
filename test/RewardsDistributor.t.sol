// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/RewardsDistributor.sol";
import "../src/interfaces/IComputePool.sol";
import "../src/interfaces/IComputeRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockComputePool {
    address public rewardToken;

    constructor(address _rewardToken) {
        rewardToken = _rewardToken;
    }

    function getRewardToken() external view returns (address) {
        return rewardToken;
    }

    // Add any additional mock functions if needed for your tests
}

contract MockComputeRegistry {
    // node => provider
    mapping(address => address) public nodeProviderMap;

    function setNodeProvider(address node, address provider) external {
        nodeProviderMap[node] = provider;
    }

    function getNodeProvider(address node) external view returns (address) {
        return nodeProviderMap[node];
    }

    // Add any additional mock functions if needed for your tests
}

contract RewardsDistributorTest is Test {
    RewardsDistributor public distributor;
    MockComputePool public mockComputePool;
    MockComputeRegistry public mockComputeRegistry;
    MockERC20 public mockRewardToken;

    // Test addresses
    address public manager = address(0x1); // Has REWARDS_MANAGER_ROLE
    address public computePoolAddress = address(0x2); // Will hold COMPUTE_POOL_ROLE by default from constructor
    address public nodeProvider = address(0x3);
    address public node = address(0x4);

    function setUp() public {
        // 1. Deploy a mock token & mint an initial supply
        mockRewardToken = new MockERC20("MockToken", "MTK");
        mockRewardToken.mint(address(this), 1_000_000 ether); // Mint to ourselves for testing

        // 2. Deploy mocks for IComputePool & IComputeRegistry
        mockComputePool = new MockComputePool(address(mockRewardToken));
        mockComputeRegistry = new MockComputeRegistry();

        // 3. Deploy the RewardsDistributor
        distributor = new RewardsDistributor(
            IComputePool(address(mockComputePool)),
            IComputeRegistry(address(mockComputeRegistry)),
            1 // poolId
        );

        // 4. By default, constructor grants COMPUTE_POOL_ROLE to the computePool
        //    but we need to re-grant it to our mockComputePool if addresses differ
        //    Because we used mockComputePool as the constructor arg, it's already set.
        //    If you want a different address to be recognized as the compute pool, you can do:
        // distributor.grantRole(distributor.COMPUTE_POOL_ROLE(), computePoolAddress);

        // 5. Give manager the REWARDS_MANAGER_ROLE
        distributor.grantRole(distributor.REWARDS_MANAGER_ROLE(), manager);

        // 6. Fund the distributor with the reward token so it can pay out
        mockRewardToken.transfer(address(distributor), 500_000 ether);

        // 7. Set up the node-provider relationship in the registry
        mockComputeRegistry.setNodeProvider(node, nodeProvider);
    }

    /// ---------------------------------------
    /// Test: setRewardRate
    /// ---------------------------------------
    function testSetRewardRate() public {
        // Check initial reward rate is 0
        assertEq(distributor.rewardRatePerSecond(), 0);

        // Non-manager tries to set - should revert
        vm.prank(node);
        vm.expectRevert();
        distributor.setRewardRate(10);

        // Manager sets reward rate
        vm.prank(manager);
        distributor.setRewardRate(10);
        assertEq(distributor.rewardRatePerSecond(), 10);
    }

    /// ---------------------------------------
    /// Test: joinPool
    /// ---------------------------------------
    function testJoinPool() public {
        // Node not active initially
        (uint256 cu,,, bool isActive) = distributor.nodeInfo(node);
        assertEq(cu, 0);
        assertFalse(isActive);

        // Have the compute pool (with role) call joinPool
        vm.prank(address(mockComputePool));
        distributor.joinPool(node, 10);

        // Now node is active
        (cu,,, isActive) = distributor.nodeInfo(node);
        assertEq(cu, 10);
        assertTrue(isActive);

        // Trying to join again should revert since isActive is true
        vm.expectRevert("Node already active");
        vm.prank(address(mockComputePool));
        distributor.joinPool(node, 10);
    }

    /// ---------------------------------------
    /// Test: leavePool
    /// ---------------------------------------
    function testLeavePool() public {
        // Must join first
        vm.prank(address(mockComputePool));
        distributor.joinPool(node, 10);

        // Node is active
        (,,, bool isActive) = distributor.nodeInfo(node);
        assertTrue(isActive);

        // set reward rate
        vm.prank(manager);
        distributor.setRewardRate(1 ether);

        // Warp some time so there's a reward accrual
        vm.warp(block.timestamp + 100);

        // Now leave
        vm.prank(address(mockComputePool));
        distributor.leavePool(node);

        // Node is no longer active
        (,,, isActive) = distributor.nodeInfo(node);
        assertFalse(isActive);

        // The unclaimedRewards should have accrued
        (,, uint256 unclaimedRewards,) = distributor.nodeInfo(node);
        assertGt(unclaimedRewards, 0);
    }

    /// ---------------------------------------
    /// Test: claimRewards
    /// ---------------------------------------
    function testClaimRewards() public {
        // 1. Manager sets nonzero reward rate
        vm.prank(manager);
        distributor.setRewardRate(1 ether); // 1 token/sec for easy math

        // 2. Node joins
        vm.prank(address(mockComputePool));
        distributor.joinPool(node, 10);

        // 3. Move forward in time
        vm.warp(block.timestamp + 10);

        // 4. Claim from the wrong address => revert
        vm.expectRevert("Unauthorized");
        distributor.claimRewards(node);

        // 5. Node's provider claims on behalf of that node
        vm.prank(nodeProvider);
        distributor.claimRewards(node);

        // Check node unclaimedRewards is zero
        (,, uint256 unclaimed,) = distributor.nodeInfo(node);
        assertEq(unclaimed, 0);

        // Check the node's token balance is correct
        uint256 nodeBalance = mockRewardToken.balanceOf(node);
        // Rewards per second = 1 token; 10 seconds => 10 tokens
        // but node has 10 computeUnits => total 1 * 10 * 10?
        // Actually, the contract logic distributes 1 token/sec / totalActiveComputeUnits
        // => 1 / 10 = 0.1 tokens/sec per compute unit
        // => in 10 secs = 10 * 0.1 = 1 token per compute unit
        // => node has 10 compute units => 10 * 1 = 10 tokens total
        // Because we are using integer division in _updateGlobalIndex,
        // and if rewardRate / totalUnits is performed as integer division,
        // you might see truncated results. (But let's assume 1 for simplicity or
        // or your contract might do more precise math if using decimals.)
        //
        // For demonstration, let's just check we got > 0
        assertEq(nodeBalance, 10 ether);
    }

    /// ---------------------------------------
    /// Test: endRewards
    /// ---------------------------------------
    function testEndRewards() public {
        // Node joins first
        vm.prank(address(mockComputePool));
        distributor.joinPool(node, 10);

        // Set a nonzero reward rate
        vm.prank(manager);
        distributor.setRewardRate(1 ether);

        // Warp 5 seconds
        vm.warp(block.timestamp + 5);

        // End rewards
        vm.prank(address(mockComputePool));
        distributor.endRewards();

        // Warp more time (should not accrue new rewards after end)
        vm.warp(block.timestamp + 100);

        // Claim
        vm.prank(nodeProvider);
        distributor.claimRewards(node);

        // The node's balance should reflect only the reward for the first 5 seconds
        uint256 nodeBalance = mockRewardToken.balanceOf(node);
        // 1 token/sec total / 10 computeUnits => 0.1 token/sec per unit * 10 units = 1 token/sec total
        // => 5 seconds => 5 tokens
        assertEq(nodeBalance, 5 ether);
    }
}
