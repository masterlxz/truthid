// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {DeviceRegistry} from "../src/DeviceRegistry.sol";
import {RecoveryManager} from "../src/RecoveryManager.sol";
import {TruthIDAccountFactory} from "../src/TruthIDAccountFactory.sol";
import {ENTRY_POINT_V07} from "../src/ERC4337Constants.sol";

contract Deploy is Script {
    function run() external {
        // Débito #52: par legado, só usado por `DeviceRegistry.migrateDevices`
        // para portar o histórico de devices de uma cascata anterior. Omitir
        // as duas env vars (deploy fresh, sem identidade real a migrar — ex:
        // ambiente local) desativa a migração via `address(0)`.
        address legacyDeviceRegistry = vm.envOr("LEGACY_DEVICE_REGISTRY", address(0));
        address legacyIdentityRegistry = vm.envOr("LEGACY_IDENTITY_REGISTRY", address(0));

        vm.startBroadcast();

        IdentityRegistry identityRegistry = new IdentityRegistry();

        DeviceRegistry deviceRegistry = new DeviceRegistry(
            address(identityRegistry), legacyDeviceRegistry, legacyIdentityRegistry
        );

        RecoveryManager recoveryManager =
            new RecoveryManager(address(identityRegistry), address(deviceRegistry));

        identityRegistry.setRecoveryManager(address(recoveryManager));

        // C3: registra o RecoveryManager no DeviceRegistry para que
        // executeRecovery possa revogar todos os devices da identidade.
        deviceRegistry.setRecoveryManager(address(recoveryManager));

        TruthIDAccountFactory factory = new TruthIDAccountFactory(
            ENTRY_POINT_V07,
            address(deviceRegistry),
            address(identityRegistry),
            address(recoveryManager)
        );

        // Débito #17: registra a factory no IdentityRegistry pra validar
        // consentimento de controllers do tipo smart account pré-deploy.
        identityRegistry.setFactory(address(factory));

        vm.stopBroadcast();

        console.log("IdentityRegistry        :", address(identityRegistry));
        console.log("DeviceRegistry          :", address(deviceRegistry));
        console.log("RecoveryManager         :", address(recoveryManager));
        console.log("TruthIDAccountFactory   :", address(factory));
    }
}
