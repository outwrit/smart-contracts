// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IWorkValidation.sol";
import "./IComputePool.sol";

event DomainCreated(string domainName, uint256 domainId);

event DomainUpdated(uint256 domainId, address validationLogic, string domainParametersURI);

interface IDomainRegistry {
    struct Domain {
        uint256 domainId;
        string name;
        IWorkValidation validationLogic;
        string domainParametersURI;
        IComputePool computePool;
    }

    function create(
        string calldata name,
        IComputePool computePool,
        IWorkValidation validationContract,
        string calldata domainParametersURI
    ) external returns (uint256);
    function updateValidationLogic(uint256 domainId, address validationContract) external;
    function updateParameters(uint256 domainId, string calldata domainParametersURI) external;
    function get(uint256 domainId) external view returns (Domain memory);
}
