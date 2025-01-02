// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IJobManager.sol";
import "./interfaces/IDomainRegistry.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract JobManager is IJobManager, AccessControl {
    bytes32 public constant PRIME_ROLE = keccak256("PRIME_ROLE");

    mapping(uint256 => JobInfo) public jobs;
    uint256 public jobIdCounter;
    IComputeRegistry public computeRegistry;
    IDomainRegistry public domainRegistry;
    IRewardsDistributor public rewardsDistributor;
    IERC20 public PrimeToken;

    mapping(uint256 => mapping(address => bool)) public blacklistedProviders;
    mapping(uint256 => mapping(address => bool)) public blacklistdNodes;

    mapping(uint256 => address[]) public jobProviders;
    mapping(uint256 => address[]) public jobNodes;

    constructor(
        address _primeAdmin,
        IDomainRegistry _domainRegistry,
        IRewardsDistributor _rewardsDistributor,
        IComputeRegistry _computeRegistry,
        IERC20 _PrimeToken
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _primeAdmin);
        _grantRole(PRIME_ROLE, _primeAdmin);
        jobIdCounter = 0;
        PrimeToken = _PrimeToken;
        computeRegistry = _computeRegistry;
        domainRegistry = _domainRegistry;
        rewardsDistributor = _rewardsDistributor;
    }

    function _verifyJobInvite(
        uint256 domainId,
        uint256 jobId,
        address computeManagerKey,
        address nodekey,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encodePacked(domainId, jobId, nodekey));
        return SignatureChecker.isValidERC1271SignatureNow(computeManagerKey, messageHash, signature);
    }

    function createJob(
        uint256 domainId,
        address creator,
        address computeManagerKey,
        uint256 rewardRate,
        string calldata jobDataURI
    ) external {
        require(domainRegistry.get(domainId).domainId == domainId, "JobManager: domain does not exist");

        jobs[jobIdCounter] = JobInfo({
            jobId: jobIdCounter,
            domainId: domainId,
            creator: creator,
            computeManagerKey: computeManagerKey,
            creationTime: block.timestamp,
            jobDataURI: jobDataURI,
            jobValidationLogic: address(0),
            totalFunds: 0,
            rewardRate: rewardRate,
            status: JobStatus.PENDING
        });

        jobIdCounter++;
    }

    function startJob(uint256 jobId) external {
        require(jobs[jobId].jobId == jobId, "JobManager: job does not exist");
        require(jobs[jobId].status == JobStatus.PENDING, "JobManager: job is not pending");
        require(jobs[jobId].creator == msg.sender, "JobManager: only creator can start job");

        jobs[jobId].status = JobStatus.ACTIVE;
    }

    function endJob(uint256 jobId) external {
        require(jobs[jobId].jobId == jobId, "JobManager: job does not exist");
        require(jobs[jobId].status == JobStatus.ACTIVE, "JobManager: job is not active");
        require(jobs[jobId].creator == msg.sender, "JobManager: only creator can end job");

        jobs[jobId].status = JobStatus.COMPLETED;
    }

    function joinJob(uint256 jobId, address provider, address[] memory nodekey, bytes[] memory signatures) external {
        require(jobs[jobId].jobId == jobId, "JobManager: job does not exist");
        require(jobs[jobId].status == JobStatus.PENDING, "JobManager: job is not pending");
        require(!blacklistedProviders[jobId][provider], "JobManager: provider is blacklisted");
        require(msg.sender == provider, "JobManager: only provider can join job");

        for (uint256 i = 0; i < nodekey.length; i++) {
            require(!blacklistdNodes[jobId][nodekey[i]], "JobManager: node is blacklisted");
        }

        jobProviders[jobId].push(provider);
        for (uint256 i = 0; i < nodekey.length; i++) {
            require(
                computeRegistry.getNode(provider, nodekey[i]).provider == provider, "JobManager: node does not exist"
            );
            require(
                _verifyJobInvite(jobs[jobId].domainId, jobId, jobs[jobId].computeManagerKey, nodekey[i], signatures[i]),
                "JobManager: invalid invite"
            );
            jobNodes[jobId].push(nodekey[i]);
        }
    }

    function leaveJob(uint256 jobId, address provider) external {
        require(jobs[jobId].jobId == jobId, "JobManager: job does not exist");
        require(jobs[jobId].status != JobStatus.COMPLETED, "JobManager: job is completed");
        require(msg.sender == provider, "JobManager: only provider can leave job");

        for (uint256 i = 0; i < jobProviders[jobId].length; i++) {
            if (jobProviders[jobId][i] == provider) {
                jobProviders[jobId][i] = jobProviders[jobId][jobProviders[jobId].length - 1];
                jobProviders[jobId].pop();
                break;
            }
        }
    }

    function updateJobURI(uint256 jobId, string calldata jobDataURI) external {
        require(jobs[jobId].jobId == jobId, "JobManager: job does not exist");
        require(jobs[jobId].creator == msg.sender, "JobManager: only creator can update job URI");

        jobs[jobId].jobDataURI = jobDataURI;
    }

    function blacklistProvider(uint256 jobId, address provider) external {
        require(jobs[jobId].jobId == jobId, "JobManager: job does not exist");
        require(jobs[jobId].creator == msg.sender, "JobManager: only creator can blacklist provider");

        for (uint256 i = 0; i < jobProviders[jobId].length; i++) {
            if (jobProviders[jobId][i] == provider) {
                jobProviders[jobId][i] = jobProviders[jobId][jobProviders[jobId].length - 1];
                jobProviders[jobId].pop();
                break;
            }
        }

        // horrendous, this uses way too much gas, need to create a set mapping or something
        for (uint256 i = 0; i < jobNodes[jobId].length; i++) {
            if (computeRegistry.getNode(provider, jobNodes[jobId][i]).provider == provider) {
                jobNodes[jobId][i] = jobNodes[jobId][jobNodes[jobId].length - 1];
                jobNodes[jobId].pop();
                break;
            }
        }

        blacklistedProviders[jobId][provider] = true;
    }

    function blacklistNode(uint256 jobId, address nodekey) external {
        require(jobs[jobId].jobId == jobId, "JobManager: job does not exist");
        require(jobs[jobId].creator == msg.sender, "JobManager: only creator can blacklist node");

        for (uint256 i = 0; i < jobNodes[jobId].length; i++) {
            if (jobNodes[jobId][i] == nodekey) {
                jobNodes[jobId][i] = jobNodes[jobId][jobNodes[jobId].length - 1];
                jobNodes[jobId].pop();
                break;
            }
        }

        blacklistdNodes[jobId][nodekey] = true;
    }

    function getJob(uint256 jobId) external view returns (JobInfo memory) {
        return jobs[jobId];
    }

    function getJobProviders(uint256 jobId) external view returns (address[] memory) {
        return jobProviders[jobId];
    }

    function getJobNodes(uint256 jobId) external view returns (address[] memory) {
        return jobNodes[jobId];
    }
}
