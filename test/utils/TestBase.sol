// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function warp(uint256) external;
    function expectRevert(bytes4) external;
    function expectRevert() external;
    function assume(bool) external;
}

abstract contract TestBase {
    Vm internal constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "not equal");
    }
    function assertEq(address a, address b) internal pure {
        require(a == b, "not equal");
    }
    function assertTrue(bool value) internal pure {
        require(value, "not true");
    }
    function bound(
        uint256 value,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (value % (max - min + 1));
    }
}
