// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/AIToken.sol";
import "../src/ComputePool.sol";
import "../src/ComputeRegistry.sol";
import "../src/DomainRegistry.sol";
import "../src/PrimeNetwork.sol";
import "../src/StakeManager.sol";
import {RewardsDistributorWorkSubmissionFactory} from "../src/RewardsDistributorWorkSubmissionFactory.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_FEDERATOR");
        address deployer = vm.addr(deployerPrivateKey);
        uint256 validatorPrivateKey = vm.envUint("PRIVATE_KEY_VALIDATOR");
        address validator = vm.addr(validatorPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy AIToken first
        AIToken aiToken = new AIToken("AI Token", "AI");

        // Deploy PrimeNetwork
        PrimeNetwork primeNetwork = new PrimeNetwork(
            deployer, // federator
            validator, // validator
            aiToken
        );

        // Deploy core registries with deployer as admin
        ComputeRegistry computeRegistry = new ComputeRegistry(address(primeNetwork));
        DomainRegistry domainRegistry = new DomainRegistry(address(primeNetwork));

        // Deploy StakeManager with deployer as admin
        StakeManager stakeManager = new StakeManager(address(primeNetwork), 7 days, aiToken);

        // Deploy RewardsDistributorFixedFactory
        RewardsDistributorWorkSubmissionFactory rewardsDistributorFactory =
            new RewardsDistributorWorkSubmissionFactory();
        // Deploy ComputePool with deployer as admin
        ComputePool computePool =
            new ComputePool(address(primeNetwork), domainRegistry, computeRegistry, rewardsDistributorFactory, aiToken);
        // Set ComputePool in RewardsDistributorFixedFactory
        rewardsDistributorFactory.setComputePool(computePool);

        // Set up module addresses in PrimeNetwork
        primeNetwork.setModuleAddresses(
            address(computeRegistry), address(domainRegistry), address(stakeManager), address(computePool)
        );

        // Optional: Set up initial parameters
        primeNetwork.setStakeMinimum(100 * 1e18); // 100 tokens minimum stake

        // Optional: Mint some initial tokens to the deployer
        aiToken.mint(deployer, 1000000 * 1e18); // 1M tokens

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("Deployed contracts:");
        console.log("AIToken:", address(aiToken));
        console.log("ComputeRegistry:", address(computeRegistry));
        console.log("DomainRegistry:", address(domainRegistry));
        console.log("StakeManager:", address(stakeManager));
        console.log("PrimeNetwork:", address(primeNetwork));
        console.log("ComputePool:", address(computePool));

        vm.serializeAddress("contracts", "AIToken", address(aiToken));
        vm.serializeAddress("contracts", "ComputeRegistry", address(computeRegistry));
        vm.serializeAddress("contracts", "DomainRegistry", address(domainRegistry));
        vm.serializeAddress("contracts", "StakeManager", address(stakeManager));
        vm.serializeAddress("contracts", "PrimeNetwork", address(primeNetwork));
        string memory finalJson = vm.serializeAddress("contracts", "ComputePool", address(computePool));

        vm.writeJson(finalJson, "./release/deployments.json");
    }
}
