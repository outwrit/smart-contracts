// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IComputeRegistry.sol";
import "./interfaces/IStakeManager.sol";
import "./interfaces/IDomainRegistry.sol";
import "./interfaces/IWorkValidation.sol";
import "./interfaces/IComputePool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract PrimeNetwork is AccessControl {
    using MessageHashUtils for bytes32;

    bytes32 public constant FEDERATOR_ROLE = keccak256("FEDERATOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    IComputeRegistry public computeRegistry;
    IDomainRegistry public domainRegistry;
    IStakeManager public stakeManager;
    IComputePool public computePool;

    IERC20 public PrimeToken;

    constructor(address _federator, address _validator, IERC20 _PrimeToken) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEDERATOR_ROLE, _federator);
        _grantRole(VALIDATOR_ROLE, _validator);
        PrimeToken = _PrimeToken;
    }

    function setModuleAddresses(
        address _computeRegistry,
        address _domainRegistry,
        address _stakeManager,
        address _computePool
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        computeRegistry = IComputeRegistry(_computeRegistry);
        domainRegistry = IDomainRegistry(_domainRegistry);
        stakeManager = IStakeManager(_stakeManager);
        computePool = IComputePool(_computePool);
        computeRegistry.setComputePool(address(computePool));
    }

    function setFederator(address _federator) external onlyRole(FEDERATOR_ROLE) {
        grantRole(FEDERATOR_ROLE, _federator);
        revokeRole(FEDERATOR_ROLE, msg.sender);
    }

    function setValidator(address _validator) external onlyRole(FEDERATOR_ROLE) {
        grantRole(VALIDATOR_ROLE, _validator);
        revokeRole(VALIDATOR_ROLE, msg.sender);
    }

    function whitelistProvider(address provider) external onlyRole(VALIDATOR_ROLE) {
        computeRegistry.setWhitelistStatus(provider, true);
        emit ProviderWhitelisted(provider);
    }

    function blacklistProvider(address provider) external onlyRole(VALIDATOR_ROLE) {
        computeRegistry.setWhitelistStatus(provider, false);
        emit ProviderBlacklisted(provider);
    }

    function validateNode(address provider, address nodekey) external onlyRole(VALIDATOR_ROLE) {
        computeRegistry.setNodeValidationStatus(provider, nodekey, true);
    }

    function invalidateNode(address provider, address nodekey) external onlyRole(VALIDATOR_ROLE) {
        computeRegistry.setNodeValidationStatus(provider, nodekey, false);
    }

    function setStakeMinimum(uint256 amount) external onlyRole(FEDERATOR_ROLE) {
        stakeManager.setStakeMinimum(amount);
        emit StakeMinimumUpdate(amount);
    }

    function createDomain(string calldata domainName, IWorkValidation validationLogic, string calldata domainURI)
        external
        onlyRole(FEDERATOR_ROLE)
    {
        uint256 domainId = domainRegistry.create(domainName, computePool, validationLogic, domainURI);
        emit DomainCreated(domainName, domainId);
    }

    function registerProvider(uint256 stake) external {
        uint256 stakeMinimum = stakeManager.getStakeMinimum();
        require(stake >= stakeMinimum, "Stake amount is below minimum");
        address provider = msg.sender;
        bool success = computeRegistry.register(provider);
        require(success, "Provider registration failed");
        PrimeToken.transferFrom(msg.sender, address(this), stake);
        PrimeToken.approve(address(stakeManager), stake);
        stakeManager.stake(provider, stake);
        emit ProviderRegistered(provider, stake);
    }

    function deregisterProvider(address provider) external {
        require(hasRole(VALIDATOR_ROLE, msg.sender) || msg.sender == provider, "Unauthorized");
        require(computeRegistry.getProvider(provider).activeNodes == 0, "Provider has active nodes");
        computeRegistry.deregister(provider);
        uint256 stake = stakeManager.getStake(provider);
        stakeManager.unstake(provider, stake);
        emit ProviderDeregistered(provider);
    }

    function addComputeNode(address nodekey, string calldata specsURI, uint256 computeUnits, bytes memory signature)
        external
    {
        address provider = msg.sender;
        // check provider exists
        require(computeRegistry.getProvider(provider).providerAddress == provider, "Provider not registered");
        require(_verifyNodekeySignature(provider, nodekey, signature), "Invalid signature");
        computeRegistry.addComputeNode(provider, nodekey, computeUnits, specsURI);
        emit ComputeNodeAdded(provider, nodekey, specsURI);
    }

    function removeComputeNode(address provider, address nodekey) external {
        require(hasRole(VALIDATOR_ROLE, msg.sender) || msg.sender == provider, "Unauthorized");
        computeRegistry.removeComputeNode(provider, nodekey);
        emit ComputeNodeRemoved(provider, nodekey);
    }

    function _verifyNodekeySignature(address provider, address nodekey, bytes memory signature)
        internal
        view
        returns (bool)
    {
        bytes32 messageHash = keccak256(abi.encodePacked(provider, nodekey)).toEthSignedMessageHash();
        return SignatureChecker.isValidSignatureNow(nodekey, messageHash, signature);
    }
}
