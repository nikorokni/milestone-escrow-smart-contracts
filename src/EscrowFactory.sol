// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MilestoneEscrow} from "./MilestoneEscrow.sol";

/// @title EscrowFactory
/// @notice Permissionless registry and deployer for milestone escrow agreements.
contract EscrowFactory {
    event EscrowCreated(
        address indexed escrow,
        address indexed client,
        address indexed contractor,
        address arbitrator
    );

    address[] private escrows;
    mapping(address => address[]) private participantEscrows;

    function createEscrow(
        address contractor,
        address arbitrator,
        address paymentToken,
        address feeRecipient,
        uint16 feeBps,
        uint64 reviewPeriod,
        uint64 disputeWindow,
        uint128[] calldata amounts,
        uint64[] calldata dueDates
    ) external returns (address escrow) {
        escrow = address(
            new MilestoneEscrow(
                msg.sender,
                contractor,
                arbitrator,
                paymentToken,
                feeRecipient,
                feeBps,
                reviewPeriod,
                disputeWindow,
                amounts,
                dueDates
            )
        );
        escrows.push(escrow);
        participantEscrows[msg.sender].push(escrow);
        participantEscrows[contractor].push(escrow);
        participantEscrows[arbitrator].push(escrow);
        emit EscrowCreated(escrow, msg.sender, contractor, arbitrator);
    }

    function escrowCount() external view returns (uint256) {
        return escrows.length;
    }
    function escrowAt(uint256 index) external view returns (address) {
        return escrows[index];
    }
    function escrowsFor(
        address participant
    ) external view returns (address[] memory) {
        return participantEscrows[participant];
    }
}
