// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PrimeNetwork} from "../src/PrimeNetwork.sol";
import {AIToken} from "../src/AIToken.sol";
import {ComputeRegistry} from "../src/ComputeRegistry.sol";
import {ComputePool} from "../src/ComputePool.sol";
import {StakeManager} from "../src/StakeManager.sol";
import {DomainRegistry} from "../src/DomainRegistry.sol";
import {IStakeManager} from "../src/interfaces/IStakeManager.sol";
import {IDomainRegistry} from "../src/interfaces/IDomainRegistry.sol";
import {IWorkValidation} from "../src/interfaces/IWorkValidation.sol";
import {RewardsDistributorFactory} from "../src/RewardsDistributorFactory.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract PrimeNetworkTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    address federator;
    address validator;
    address pool_creator;
    address provider_good1;
    address provider_good2;
    address provider_good3;
    address provider_bad1;
    address node_good1;
    uint256 node_good1_sk;
    address node_good2;
    uint256 node_good2_sk;
    address node_good3;
    uint256 node_good3_sk;
    address node_bad1;
    uint256 node_bad1_sk;
    address computeManager;
    uint256 computeManager_sk;
    PrimeNetwork primeNetwork;
    AIToken AI;
    ComputeRegistry computeRegistry;
    ComputePool computePool;
    StakeManager stakeManager;
    DomainRegistry domainRegistry;
    RewardsDistributorFactory rewardsDistributorFactory;

    struct NodeGroup {
        address provider;
        uint256 provder_key;
        address[] nodes;
        uint256[] node_keys;
    }

    uint256 unbondingPeriod = 60 * 60 * 24 * 7; // 1 week

    function setUp() public {
        federator = makeAddr("federator");
        validator = makeAddr("validator");
        startHoax(federator);
        AI = new AIToken("Prime Intellect", "AI");
        primeNetwork = new PrimeNetwork(federator, validator, AI);
        computeRegistry = new ComputeRegistry(address(primeNetwork));
        stakeManager = new StakeManager(address(primeNetwork), unbondingPeriod, AI);
        domainRegistry = new DomainRegistry(address(primeNetwork));
        rewardsDistributorFactory = new RewardsDistributorFactory();
        computePool =
            new ComputePool(address(primeNetwork), domainRegistry, computeRegistry, rewardsDistributorFactory, AI);
        rewardsDistributorFactory.setComputePool(computePool);

        primeNetwork.setModuleAddresses(
            address(computeRegistry), address(domainRegistry), address(stakeManager), address(computePool)
        );

        primeNetwork.setStakeMinimum(10);

        pool_creator = makeAddr("pool_creator");

        provider_good1 = makeAddr("provider_good1");
        provider_good2 = makeAddr("provider_good2");
        provider_good3 = makeAddr("provider_good3");
        provider_bad1 = makeAddr("provider_bad1");

        (node_good1, node_good1_sk) = makeAddrAndKey("node_good1");
        (node_good2, node_good2_sk) = makeAddrAndKey("node_good2");
        (node_good3, node_good3_sk) = makeAddrAndKey("node_good3");
        (node_bad1, node_bad1_sk) = makeAddrAndKey("node_bad1");
        (computeManager, computeManager_sk) = makeAddrAndKey("computeManager");

        AI.mint(provider_good1, 1000);
        AI.mint(provider_good2, 1000);
        AI.mint(provider_good3, 1000);
        AI.mint(provider_bad1, 1000);
    }

    function fundProvider(address provider) public {
        vm.startPrank(federator);
        AI.mint(provider, 1000);
    }

    function addProvider(address provider) public {
        vm.startPrank(provider);
        AI.approve(address(primeNetwork), 10);
        primeNetwork.registerProvider(10);
    }

    function removeProvider(address provider) public {
        vm.startPrank(provider);
        primeNetwork.deregisterProvider(provider);
    }

    function addNode(address provider, address node, uint256 node_sk) public {
        vm.startPrank(provider);
        bytes32 digest = keccak256(abi.encodePacked(provider, node)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(node_sk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        primeNetwork.addComputeNode(node, "ipfs://nodekey/", 10, signature);
    }

    function removeNode(address provider, address node) public {
        vm.startPrank(provider);
        primeNetwork.removeComputeNode(provider, node);
    }

    function whitelistProvider(address provider) public {
        vm.startPrank(validator);
        primeNetwork.whitelistProvider(provider);
    }

    function blacklistProvider(address provider) public {
        vm.startPrank(validator);
        primeNetwork.blacklistProvider(provider);
    }

    function validateNode(address provider, address node) public {
        vm.startPrank(validator);
        primeNetwork.validateNode(provider, node);
    }

    function invalidateNode(address provider, address node) public {
        vm.startPrank(validator);
        primeNetwork.invalidateNode(provider, node);
    }

    function withdrawStake(address provider) public {
        vm.startPrank(provider);
        stakeManager.withdraw();
    }

    function slashProvider(address provider, uint256 amount) public {
        vm.startPrank(validator);
        primeNetwork.slash(provider, amount, "test");
    }

    function newDomain(string memory name, string memory uri) public returns (uint256) {
        vm.startPrank(federator);
        return primeNetwork.createDomain(name, IWorkValidation(address(0)), uri);
    }

    function newPool(uint256 domainId, string memory name, string memory uri) public returns (uint256) {
        vm.startPrank(pool_creator);
        return computePool.createComputePool(domainId, computeManager, name, uri, 0);
    }

    function startPool(uint256 poolId) public {
        vm.startPrank(pool_creator);
        computePool.startComputePool(poolId);
    }

    function nodeJoin(uint256 domainId, uint256 poolId, address provider, address node) public {
        bytes32 digest = keccak256(abi.encodePacked(domainId, poolId, node)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(computeManager_sk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.startPrank(provider);
        address[] memory nodes = new address[](1);
        bytes[] memory signatures = new bytes[](1);
        nodes[0] = node;
        signatures[0] = signature;
        computePool.joinComputePool(poolId, provider, nodes, signatures);
    }

    function nodeJoinMultiple(uint256 domainId, uint256 poolId, address provider, address[] memory nodes) public {
        bytes[] memory signatures = new bytes[](nodes.length);
        for (uint256 i = 0; i < nodes.length; i++) {
            bytes32 digest = keccak256(abi.encodePacked(domainId, poolId, nodes[i])).toEthSignedMessageHash();
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(computeManager_sk, digest);
            bytes memory signature = abi.encodePacked(r, s, v);
            signatures[i] = signature;
        }
        vm.startPrank(provider);
        vm.startSnapshotGas("add nodes to pool using multi join");
        computePool.joinComputePool(poolId, provider, nodes, signatures);
        uint256 gasUsed = vm.stopSnapshotGas();
        console.log("add nodes to pool using multi join", gasUsed);
    }

    function nodeLeave(uint256 poolId, address provider, address node) public {
        vm.startPrank(provider);
        computePool.leaveComputePool(poolId, provider, node);
    }

    function nodeLeaveAll(uint256 poolId, address provider) public {
        vm.startPrank(provider);
        computePool.leaveComputePool(poolId, provider, address(0));
    }

    function blacklistProviderFromPool(uint256 poolId, address provider) public {
        vm.startPrank(pool_creator);
        computePool.blacklistProvider(poolId, provider);
    }

    function blacklistNodeFromPool(uint256 poolId, address provider, address node) public {
        vm.startPrank(pool_creator);
        computePool.blacklistNode(poolId, provider, node);
    }

    function test_federatorRole() public {
        vm.startPrank(address(0));
        vm.expectRevert();
        primeNetwork.setFederator(federator);
    }

    function test_validatorRole() public {
        vm.startPrank(address(0));
        vm.expectRevert();
        primeNetwork.setValidator(validator);
    }

    function test_providerRegistration() public {
        vm.startPrank(provider_good1);
        AI.approve(address(primeNetwork), 10);
        primeNetwork.registerProvider(10);
        (address providerAddress,,) = computeRegistry.providers(provider_good1);
        assertEq(providerAddress, provider_good1);
    }

    function test_providerDeregistrationAndUnstaking() public {
        vm.startPrank(provider_good1);
        assertEq(AI.balanceOf(provider_good1), 1000);
        AI.approve(address(primeNetwork), 10);
        primeNetwork.registerProvider(10);
        primeNetwork.deregisterProvider(provider_good1);
        (address providerAddress,,) = computeRegistry.providers(provider_good1);
        assertEq(providerAddress, address(0));
        // try to withdraw before unbonding period
        vm.expectRevert();
        stakeManager.withdraw();
        skip(block.timestamp + unbondingPeriod + 1);
        IStakeManager.Unbond[] memory bond = stakeManager.getPendingUnbonds(provider_good1);
        console.log("Unbond:", bond[0].amount, bond[0].timestamp);
        stakeManager.withdraw();
        assertEq(AI.balanceOf(provider_good1), 1000);
    }

    function test_domainCreation() public {
        vm.startPrank(federator);
        primeNetwork.createDomain("test", IWorkValidation(address(0)), "test");
        IDomainRegistry.Domain memory domain = domainRegistry.get(0);
        assertEq(domain.domainId, 0);
        assertEq(domain.name, "test");
    }

    function test_providerOps() public {
        addProvider(provider_good1);
        assertEq(computeRegistry.getProvider(provider_good1).providerAddress, provider_good1);
        addProvider(provider_good2);
        assertEq(computeRegistry.getProvider(provider_good2).providerAddress, provider_good2);
        addProvider(provider_good3);
        assertEq(computeRegistry.getProvider(provider_good3).providerAddress, provider_good3);
        addProvider(provider_bad1);
        assertEq(computeRegistry.getProvider(provider_bad1).providerAddress, provider_bad1);
        // whitelist good providers
        whitelistProvider(provider_good1);
        assertEq(computeRegistry.getProvider(provider_good1).isWhitelisted, true);
        whitelistProvider(provider_good2);
        assertEq(computeRegistry.getProvider(provider_good2).isWhitelisted, true);
        whitelistProvider(provider_good3);
        assertEq(computeRegistry.getProvider(provider_good3).isWhitelisted, true);
        assertEq(computeRegistry.getProvider(provider_bad1).isWhitelisted, false);

        // slash prior to unstaking
        slashProvider(provider_bad1, 5);

        removeProvider(provider_bad1);
        assertEq(computeRegistry.getProvider(provider_bad1).providerAddress, address(0));
        removeProvider(provider_good1);
        assertEq(computeRegistry.getProvider(provider_good1).providerAddress, address(0));
        removeProvider(provider_good2);
        assertEq(computeRegistry.getProvider(provider_good2).providerAddress, address(0));
        removeProvider(provider_good3);
        assertEq(computeRegistry.getProvider(provider_good3).providerAddress, address(0));

        IStakeManager.Unbond[] memory unbonds = stakeManager.getPendingUnbonds(provider_bad1);
        assertEq(unbonds[0].amount, 5);

        // slash post unstaking, but pre unbonding period expiry
        slashProvider(provider_bad1, 2);
        unbonds = stakeManager.getPendingUnbonds(provider_bad1);
        assertEq(unbonds[0].amount, 3);

        // skip to unbond time
        skip(unbondingPeriod + 10);
        // check stake withdrawal
        withdrawStake(provider_good1);
        assertEq(AI.balanceOf(provider_good1), 1000);
        withdrawStake(provider_good2);
        assertEq(AI.balanceOf(provider_good2), 1000);
        withdrawStake(provider_good3);
        assertEq(AI.balanceOf(provider_good3), 1000);
        withdrawStake(provider_bad1);
        assertEq(AI.balanceOf(provider_bad1), 993);
        assertEq(AI.balanceOf(validator), 7);
    }

    function test_nodeOps() public {
        addProvider(provider_good1);

        addNode(provider_good1, node_good1, node_good1_sk);
        addNode(provider_good1, node_good2, node_good2_sk);
        addNode(provider_good1, node_good3, node_good3_sk);
        addNode(provider_good1, node_bad1, node_bad1_sk);

        whitelistProvider(provider_good1);
        validateNode(provider_good1, node_good1);
        validateNode(provider_good1, node_good2);
        validateNode(provider_good1, node_good3);
        validateNode(provider_good1, node_bad1);

        assertEq(computeRegistry.getNode(provider_good1, node_good1).subkey, node_good1);
        assertEq(computeRegistry.getNode(provider_good1, node_good2).subkey, node_good2);
        assertEq(computeRegistry.getNode(provider_good1, node_good3).subkey, node_good3);
        assertEq(computeRegistry.getNode(provider_good1, node_bad1).subkey, node_bad1);

        invalidateNode(provider_good1, node_bad1);
        assertEq(computeRegistry.getNode(provider_good1, node_bad1).isValidated, false);

        uint256 domain = newDomain("Decentralized Training", "https://primeintellect.ai/training/params");
        uint256 pool = newPool(domain, "INTELLECT-1", "https://primeintellect.ai/pools/intellect-1");

        startPool(pool);

        nodeJoin(domain, pool, provider_good1, node_good1);
        address[] memory nodes = new address[](2);
        nodes[0] = node_good2;
        nodes[1] = node_good3;

        nodeJoinMultiple(domain, pool, provider_good1, nodes);

        vm.expectRevert();
        nodeJoin(domain, pool, provider_good1, node_bad1);

        // should revert since node is already in another pool
        vm.expectRevert();
        nodeJoin(domain, pool, provider_good1, node_good1);

        nodeLeave(pool, provider_good1, node_good1);

        // should revert because provider still has active nodes
        vm.expectRevert();
        removeProvider(provider_good1);

        nodeLeaveAll(pool, provider_good1);

        nodeJoin(domain, pool, provider_good1, node_good1);
        nodeJoin(domain, pool, provider_good1, node_good2);

        // check blacklist prevents nodes from rejoining
        blacklistNodeFromPool(pool, provider_good1, node_good1);
        vm.expectRevert();
        nodeJoin(domain, pool, provider_good1, node_good1);

        // check that provider level blacklist also works
        blacklistProviderFromPool(pool, provider_good1);
        vm.expectRevert();
        nodeJoin(domain, pool, provider_good1, node_good2);

        // should succeed now that all nodes are removed (forcibly or voluntarily)
        removeProvider(provider_good1);

        skip(stakeManager.getUnbondingPeriod() + 10);

        withdrawStake(provider_good1);
        assertEq(AI.balanceOf(provider_good1), 1000);
    }

    function test_noNodeOwnedByMultipleProviders() public {
        addProvider(provider_good1);
        addProvider(provider_good2);

        addNode(provider_good1, node_good1, node_good1_sk);
        // should revert as node is already owned by provider_good1
        vm.expectRevert();
        addNode(provider_good2, node_good1, node_good1_sk);
    }

    function test_registerWithPermit() public {
        address provider_permit;
        uint256 provider_permit_sk;
        (provider_permit, provider_permit_sk) = makeAddrAndKey("provider_permit");
        bytes32 DOMAIN_SEPARATOR;
        bytes32 PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        DOMAIN_SEPARATOR = AI.DOMAIN_SEPARATOR();

        vm.startPrank(federator);
        AI.mint(provider_permit, 100);
        vm.startPrank(provider_permit);
        address owner = provider_permit;
        address spender = address(primeNetwork);
        uint256 value = 10;
        uint256 deadline = block.timestamp + 1000;
        uint256 nonce = AI.nonces(provider_good1);
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(provider_permit_sk, digest);
        bytes memory signature = abi.encode(r, s, v);
        primeNetwork.registerProviderWithPermit(value, deadline, signature);
    }

    function test_blacklistGasCosts() public {
        string memory node_prefix = "node_gastest";
        string memory provider_prefix = "provider_gastest";

        uint256 num_providers = 10;
        uint256 num_nodes_per_provider = 20;
        uint256 domain = newDomain("Decentralized Training", "https://primeintellect.ai/training/params");
        uint256 pool = newPool(domain, "INTELLECT-1", "https://primeintellect.ai/pools/intellect-1");
        startPool(pool);

        NodeGroup[] memory ng = new NodeGroup[](num_providers);

        for (uint256 i = 0; i < num_providers; i++) {
            string memory provider = string(abi.encodePacked(provider_prefix, vm.toString(i)));
            (address pa, uint256 pk) = makeAddrAndKey(provider);
            fundProvider(pa);
            addProvider(pa);
            whitelistProvider(pa);
            ng[i].provider = pa;
            ng[i].provder_key = pk;
            ng[i].nodes = new address[](num_nodes_per_provider);
            ng[i].node_keys = new uint256[](num_nodes_per_provider);
            for (uint256 j = 0; j < num_nodes_per_provider; j++) {
                string memory node = string(abi.encodePacked(node_prefix, vm.toString(i), "_", vm.toString(j)));
                (address na, uint256 nk) = makeAddrAndKey(node);
                ng[i].nodes[j] = na;
                ng[i].node_keys[j] = nk;
                addNode(pa, na, nk);
                validateNode(pa, na);
                // nodeJoin(domain, pool, pa, na);
                // confirm node registration
                ComputeRegistry.ComputeNode memory nx = computeRegistry.getNode(pa, na);
                assertEq(nx.provider, pa);
                assertEq(nx.subkey, na);
            }
            nodeJoinMultiple(domain, pool, ng[i].provider, ng[i].nodes);
        }

        vm.startSnapshotGas("blacklist provider that has 20 active nodes in 200 node pool");
        blacklistProviderFromPool(pool, ng[3].provider);
        uint256 gasUsed = vm.stopSnapshotGas();
        console.log("Gas used to blacklist provider with 20 active nodes in 200 node pool:", gasUsed);
    }

    function test_computePoolFlow() public {
        // start federator role ----
        vm.startPrank(federator);
        // create domain
        primeNetwork.createDomain(
            "Decentralized Training", IWorkValidation(address(0)), "https://primeintellect.ai/training/params"
        );
        IDomainRegistry.Domain memory domain = domainRegistry.get(0);
        assertEq(domain.name, "Decentralized Training");
        uint256 domainId = domain.domainId;
        // mint some tokens so provider can stake
        AI.mint(address(provider_good1), 10);
        // end federator role ------
        // start provider role -----
        vm.startPrank(provider_good1);
        // register provider
        AI.approve(address(primeNetwork), 10);
        primeNetwork.registerProvider(10);
        // create a signature from node and add node
        bytes32 digest = keccak256(abi.encodePacked(provider_good1, node_good1)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(node_good1_sk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        primeNetwork.addComputeNode(node_good1, "ipfs://nodekey/", 10, signature);
        assertEq(computeRegistry.getNode(provider_good1, node_good1).subkey, node_good1);
        // end provider role -------
        // start validator role-----
        vm.startPrank(validator);
        // whitelist provider
        primeNetwork.whitelistProvider(provider_good1);
        // validate node
        primeNetwork.validateNode(provider_good1, node_good1);
        // end validator role ------
        // start pool creator role
        vm.startPrank(pool_creator);
        // create compute pool
        uint256 poolId = computePool.createComputePool(
            domainId, computeManager, "INTELLECT-2", "https://primeintellect.ai/pools/intellect-2", 0
        );
        computePool.startComputePool(poolId);
        // invite node to join pool
        bytes32 digest_invite = keccak256(abi.encodePacked(domainId, poolId, node_good1)).toEthSignedMessageHash();
        (uint8 v_invite, bytes32 r_invite, bytes32 s_invite) = vm.sign(computeManager_sk, digest_invite);
        bytes memory signature_invite = abi.encodePacked(r_invite, s_invite, v_invite);
        // end pool creator role
        // start provider role -----
        vm.startPrank(provider_good1);
        // join pool
        address[] memory nodes = new address[](1);
        nodes[0] = node_good1;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature_invite;
        computePool.joinComputePool(poolId, provider_good1, nodes, signatures);
    }
}
