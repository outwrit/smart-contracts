#!/bin/bash

rm -rf ./release
mkdir -p ./release

anvil --state ./release/anvil_base.state  > /dev/null 2>&1 &
pid=$!

echo "Anvil started, waiting for init..."

sleep 2

echo "Deploying..."

./deploy.sh

sleep 1

echo "Finished..."

kill $pid
