// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./utils/TestBase.sol";
import {MilestoneEscrow} from "../src/MilestoneEscrow.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract MilestoneEscrowFuzzTest is TestBase {
    function testFuzz_DisputeAccounting(
        uint128 rawAmount,
        uint16 rawAward,
        uint16 rawFee
    ) public {
        uint128 amount = uint128(bound(rawAmount, 1e6, 1_000_000 ether));
        uint16 award = uint16(bound(rawAward, 0, 10_000));
        uint16 fee = uint16(bound(rawFee, 0, 500));
        address client = address(0xC1);
        address contractor = address(0xC2);
        address arbitrator = address(0xA1);
        address feeRecipient = address(0xF1);
        MockERC20 token = new MockERC20();
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = amount;
        uint64[] memory dates = new uint64[](1);
        dates[0] = uint64(block.timestamp + 1 days);
        MilestoneEscrow escrow = new MilestoneEscrow(
            client,
            contractor,
            arbitrator,
            address(token),
            feeRecipient,
            fee,
            1 days,
            3 days,
            amounts,
            dates
        );
        token.mint(client, amount);
        vm.startPrank(client);
        token.approve(address(escrow), amount);
        escrow.fund();
        vm.stopPrank();
        vm.prank(contractor);
        escrow.startProject();
        vm.prank(contractor);
        escrow.submitMilestone(0, keccak256("evidence"));
        vm.prank(client);
        escrow.rejectMilestone(0, keccak256("reason"));
        vm.prank(contractor);
        escrow.openDispute(0, keccak256("claim"));
        vm.prank(arbitrator);
        escrow.resolveDispute(0, award);

        uint256 distributed = token.balanceOf(client) +
            token.balanceOf(contractor) +
            token.balanceOf(feeRecipient) +
            token.balanceOf(address(escrow));
        assertEq(distributed, amount);
        assertEq(token.balanceOf(address(escrow)), 0);
    }
}
