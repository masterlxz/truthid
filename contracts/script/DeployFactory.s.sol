// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TruthIDAccountFactory} from "../src/TruthIDAccountFactory.sol";
import {ENTRY_POINT_V07} from "../src/ERC4337Constants.sol";

contract DeployFactory is Script {
    function run() external {
        address deviceRegistry = vm.envAddress("DEVICE_REGISTRY");
        address identityRegistry = vm.envAddress("IDENTITY_REGISTRY");
        address recoveryManager = vm.envAddress("RECOVERY_MANAGER");

        vm.startBroadcast();

        TruthIDAccountFactory factory = new TruthIDAccountFactory(
            ENTRY_POINT_V07, deviceRegistry, identityRegistry, recoveryManager
        );

        vm.stopBroadcast();

        console.log("TruthIDAccountFactory   :", address(factory));
    }
}
