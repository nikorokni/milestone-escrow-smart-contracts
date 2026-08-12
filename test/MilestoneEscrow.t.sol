// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./utils/TestBase.sol";
import {MilestoneEscrow} from "../src/MilestoneEscrow.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {EscrowFactory} from "../src/EscrowFactory.sol";

contract MilestoneEscrowTest is TestBase {
    address internal client = address(0xC11E17);
    address internal contractor = address(0xC017);
    address internal arbitrator = address(0xA8B1);
    address internal feeRecipient = address(0xFEE);
    MockERC20 internal token;
    MilestoneEscrow internal escrow;

    function setUp() public {
        token = new MockERC20();
        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 1_000 ether;
        amounts[1] = 2_000 ether;
        amounts[2] = 3_000 ether;
        uint64[] memory dates = new uint64[](3);
        dates[0] = uint64(block.timestamp + 7 days);
        dates[1] = uint64(block.timestamp + 14 days);
        dates[2] = uint64(block.timestamp + 21 days);
        escrow = new MilestoneEscrow(
            client,
            contractor,
            arbitrator,
            address(token),
            feeRecipient,
            200,
            3 days,
            7 days,
            amounts,
            dates
        );
        token.mint(client, 6_000 ether);
        vm.prank(client);
        token.approve(address(escrow), type(uint256).max);
    }

    function _fundAndStart() internal {
        vm.prank(client);
        escrow.fund();
        vm.prank(contractor);
        escrow.startProject();
    }

    function testFundAndStartProject() public {
        _fundAndStart();
        assertEq(token.balanceOf(address(escrow)), 6_000 ether);
        assertEq(
            uint256(escrow.projectState()),
            uint256(MilestoneEscrow.ProjectState.Active)
        );
    }

    function testApprovePaysContractorAndFee() public {
        _fundAndStart();
        vm.prank(contractor);
        escrow.submitMilestone(0, keccak256("ipfs://deliverable"));
        vm.prank(client);
        escrow.approveMilestone(0);
        assertEq(token.balanceOf(contractor), 980 ether);
        assertEq(token.balanceOf(feeRecipient), 20 ether);
        assertEq(escrow.currentMilestone(), 1);
    }

    function testContractorCanClaimAfterReviewTimeout() public {
        _fundAndStart();
        vm.prank(contractor);
        escrow.submitMilestone(0, keccak256("evidence"));
        vm.warp(block.timestamp + 3 days);
        vm.prank(contractor);
        escrow.claimAfterTimeout(0);
        assertEq(token.balanceOf(contractor), 980 ether);
    }

    function testCannotClaimBeforeTimeout() public {
        _fundAndStart();
        vm.prank(contractor);
        escrow.submitMilestone(0, keccak256("evidence"));
        vm.expectRevert(MilestoneEscrow.ReviewPeriodActive.selector);
        vm.prank(contractor);
        escrow.claimAfterTimeout(0);
    }

    function testClientCannotRejectAfterReviewDeadline() public {
        _fundAndStart();
        vm.prank(contractor);
        escrow.submitMilestone(0, keccak256("evidence"));
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert(MilestoneEscrow.ReviewPeriodExpired.selector);
        vm.prank(client);
        escrow.rejectMilestone(0, keccak256("late rejection"));
    }

    function testArbitratorSplitsDisputedMilestone() public {
        _fundAndStart();
        vm.prank(contractor);
        escrow.submitMilestone(0, keccak256("evidence"));
        vm.prank(client);
        escrow.rejectMilestone(0, keccak256("missing tests"));
        vm.prank(contractor);
        escrow.openDispute(0, keccak256("tests attached"));
        vm.prank(arbitrator);
        escrow.resolveDispute(0, 6_000);
        assertEq(token.balanceOf(contractor), 588 ether);
        assertEq(token.balanceOf(feeRecipient), 12 ether);
        assertEq(token.balanceOf(client), 400 ether);
    }

    function testSequentialMilestonesEnforced() public {
        _fundAndStart();
        vm.expectRevert(MilestoneEscrow.InvalidMilestone.selector);
        vm.prank(contractor);
        escrow.submitMilestone(1, keccak256("skip"));
    }

    function testPauseBlocksFundMovement() public {
        _fundAndStart();
        vm.prank(contractor);
        escrow.submitMilestone(0, keccak256("evidence"));
        vm.prank(arbitrator);
        escrow.setPaused(true);
        vm.expectRevert(MilestoneEscrow.ContractPaused.selector);
        vm.prank(client);
        escrow.approveMilestone(0);
    }

    function testCancelBeforeStartRefundsClient() public {
        vm.prank(client);
        escrow.fund();
        vm.prank(client);
        escrow.cancelBeforeStart();
        assertEq(token.balanceOf(client), 6_000 ether);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function testOnlyClientCanFund() public {
        vm.expectRevert(MilestoneEscrow.Unauthorized.selector);
        vm.prank(contractor);
        escrow.fund();
    }

    function testFactoryRegistersAllParticipants() public {
        EscrowFactory factory = new EscrowFactory();
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 100 ether;
        uint64[] memory dates = new uint64[](1);
        dates[0] = uint64(block.timestamp + 1 days);
        vm.prank(client);
        address deployed = factory.createEscrow(
            contractor,
            arbitrator,
            address(token),
            feeRecipient,
            100,
            1 days,
            2 days,
            amounts,
            dates
        );
        assertEq(factory.escrowCount(), 1);
        assertEq(factory.escrowAt(0), deployed);
        assertEq(factory.escrowsFor(contractor)[0], deployed);
    }
}
