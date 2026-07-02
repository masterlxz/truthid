// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TruthIDAccountFactory} from "../src/TruthIDAccountFactory.sol";

contract DeployFactory is Script {
    address internal constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        address deviceRegistry = vm.envAddress("DEVICE_REGISTRY");
        address identityRegistry = vm.envAddress("IDENTITY_REGISTRY");
        address recoveryManager = vm.envAddress("RECOVERY_MANAGER");

        vm.startBroadcast();

        TruthIDAccountFactory factory = new TruthIDAccountFactory(
            ENTRY_POINT_V07,
            deviceRegistry,
            identityRegistry,
            recoveryManager
        );

        vm.stopBroadcast();

        console.log("TruthIDAccountFactory   :", address(factory));
    }
}