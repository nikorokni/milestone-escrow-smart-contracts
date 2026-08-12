// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "../utils/TestBase.sol";
import {MilestoneEscrow} from "../../src/MilestoneEscrow.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract EscrowHandler is TestBase {
    MilestoneEscrow public immutable escrow;
    address public immutable client;
    address public immutable contractor;

    constructor(MilestoneEscrow escrow_, address client_, address contractor_) {
        escrow = escrow_;
        client = client_;
        contractor = contractor_;
    }

    function submit() external {
        if (escrow.currentMilestone() >= escrow.milestoneCount()) return;
        MilestoneEscrow.Milestone memory m = escrow.getMilestone(
            escrow.currentMilestone()
        );
        if (m.state != MilestoneEscrow.MilestoneState.Pending) return;
        vm.prank(contractor);
        escrow.submitMilestone(
            escrow.currentMilestone(),
            keccak256("invariant evidence")
        );
    }

    function approve() external {
        if (escrow.currentMilestone() >= escrow.milestoneCount()) return;
        MilestoneEscrow.Milestone memory m = escrow.getMilestone(
            escrow.currentMilestone()
        );
        if (m.state != MilestoneEscrow.MilestoneState.Submitted) return;
        vm.prank(client);
        escrow.approveMilestone(escrow.currentMilestone());
    }
}

contract EscrowInvariantTest is TestBase {
    MilestoneEscrow internal escrow;
    MockERC20 internal token;
    EscrowHandler internal handler;
    address[] internal targets;

    function setUp() public {
        address client = address(0xC1);
        address contractor = address(0xC2);
        token = new MockERC20();
        uint128[] memory amounts = new uint128[](2);
        amounts[0] = 1_000 ether;
        amounts[1] = 2_000 ether;
        uint64[] memory dates = new uint64[](2);
        dates[0] = uint64(block.timestamp + 1 days);
        dates[1] = uint64(block.timestamp + 2 days);
        escrow = new MilestoneEscrow(
            client,
            contractor,
            address(0xA1),
            address(token),
            address(0xF1),
            200,
            1 days,
            2 days,
            amounts,
            dates
        );
        token.mint(client, 3_000 ether);
        vm.startPrank(client);
        token.approve(address(escrow), type(uint256).max);
        escrow.fund();
        vm.stopPrank();
        vm.prank(contractor);
        escrow.startProject();
        handler = new EscrowHandler(escrow, client, contractor);
        targets.push(address(handler));
    }

    function targetContracts() external view returns (address[] memory) {
        return targets;
    }

    function invariant_AccountingNeverExceedsBudget() public view {
        uint256 accounted = token.balanceOf(address(escrow)) +
            escrow.totalReleased() +
            escrow.totalRefunded();
        assertEq(accounted, escrow.totalBudget());
    }

    function invariant_CurrentMilestoneIsBounded() public view {
        assertTrue(escrow.currentMilestone() <= escrow.milestoneCount());
    }
}
