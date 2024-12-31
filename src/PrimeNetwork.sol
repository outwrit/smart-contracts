// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IComputeRegistry.sol";
import "./IStakeManager.sol";
import "./IDomainRegistry.sol";
import "./IWorkValidation.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PrimeNetwork {
    address public federator;
    address public validator;
    IComputeRegistry public computeRegistry;
    IDomainRegistry public domainRegistry;
    IStakeManager public stakeManager;
    IERC20 public PrimeToken;

    uint256 stakeMinimum;

    modifier onlyFederator() {
        require(msg.sender == federator, "Only federator can call this function");
        _;
    }

    modifier onlyFederatorOrProvider(address provider) {
        require(msg.sender == federator || msg.sender == provider, "Only federator or provider can call this function");
        _;
    }

    modifier onlyValidator() {
        require(msg.sender == validator, "Only validator can call this function");
        _;
    }

    constructor(address _federator) {
        federator = _federator;
        validator = address(0);
        stakeMinimum = 100 ether;
    }

    function setFederator(address _federator) external onlyFederator {
        federator = _federator;
    }

    function setValidator(address _validator) external onlyFederator {
        validator = _validator;
    }

    function setStakeMinimum(uint256 _stakeMinimum) external onlyFederator {
        stakeMinimum = _stakeMinimum;
    }

    function whitelistProvider(address provider) external onlyFederator {
        computeRegistry.setWhitelistStatus(provider, true);
        emit ProviderWhitelisted(provider);
    }

    function blacklistProvider(address provider) external onlyFederator {
        computeRegistry.setWhitelistStatus(provider, false);
        emit ProviderBlacklisted(provider);
    }

    function createDomain(string calldata domainName, IWorkValidation validationLogic, string calldata domainURI)
        external
        onlyFederator
    {
        uint256 domainId = domainRegistry.create(domainName, validationLogic, domainURI);
        require(domainId > 0, "Domain creation failed");
        emit DomainCreated(domainName, domainId);
    }

    function registerProvider(uint256 stake) external {
        require(stake >= stakeMinimum, "Stake amount is below minimum");
        address provider = msg.sender;
        bool success = computeRegistry.register(provider);
        require(success, "Provider registration failed");
        PrimeToken.transferFrom(msg.sender, address(this), stake);
        stakeManager.stake(provider, stake);
        emit ProviderRegistered(provider, stake);
    }

    function deregisterProvider(address provider) external onlyFederatorOrProvider(provider) {
        computeRegistry.deregister(provider);
        uint256 stake = stakeManager.getStake(provider);
        stakeManager.unstake(provider, stake);
        emit ProviderDeregistered(provider);
    }

    function addComputeNode(address nodekey, string calldata specsURI) external {
        address provider = msg.sender;
        uint256 nodeId = computeRegistry.addComputeNode(provider, nodekey, specsURI);
        require(nodeId > 0, "Compute node addition failed");
        emit ComputeNodeAdded(provider, nodekey, specsURI);
    }

    function removeComputeNode(address provider, address nodekey) external onlyFederatorOrProvider(provider) {
        computeRegistry.removeComputeNode(provider, nodekey);
        emit ComputeNodeRemoved(provider, nodekey);
    }
}
