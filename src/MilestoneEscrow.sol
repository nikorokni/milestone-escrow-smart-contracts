// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

/// @title MilestoneEscrow
/// @notice Non-custodial ERC-20 escrow with sequential milestones, review timeouts and bounded arbitration.
/// @dev Each milestone can release at most its configured amount. No privileged sweep function exists.
contract MilestoneEscrow {
    using SafeTransferLib for address;

    uint16 public constant BPS = 10_000;
    uint16 public constant MAX_FEE_BPS = 500;

    enum ProjectState {
        Created,
        Funded,
        Active,
        Completed,
        Cancelled
    }
    enum MilestoneState {
        Pending,
        Submitted,
        Rejected,
        Disputed,
        Settled
    }

    struct Milestone {
        uint128 amount;
        uint64 dueDate;
        uint64 submittedAt;
        MilestoneState state;
        bytes32 evidenceHash;
    }

    error Unauthorized();
    error InvalidAddress();
    error InvalidConfiguration();
    error InvalidState();
    error InvalidMilestone();
    error ReviewPeriodActive();
    error ReviewPeriodExpired();
    error DisputeWindowClosed();
    error ContractPaused();
    error Reentrancy();

    event ProjectFunded(uint256 amount);
    event ProjectStarted(uint256 timestamp);
    event MilestoneSubmitted(
        uint256 indexed milestoneId,
        bytes32 indexed evidenceHash,
        uint256 timestamp
    );
    event MilestoneRejected(
        uint256 indexed milestoneId,
        bytes32 indexed reasonHash
    );
    event DisputeOpened(uint256 indexed milestoneId, bytes32 indexed claimHash);
    event MilestoneSettled(
        uint256 indexed milestoneId,
        uint256 contractorAmount,
        uint256 clientAmount,
        uint256 feeAmount
    );
    event ProjectCompleted(uint256 timestamp);
    event ProjectCancelled(uint256 refundAmount);
    event PauseChanged(bool paused);

    address public immutable client;
    address public immutable contractor;
    address public immutable arbitrator;
    address public immutable paymentToken;
    address public immutable feeRecipient;
    uint64 public immutable reviewPeriod;
    uint64 public immutable disputeWindow;
    uint16 public immutable feeBps;
    uint256 public immutable totalBudget;

    ProjectState public projectState;
    uint256 public currentMilestone;
    uint256 public totalReleased;
    uint256 public totalRefunded;
    bool public paused;
    uint256 private locked = 1;
    Milestone[] private milestones;

    modifier onlyClient() {
        if (msg.sender != client) revert Unauthorized();
        _;
    }
    modifier onlyContractor() {
        if (msg.sender != contractor) revert Unauthorized();
        _;
    }
    modifier onlyArbitrator() {
        if (msg.sender != arbitrator) revert Unauthorized();
        _;
    }
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }
    modifier nonReentrant() {
        if (locked != 1) revert Reentrancy();
        locked = 2;
        _;
        locked = 1;
    }

    constructor(
        address client_,
        address contractor_,
        address arbitrator_,
        address paymentToken_,
        address feeRecipient_,
        uint16 feeBps_,
        uint64 reviewPeriod_,
        uint64 disputeWindow_,
        uint128[] memory amounts,
        uint64[] memory dueDates
    ) {
        if (
            client_ == address(0) ||
            contractor_ == address(0) ||
            arbitrator_ == address(0) ||
            paymentToken_ == address(0) ||
            feeRecipient_ == address(0)
        ) revert InvalidAddress();
        if (
            client_ == contractor_ ||
            contractor_ == arbitrator_ ||
            client_ == arbitrator_ ||
            feeBps_ > MAX_FEE_BPS ||
            reviewPeriod_ == 0 ||
            disputeWindow_ == 0 ||
            amounts.length == 0 ||
            amounts.length != dueDates.length
        ) revert InvalidConfiguration();

        client = client_;
        contractor = contractor_;
        arbitrator = arbitrator_;
        paymentToken = paymentToken_;
        feeRecipient = feeRecipient_;
        feeBps = feeBps_;
        reviewPeriod = reviewPeriod_;
        disputeWindow = disputeWindow_;

        uint256 budget;
        for (uint256 i; i < amounts.length; ++i) {
            if (amounts[i] == 0 || (i > 0 && dueDates[i] <= dueDates[i - 1])) {
                revert InvalidConfiguration();
            }
            milestones.push(
                Milestone(
                    amounts[i],
                    dueDates[i],
                    0,
                    MilestoneState.Pending,
                    bytes32(0)
                )
            );
            budget += amounts[i];
        }
        totalBudget = budget;
    }

    function fund() external onlyClient nonReentrant {
        if (projectState != ProjectState.Created) revert InvalidState();
        projectState = ProjectState.Funded;
        paymentToken.safeTransferFrom(client, address(this), totalBudget);
        emit ProjectFunded(totalBudget);
    }

    function startProject() external onlyContractor whenNotPaused {
        if (projectState != ProjectState.Funded) revert InvalidState();
        projectState = ProjectState.Active;
        emit ProjectStarted(block.timestamp);
    }

    function submitMilestone(
        uint256 milestoneId,
        bytes32 evidenceHash
    ) external onlyContractor whenNotPaused {
        Milestone storage milestone = _activeMilestone(milestoneId);
        if (
            milestone.state != MilestoneState.Pending ||
            evidenceHash == bytes32(0)
        ) revert InvalidState();
        milestone.state = MilestoneState.Submitted;
        milestone.submittedAt = uint64(block.timestamp);
        milestone.evidenceHash = evidenceHash;
        emit MilestoneSubmitted(milestoneId, evidenceHash, block.timestamp);
    }

    function approveMilestone(
        uint256 milestoneId
    ) external onlyClient whenNotPaused nonReentrant {
        Milestone storage milestone = _activeMilestone(milestoneId);
        if (milestone.state != MilestoneState.Submitted) revert InvalidState();
        _settle(milestoneId, BPS);
    }

    function rejectMilestone(
        uint256 milestoneId,
        bytes32 reasonHash
    ) external onlyClient whenNotPaused {
        Milestone storage milestone = _activeMilestone(milestoneId);
        if (
            milestone.state != MilestoneState.Submitted ||
            reasonHash == bytes32(0)
        ) revert InvalidState();
        if (block.timestamp >= uint256(milestone.submittedAt) + reviewPeriod)
            revert ReviewPeriodExpired();
        milestone.state = MilestoneState.Rejected;
        emit MilestoneRejected(milestoneId, reasonHash);
    }

    function claimAfterTimeout(
        uint256 milestoneId
    ) external onlyContractor whenNotPaused nonReentrant {
        Milestone storage milestone = _activeMilestone(milestoneId);
        if (milestone.state != MilestoneState.Submitted) revert InvalidState();
        if (block.timestamp < uint256(milestone.submittedAt) + reviewPeriod)
            revert ReviewPeriodActive();
        _settle(milestoneId, BPS);
    }

    function openDispute(
        uint256 milestoneId,
        bytes32 claimHash
    ) external onlyContractor whenNotPaused {
        Milestone storage milestone = _activeMilestone(milestoneId);
        if (
            milestone.state != MilestoneState.Rejected ||
            claimHash == bytes32(0)
        ) revert InvalidState();
        if (
            block.timestamp >
            uint256(milestone.submittedAt) + reviewPeriod + disputeWindow
        ) {
            revert DisputeWindowClosed();
        }
        milestone.state = MilestoneState.Disputed;
        emit DisputeOpened(milestoneId, claimHash);
    }

    /// @param contractorAwardBps Percentage of the milestone, before protocol fee, awarded to contractor.
    function resolveDispute(
        uint256 milestoneId,
        uint16 contractorAwardBps
    ) external onlyArbitrator whenNotPaused nonReentrant {
        Milestone storage milestone = _activeMilestone(milestoneId);
        if (
            milestone.state != MilestoneState.Disputed ||
            contractorAwardBps > BPS
        ) revert InvalidState();
        _settle(milestoneId, contractorAwardBps);
    }

    function cancelBeforeStart() external onlyClient nonReentrant {
        if (projectState != ProjectState.Funded) revert InvalidState();
        projectState = ProjectState.Cancelled;
        totalRefunded = totalBudget;
        paymentToken.safeTransfer(client, totalBudget);
        emit ProjectCancelled(totalBudget);
    }

    /// @notice Emergency circuit breaker. Arbitration cannot move funds while paused.
    function setPaused(bool paused_) external onlyArbitrator {
        paused = paused_;
        emit PauseChanged(paused_);
    }

    function milestoneCount() external view returns (uint256) {
        return milestones.length;
    }
    function getMilestone(
        uint256 milestoneId
    ) external view returns (Milestone memory) {
        if (milestoneId >= milestones.length) revert InvalidMilestone();
        return milestones[milestoneId];
    }
    function remainingEscrow() external view returns (uint256) {
        return totalBudget - totalReleased - totalRefunded;
    }

    function _activeMilestone(
        uint256 milestoneId
    ) internal view returns (Milestone storage milestone) {
        if (
            projectState != ProjectState.Active ||
            milestoneId != currentMilestone ||
            milestoneId >= milestones.length
        ) {
            revert InvalidMilestone();
        }
        milestone = milestones[milestoneId];
    }

    function _settle(uint256 milestoneId, uint16 contractorAwardBps) internal {
        Milestone storage milestone = milestones[milestoneId];
        milestone.state = MilestoneState.Settled;

        uint256 grossContractor = (uint256(milestone.amount) *
            contractorAwardBps) / BPS;
        uint256 clientAmount = uint256(milestone.amount) - grossContractor;
        uint256 feeAmount = (grossContractor * feeBps) / BPS;
        uint256 contractorAmount = grossContractor - feeAmount;

        totalReleased += contractorAmount + feeAmount;
        totalRefunded += clientAmount;
        currentMilestone = milestoneId + 1;

        if (feeAmount != 0) paymentToken.safeTransfer(feeRecipient, feeAmount);
        if (contractorAmount != 0)
            paymentToken.safeTransfer(contractor, contractorAmount);
        if (clientAmount != 0) paymentToken.safeTransfer(client, clientAmount);

        emit MilestoneSettled(
            milestoneId,
            contractorAmount,
            clientAmount,
            feeAmount
        );
        if (currentMilestone == milestones.length) {
            projectState = ProjectState.Completed;
            emit ProjectCompleted(block.timestamp);
        }
    }
}
