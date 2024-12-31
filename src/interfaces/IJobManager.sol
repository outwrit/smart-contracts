// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IComputeRegistry.sol";
import "./IRewardsDistributor.sol";

event JobCreated(uint256 indexed jobId, uint256 indexed domainId, address indexed creator);

event JobFunded(uint256 indexed jobId, uint256 amount);

event JobEnded(uint256 indexed jobId);

event JobURIUpdated(uint256 indexed jobId, string uri);

interface IJobManager {
    enum JobStatus {
        PENDING,
        ACTIVE,
        CANCELED,
        COMPLETED
    }

    struct JobInfo {
        uint256 jobId;
        uint256 domainId;
        address creator;
        uint256 creationTime;
        string jobDataURI;
        address jobValidationLogic;
        uint256 totalFunds;
        uint256 rewardRate;
        JobStatus status;
    }
    // there should probably be a rewards delegate stub deployed
    // for each job for efficiency's sake rather than a whole new
    // rewards distributor contract each time

    function createJob(uint256 domainId, address creator, uint256 rewardRate, string calldata jobDataURI) external;
    function fundJob(uint256 jobId, uint256 amount) external;
    function startJob(uint256 jobId) external;
    function endJob(uint256 jobId) external;
    function joinJob(uint256 jobId, address provider, address[] memory nodekey) external;
    function leaveJob(uint256 jobId, address provider) external;
    function updateJobURI(uint256 jobId, string calldata jobDataURI) external;
    function blacklistProvider(uint256 jobId, address provider) external;
    function blacklistNode(uint256 jobId, address nodekey) external;
    function getJob(uint256 jobId) external view returns (JobInfo memory);
    function getJobProviders(uint256 jobId) external view returns (address[] memory);
    function getJobNodes(uint256 jobId) external view returns (address[] memory);
}
