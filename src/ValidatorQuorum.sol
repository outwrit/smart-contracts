// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

// example contract that implements a validator quorum

import "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

event CallAdded(address target, bytes args, uint256 callIndex);

event CallExecuted(address target, bytes args, uint256 callIndex);

event CallReverted(address target, bytes args, uint256 callIndex);

event ValidatorAdded(address validator);

event ValidatorRemoved(address validator);

event QuorumSizeChanged(uint256 quorumSize);

event VoteAdded(address validator, uint256 callIndex);

contract ValidatorQuorum is AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct Calls {
        address target;
        bytes args;
        bool done;
    }

    bytes32 public constant FEDERATOR_ROLE = keccak256("FEDERATOR_ROLE");
    uint256 public quorumSize;
    EnumerableSet.AddressSet validators;

    Calls[] public calls;
    EnumerableSet.AddressSet[] callVotes;

    modifier onlyValidator() {
        require(validators.contains(msg.sender), "ValidatorQuorum: caller is not a validator");
        _;
    }

    constructor(address[] memory _validators, uint256 _quorumSize) {
        for (uint256 i = 0; i < _validators.length; i++) {
            validators.add(_validators[i]);
        }
        quorumSize = _quorumSize;
        _grantRole(FEDERATOR_ROLE, msg.sender);
    }

    function newCall(address _target, bytes calldata _args) external onlyValidator {
        calls.push(Calls({target: _target, args: _args, done: false}));
        EnumerableSet.AddressSet storage votes = callVotes[calls.length - 1];
        votes.add(msg.sender);
        emit CallAdded(_target, _args, calls.length - 1);
    }

    function addVote(uint256 _callIndex) external onlyValidator {
        require(_callIndex < calls.length, "ValidatorQuorum: call does not exist");
        EnumerableSet.AddressSet storage votes = callVotes[_callIndex];
        require(!votes.contains(msg.sender), "ValidatorQuorum: validator has already voted");
        votes.add(msg.sender);
        emit VoteAdded(msg.sender, _callIndex);
    }

    function callExecutor(uint256 _callIndex) external onlyValidator {
        require(!calls[_callIndex].done, "ValidatorQuorum: call already executed");
        require(callVotes[_callIndex].length() >= quorumSize, "ValidatorQuorum: quorum not reached");
        calls[_callIndex].done = true;
        uint256 gas = gasleft();
        gas = gas - 10000;
        (bool success,) = calls[_callIndex].target.call{gas: gas}(calls[_callIndex].args);
        if (success) {
            emit CallExecuted(calls[_callIndex].target, calls[_callIndex].args, _callIndex);
        } else {
            emit CallReverted(calls[_callIndex].target, calls[_callIndex].args, _callIndex);
        }
    }

    function addValidator(address validator) external onlyRole(FEDERATOR_ROLE) {
        validators.add(validator);
        emit ValidatorAdded(validator);
    }

    function removeValidator(address validator) external onlyRole(FEDERATOR_ROLE) {
        validators.remove(validator);
        emit ValidatorRemoved(validator);
    }

    function setQuorumSize(uint256 _quorumSize) external onlyRole(FEDERATOR_ROLE) {
        quorumSize = _quorumSize;
        emit QuorumSizeChanged(_quorumSize);
    }
}
