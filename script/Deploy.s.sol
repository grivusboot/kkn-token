// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {KKNToken} from "../contracts/KKNToken.sol";

contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY"); // NU-l commita
        address charity  = vm.envAddress("CHARITY");
        address treasury = vm.envAddress("TREASURY");
        address rewards  = vm.envAddress("REWARDS");
        uint256 supply   = vm.envUint("INITIAL_SUPPLY"); // ex: 1_000_000_000 ether

        vm.startBroadcast(pk);
        new KKNToken(supply, charity, treasury, rewards);
        vm.stopBroadcast();
    }
}
