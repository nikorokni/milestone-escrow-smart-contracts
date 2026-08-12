// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EscrowFactory} from "../src/EscrowFactory.sol";

interface VmBroadcast {
    function startBroadcast() external;
    function stopBroadcast() external;
}

contract Deploy {
    VmBroadcast private constant vm =
        VmBroadcast(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external returns (EscrowFactory factory) {
        vm.startBroadcast();
        factory = new EscrowFactory();
        vm.stopBroadcast();
    }
}
