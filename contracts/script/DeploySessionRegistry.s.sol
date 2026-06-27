// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SessionRegistry} from "../src/SessionRegistry.sol";

contract DeploySessionRegistry is Script {
    // Contratos deployados na Base Mainnet (Sessão 25, Fase 7.1)
    address constant IDENTITY_REGISTRY = 0xbf097EC74d0Cc9b16D3d94EaCa62060d89A63b17;
    address constant DEVICE_REGISTRY = 0x4A7a307cb6872bde24BAf3E9de2BeC3Ddd03e144;

    function run() external {
        vm.startBroadcast();

        SessionRegistry sessionRegistry = new SessionRegistry(IDENTITY_REGISTRY, DEVICE_REGISTRY);

        vm.stopBroadcast();

        console.log("SessionRegistry  :", address(sessionRegistry));
    }
}
