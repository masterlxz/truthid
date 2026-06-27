// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SessionRegistry} from "../src/SessionRegistry.sol";

contract DeploySessionRegistry is Script {
    // Contratos já deployados na Base Sepolia (redeploy Sessão 24, pós-auditoria)
    address constant IDENTITY_REGISTRY = 0x35D21c65980cBd2dAE7576e1bf6b8e46C9e180BF;
    address constant DEVICE_REGISTRY = 0x225c67a98c9D675fE595ae05a2F9249C34d9C60a;

    function run() external {
        vm.startBroadcast();

        SessionRegistry sessionRegistry = new SessionRegistry(IDENTITY_REGISTRY, DEVICE_REGISTRY);

        vm.stopBroadcast();

        console.log("SessionRegistry  :", address(sessionRegistry));
    }
}
