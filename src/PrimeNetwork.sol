// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// MVP interface scaffolding for a decentralized AI training network.
// Initial API is designed for a permissioned network with admin, validators, and trainers.

// Roles:
// - DEFAULT_ADMIN_ROLE: Contract owner/admin.
// - VALIDATOR_ROLE: Initially a whitelisted address with authority to slash stakes.
// - TASKER_ROLE: Model trainers creating and managing compute tasks.

// Key Concepts:
// - Miners (nodes) join network with hardware specs and optional stake.
// - Model trainers create compute tasks (subnets) with hardware requirements.
// - Miners join/leave compute tasks. Only active participants earn rewards.
// - Validators can slash stakes for fraudulent behavior.
// - Compute task creators can remove underperforming or byzantine nodes.
// - Rewards schedules are to be implemented later, possibly stake/hardware dependent.

abstract contract PrimeNetwork is AccessControl, ReentrancyGuard {
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant TASKER_ROLE   = keccak256("TASKER_ROLE");

    struct HardwareSpecs {
        uint256 gpuModel; // hardware identifier
        uint256 gpuCount;
        uint256 gpuMemory; // in GB
        uint256 totalFlops; // in TFLOPS
        uint256 cpuModel; // hardware identifier
        uint256 cpuCores;
        uint256 ram;       // in GB
        uint256 disk;      // in GB
        uint256 bandwidth; // in Gbps
    }

    struct Node {
        address miner;
        bool activeOnNetwork;
        bool activeOnComputeTask;
        uint256 stake; // optional staking
        HardwareSpecs hardware;
    }

    struct ComputeTask {
        address tasker;
        uint256 minGpuCount;
        uint256 minGpuMemory;
        uint256 minCpuCores;
        uint256 minRam;
        uint256 minStorage;
        uint256 rewardRatePerFLOPS; // is flops the right metric?
        bool active;
        // Additional parameters such as reward distribution rates, etc.
    }

    // Mappings
    mapping(address => Node) public nodes;
    mapping(uint256 => ComputeTask) public computeTasks;
    mapping(uint256 => address[]) public computeTaskParticipants; // taskId => node addresses
    mapping(address => uint256) public rewardsBalance; // node => accrued rewards

    // Counters
    uint256 public computeTaskCount;

    // Events
    event NodeJoinedNetwork(address indexed miner, HardwareSpecs specs, uint256 stake);
    event NodeLeftNetwork(address indexed miner);
    event ComputeTaskCreated(uint256 indexed taskId, address indexed tasker);
    event ComputeTaskClosed(uint256 indexed taskId);
    event NodeAppliedForComputeTask(uint256 indexed taskId, address indexed miner);
    event NodeJoinedComputeTask(uint256 indexed taskId, address indexed miner);
    event NodeRemovedFromComputeTask(uint256 indexed taskId, address indexed miner, string reason);
    event StakeSlashed(address indexed miner, uint256 amount);
    event RewardsDistributed(uint256 indexed taskId, address indexed miner, uint256 amount);

    // Modifiers
    modifier onlyValidator() {
        require(hasRole(VALIDATOR_ROLE, msg.sender), "Not validator");
        _;
    }

    modifier onlyTasker() {
        require(hasRole(TASKER_ROLE, msg.sender), "Not tasker");
        _;
    }

    modifier onlyExistingNode(address _miner) {
        require(nodes[_miner].miner == _miner, "Node does not exist");
        _;
    }

    modifier computeTaskActive(uint256 _taskId) {
        require(computeTasks[_taskId].active, "Compute task inactive");
        _;
    }

    modifier meetsHardwareRequirements(uint256 _taskId, HardwareSpecs memory _specs) {
        ComputeTask memory ct = computeTasks[_taskId];
        require(_specs.gpuCount   >= ct.minGpuCount, "Insufficient GPU count");
        require(_specs.gpuMemory  >= ct.minGpuMemory, "Insufficient GPU mem");
        require(_specs.cpuCores   >= ct.minCpuCores, "Insufficient CPU cores");
        require(_specs.ram        >= ct.minRam, "Insufficient RAM");
        require(_specs.disk       >= ct.minStorage, "Insufficient storage");
        _;
    }

    // Node registration and network participation
    function joinNetwork(HardwareSpecs calldata _specs, uint256 _stake) external virtual;
    function updateNodeHardware(HardwareSpecs calldata _specs) external virtual onlyExistingNode(msg.sender) {}
    function leaveNetwork() external virtual onlyExistingNode(msg.sender) {}

    // Staking
    function depositStake(uint256 _amount) external virtual onlyExistingNode(msg.sender) {}
    function withdrawStake(uint256 _amount) external virtual onlyExistingNode(msg.sender) {}

    // Validation and slashing
    function slashStake(address _miner, uint256 _amount, bytes[] calldata _proof) external virtual onlyValidator onlyExistingNode(_miner) {}

    // Compute tasks
    function createComputeTask(
        uint256 _minGpuCount,
        uint256 _minGpuMemory,
        uint256 _minCpuCores,
        uint256 _minRam,
        uint256 _minStorage
    ) external virtual onlyTasker returns (uint256) {}

    function closeComputeTask(uint256 _taskId) external virtual onlyTasker {}

    function applyForComputeTask(uint256 _taskId)
        external
        virtual
        onlyExistingNode(msg.sender)
        computeTaskActive(_taskId)
        meetsHardwareRequirements(_taskId, nodes[msg.sender].hardware) {}

    function approveNodeForComputeTask(uint256 _taskId, address _miner)
        external
        virtual
        onlyTasker {}

    function removeNodeFromComputeTask(uint256 _taskId, address _miner, string calldata _reason) 
        external
        virtual
        onlyTasker {}

    // Rewards
    function distributeRewards(uint256 _taskId, address _miner, uint256 _amount) 
        external 
        virtual 
        onlyTasker
        computeTaskActive(_taskId) {}

    // View and utility functions for future logic
    function getActiveNodes() external view virtual returns (address[] memory);
    function getParticipants(uint256 _taskId) external view virtual returns (address[] memory);
    function getNodeInfo(address _miner) external view virtual returns (Node memory);
    function getComputeTaskInfo(uint256 _taskId) external view virtual returns (ComputeTask memory);
}
