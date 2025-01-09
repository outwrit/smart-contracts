// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {PrimeNetwork} from "../src/PrimeNetwork.sol";

contract PrimeNetworkScript is Script {
    PrimeNetwork primeNetwork;

    function setUp() public {
        //primeNetwork = new PrimeNetwork();
    }

    function run() public pure {
        console.log("PrimeNetworkScript test");
    }
}
