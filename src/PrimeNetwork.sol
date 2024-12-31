// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IComputeRegistry.sol";
import "./IStakeManager.sol";
import "./IDomainRegistry.sol";
import "./IWorkValidation.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract PrimeNetwork is AccessControl {
    bytes32 public constant FEDERATOR_ROLE = keccak256("FEDERATOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    IComputeRegistry public computeRegistry;
    IDomainRegistry public domainRegistry;
    IStakeManager public stakeManager;
    IERC20 public PrimeToken;

    uint256 stakeMinimum;

    constructor(address _federator, address _validator, IERC20 _PrimeToken) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEDERATOR_ROLE, _federator);
        _grantRole(VALIDATOR_ROLE, _validator);
        stakeMinimum = 100 ether;
        PrimeToken = _PrimeToken;
    }

    function setFederator(address _federator) external onlyRole(FEDERATOR_ROLE) {
        grantRole(FEDERATOR_ROLE, _federator);
        revokeRole(FEDERATOR_ROLE, msg.sender);
    }

    function setValidator(address _validator) external onlyRole(FEDERATOR_ROLE) {
        grantRole(VALIDATOR_ROLE, _validator);
        revokeRole(VALIDATOR_ROLE, msg.sender);
    }

    function setStakeMinimum(uint256 _stakeMinimum) external onlyRole(FEDERATOR_ROLE) {
        stakeMinimum = _stakeMinimum;
    }

    function whitelistProvider(address provider) external onlyRole(FEDERATOR_ROLE) {
        computeRegistry.setWhitelistStatus(provider, true);
        emit ProviderWhitelisted(provider);
    }

    function blacklistProvider(address provider) external onlyRole(FEDERATOR_ROLE) {
        computeRegistry.setWhitelistStatus(provider, false);
        emit ProviderBlacklisted(provider);
    }

    function createDomain(string calldata domainName, IWorkValidation validationLogic, string calldata domainURI)
        external
        onlyRole(FEDERATOR_ROLE)
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

    function deregisterProvider(address provider) external {
        require(hasRole(FEDERATOR_ROLE, msg.sender) || msg.sender == provider, "Unauthorized");
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

    function removeComputeNode(address provider, address nodekey) external {
        require(hasRole(FEDERATOR_ROLE, msg.sender) || msg.sender == provider, "Unauthorized");
        computeRegistry.removeComputeNode(provider, nodekey);
        emit ComputeNodeRemoved(provider, nodekey);
    }
}
