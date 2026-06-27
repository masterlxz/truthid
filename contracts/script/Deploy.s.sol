// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {DeviceRegistry} from "../src/DeviceRegistry.sol";
import {RecoveryManager} from "../src/RecoveryManager.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        IdentityRegistry identityRegistry = new IdentityRegistry();

        DeviceRegistry deviceRegistry = new DeviceRegistry(address(identityRegistry));

        RecoveryManager recoveryManager = new RecoveryManager(address(identityRegistry));

        identityRegistry.setRecoveryManager(address(recoveryManager));

        vm.stopBroadcast();

        console.log("IdentityRegistry :", address(identityRegistry));
        console.log("DeviceRegistry   :", address(deviceRegistry));
        console.log("RecoveryManager  :", address(recoveryManager));
    }
}
