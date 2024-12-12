// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// MVP interface scaffolding for a decentralized AI training network.
// No function implementations, just structures, events, and function signatures.

// Roles:
// - DEFAULT_ADMIN_ROLE: Contract owner/admin.
// - VALIDATOR_ROLE: Initially a whitelisted address with authority to slash stakes.
// - TRAINER_ROLE: Model trainers creating and managing training runs.
// - Later roles can be extended when decentralizing validation, reward distribution, etc.

// Key Concepts:
// - Miners (nodes) join network with hardware specs and optional stake.
// - Model trainers create "training runs" (subnets) with hardware requirements.
// - Miners join/leave training runs. Only active participants earn rewards.
// - Validators can slash stakes for fraudulent behavior.
// - Training run creators can remove underperforming or byzantine nodes.
// - Rewards schedules are to be implemented later, possibly stake/hardware dependent.

abstract contract DecentralizedAITNetwork is AccessControl, ReentrancyGuard {
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant TRAINER_ROLE   = keccak256("TRAINER_ROLE");

    struct HardwareSpecs {
        uint256 gpuCount;
        uint256 gpuMemory; // in GB
        uint256 cpuCores;
        uint256 ram;       // in GB
        uint256 disk;   // in GB
    }

    struct Node {
        address miner;
        bool activeOnNetwork;
        bool activeOnTrainingRun;
        uint256 stake;            // optional staking
        HardwareSpecs hardware;
    }

    struct TrainingRun {
        address trainer;
        uint256 minGpuCount;
        uint256 minGpuMemory;
        uint256 minCpuCores;
        uint256 minRam;
        uint256 minStorage;
        bool active;
        // Additional parameters such as reward distribution rates, etc.
    }

    // Mappings
    mapping(address => Node) public nodes;
    mapping(uint256 => TrainingRun) public trainingRuns;
    mapping(uint256 => address[]) public trainingRunParticipants; // runId => node addresses
    mapping(address => uint256) public rewardsBalance; // node => accrued rewards

    // Counters
    uint256 public trainingRunCount;

    // Events
    event NodeJoinedNetwork(address indexed miner, HardwareSpecs specs, uint256 stake);
    event NodeLeftNetwork(address indexed miner);
    event TrainingRunCreated(uint256 indexed runId, address indexed trainer);
    event TrainingRunClosed(uint256 indexed runId);
    event NodeJoinedTrainingRun(uint256 indexed runId, address indexed miner);
    event NodeRemovedFromTrainingRun(uint256 indexed runId, address indexed miner, string reason);
    event StakeSlashed(address indexed miner, uint256 amount);
    event RewardsDistributed(uint256 indexed runId, address indexed miner, uint256 amount);

    // Modifiers
    modifier onlyValidator() {
        require(hasRole(VALIDATOR_ROLE, msg.sender), "Not validator");
        _;
    }

    modifier onlyTrainer() {
        require(hasRole(TRAINER_ROLE, msg.sender), "Not trainer");
        _;
    }

    modifier onlyExistingNode(address _miner) {
        require(nodes[_miner].miner == _miner, "Node does not exist");
        _;
    }

    modifier trainingRunActive(uint256 _runId) {
        require(trainingRuns[_runId].active, "Run inactive");
        _;
    }

    modifier meetsHardwareRequirements(uint256 _runId, HardwareSpecs memory _specs) {
        TrainingRun memory tr = trainingRuns[_runId];
        require(_specs.gpuCount   >= tr.minGpuCount, "Insufficient GPU count");
        require(_specs.gpuMemory  >= tr.minGpuMemory, "Insufficient GPU mem");
        require(_specs.cpuCores   >= tr.minCpuCores, "Insufficient CPU cores");
        require(_specs.ram        >= tr.minRam, "Insufficient RAM");
        require(_specs.disk    >= tr.minStorage, "Insufficient storage");
        _;
    }

    // Node registration and network participation
    function joinNetwork(HardwareSpecs calldata _specs, uint256 _stake) external virtual;
    function updateNodeHardware(HardwareSpecs calldata _specs) external virtual onlyExistingNode(msg.sender);
    function leaveNetwork() external virtual onlyExistingNode(msg.sender);

    // Staking
    function depositStake(uint256 _amount) external virtual onlyExistingNode(msg.sender);
    function withdrawStake(uint256 _amount) external virtual onlyExistingNode(msg.sender);

    // Validation and slashing
    function slashStake(address _miner, uint256 _amount) external virtual onlyValidator onlyExistingNode(_miner);

    // Training runs
    function createTrainingRun(
        uint256 _minGpuCount,
        uint256 _minGpuMemory,
        uint256 _minCpuCores,
        uint256 _minRam,
        uint256 _minStorage
    ) external virtual onlyTrainer returns (uint256);

    function closeTrainingRun(uint256 _runId) external virtual onlyTrainer;

    function joinTrainingRun(uint256 _runId) 
        external 
        virtual 
        onlyExistingNode(msg.sender) 
        trainingRunActive(_runId) 
        meetsHardwareRequirements(_runId, nodes[msg.sender].hardware);

    function removeNodeFromTrainingRun(uint256 _runId, address _miner, string calldata _reason) 
        external 
        virtual 
        onlyTrainer;

    // Rewards
    function distributeRewards(uint256 _runId, address _miner, uint256 _amount) 
        external 
        virtual 
        onlyTrainer
        trainingRunActive(_runId);

    // View and utility functions for future logic
    function getActiveNodes() external view virtual returns (address[] memory);
    function getParticipants(uint256 _runId) external view virtual returns (address[] memory);
    function getNodeInfo(address _miner) external view virtual returns (Node memory);
    function getTrainingRunInfo(uint256 _runId) external view virtual returns (TrainingRun memory);
}
