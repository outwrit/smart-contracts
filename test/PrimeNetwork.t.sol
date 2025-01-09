// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PrimeNetwork} from "../src/PrimeNetwork.sol";

contract PrimeNetworkTest is Test {
    PrimeNetwork primeNetwork;

    function setUp() public {
        //primeNetwork = new PrimeNetwork();
    }

    function test_n() public pure {
        console.log("PrimeNetworkTest test");
    }
}
