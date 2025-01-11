// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PrimeNetwork} from "../src/PrimeNetwork.sol";
import {PrimeIntellectToken} from "../src/PrimeIntellectToken.sol";
import {ComputeRegistry} from "../src/ComputeRegistry.sol";
import {ComputePool} from "../src/ComputePool.sol";
import {StakeManager} from "../src/StakeManager.sol";
import {DomainRegistry} from "../src/DomainRegistry.sol";
import {IStakeManager} from "../src/interfaces/IStakeManager.sol";
import {IDomainRegistry} from "../src/interfaces/IDomainRegistry.sol";
import {IWorkValidation} from "../src/interfaces/IWorkValidation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

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
    PrimeIntellectToken primeIntellectToken;
    ComputeRegistry computeRegistry;
    ComputePool computePool;
    StakeManager stakeManager;
    DomainRegistry domainRegistry;

    uint256 unbondingPeriod = 60 * 60 * 24 * 7; // 1 week

    function setUp() public {
        federator = makeAddr("federator");
        validator = makeAddr("validator");
        startHoax(federator);
        primeIntellectToken = new PrimeIntellectToken("Prime Intellect", "PRIME");
        primeNetwork = new PrimeNetwork(federator, validator, primeIntellectToken);
        computeRegistry = new ComputeRegistry(address(primeNetwork));
        stakeManager = new StakeManager(address(primeNetwork), unbondingPeriod, primeIntellectToken);
        domainRegistry = new DomainRegistry(address(primeNetwork));
        computePool = new ComputePool(address(primeNetwork), domainRegistry, computeRegistry, primeIntellectToken);

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

        primeIntellectToken.mint(provider_good1, 1000);
        primeIntellectToken.mint(provider_good2, 1000);
        primeIntellectToken.mint(provider_good3, 1000);
        primeIntellectToken.mint(provider_bad1, 1000);
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
        primeIntellectToken.approve(address(primeNetwork), 10);
        primeNetwork.registerProvider(10);
        (address providerAddress,,) = computeRegistry.providers(provider_good1);
        assertEq(providerAddress, provider_good1);
    }

    function test_providerDeregistrationAndUnstaking() public {
        vm.startPrank(provider_good1);
        assertEq(primeIntellectToken.balanceOf(provider_good1), 1000);
        primeIntellectToken.approve(address(primeNetwork), 10);
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
        assertEq(primeIntellectToken.balanceOf(provider_good1), 1000);
    }

    function test_domainCreation() public {
        vm.startPrank(federator);
        primeNetwork.createDomain("test", IWorkValidation(address(0)), "test");
        IDomainRegistry.Domain memory domain = domainRegistry.get(0);
        assertEq(domain.domainId, 0);
        assertEq(domain.name, "test");
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
        primeIntellectToken.mint(address(provider_good1), 10);
        // end federator role ------
        // start provider role -----
        vm.startPrank(provider_good1);
        // register provider
        primeIntellectToken.approve(address(primeNetwork), 10);
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
            0, computeManager, "INTELLECT-2", "https://primeintellect.ai/pools/intellect-2"
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
