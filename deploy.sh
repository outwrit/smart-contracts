#!/bin/bash

export PRIVATE_KEY_FEDERATOR="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
export PRIVATE_KEY_VALIDATOR="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

forge script script/Deploy.s.sol:DeployScript --rpc-url localhost:8545 --broadcast --via-ir