// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VaultRegistry} from "../src/VaultRegistry.sol";

contract DeployVaultRegistry is Script {
    function run() external {
        address identityRegistry = vm.envAddress("IDENTITY_REGISTRY");
        address deviceRegistry = vm.envAddress("DEVICE_REGISTRY");

        vm.startBroadcast();

        VaultRegistry vaultRegistry = new VaultRegistry(identityRegistry, deviceRegistry);

        vm.stopBroadcast();

        console.log("VaultRegistry    :", address(vaultRegistry));
    }
}
