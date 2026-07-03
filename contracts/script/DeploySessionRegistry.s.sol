// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SessionRegistry} from "../src/SessionRegistry.sol";

contract DeploySessionRegistry is Script {
    function run() external {
        address identityRegistry = vm.envAddress("IDENTITY_REGISTRY");
        address deviceRegistry = vm.envAddress("DEVICE_REGISTRY");

        vm.startBroadcast();

        SessionRegistry sessionRegistry = new SessionRegistry(identityRegistry, deviceRegistry);

        vm.stopBroadcast();

        console.log("SessionRegistry  :", address(sessionRegistry));
    }
}
