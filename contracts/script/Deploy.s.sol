// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {DeviceRegistry} from "../src/DeviceRegistry.sol";
import {RecoveryManager} from "../src/RecoveryManager.sol";
import {TruthIDAccountFactory} from "../src/TruthIDAccountFactory.sol";

contract Deploy is Script {
    // EntryPoint v0.7 (ERC-4337) — endereco oficial, identico em todas as
    // EVM chains porque foi deployado via CREATE2 com salt zero.
    address internal constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        vm.startBroadcast();

        IdentityRegistry identityRegistry = new IdentityRegistry();

        DeviceRegistry deviceRegistry = new DeviceRegistry(address(identityRegistry));

        RecoveryManager recoveryManager = new RecoveryManager(address(identityRegistry));

        identityRegistry.setRecoveryManager(address(recoveryManager));

        TruthIDAccountFactory factory = new TruthIDAccountFactory(
            ENTRY_POINT_V07,
            address(deviceRegistry),
            address(identityRegistry),
            address(recoveryManager)
        );

        vm.stopBroadcast();

        console.log("IdentityRegistry        :", address(identityRegistry));
        console.log("DeviceRegistry          :", address(deviceRegistry));
        console.log("RecoveryManager         :", address(recoveryManager));
        console.log("TruthIDAccountFactory   :", address(factory));
    }
}
