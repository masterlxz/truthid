// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SessionRegistry} from "../src/SessionRegistry.sol";

contract DeploySessionRegistry is Script {
    // Contratos já deployados na Base Sepolia
    address constant IDENTITY_REGISTRY = 0xd4484aDD6DCd0919568B6365882cDB207fE27D9c;

    function run() external {
        vm.startBroadcast();

        SessionRegistry sessionRegistry = new SessionRegistry(IDENTITY_REGISTRY);

        vm.stopBroadcast();

        console.log("SessionRegistry  :", address(sessionRegistry));
    }
}
