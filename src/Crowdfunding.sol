// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Crowdfunding Contract
/// @author FSTO
/// @notice Allows users to create and fund crowdfunding campaigns
/// @dev
/// - Pull-based refunds for safety
/// - ReentrancyGuard used for external calls
/// - Overfunding is allowed by design
contract Crowdfunding is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error Crowdfunding__TransferFailed();
    error Crowdfunding__GoalMustBeGreaterThanZero();
    error Crowdfunding__GoalTooLarge();
    error Crowdfunding__DurationMustBeAtLeastOneDay();
    error Crowdfunding__CampaignDoesNotExist();
    error Crowdfunding__CampaignPassedDeadline();
    error Crowdfunding__ZeroContributionNotAllowed();
    error Crowdfunding__OnlyCreatorCanWithdraw();
    error Crowdfunding__CampaignStillActive();
    error Crowdfunding__GoalNotReached();
    error Crowdfunding__AlreadyWithdrawn();
    error Crowdfunding__CampaignWasSuccessful();
    error Crowdfunding__NoContributionToRefund();
    error Crowdfunding__DirectTransferNotAllowed();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Represents a crowdfunding campaign
    /// @param creator Address that created the campaign
    /// @param deadline Timestamp when campaign ends
    /// @param goal Funding goal in wei
    /// @param amountRaised Total ETH raised
    /// @param withdrawn Whether funds have been withdrawn
    struct Campaign {
        address creator;
        uint64 deadline;
        uint128 goal;
        uint128 amountRaised;
        bool withdrawn;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice campaignId => Campaign data
    mapping(uint256 => Campaign) public campaigns;

    /// @notice campaignId => contributor => amount contributed
    mapping(uint256 => mapping(address => uint256)) public contributions;

    /// @notice Total number of campaigns
    uint256 public campaignCount;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a campaign is created
    event CampaignCreated(uint256 indexed campaignId, address indexed creator, uint256 goal, uint256 deadline);

    /// @notice Emitted when a campaign is funded
    event CampaignFunded(uint256 indexed campaignId, address indexed funder, uint256 amount);

    /// @notice Emitted when creator withdraws funds
    event CampaignWithdrawn(uint256 indexed campaignId, address indexed creator, uint256 amount);

    /// @notice Emitted when a refund is issued
    event RefundIssued(uint256 indexed campaignId, address indexed funder, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new crowdfunding campaign
    /// @param goal Funding goal in wei (must be > 0)
    /// @param durationInDays Duration of campaign in days (>= 1)
    /// @return campaignId ID of the created campaign
    function createCampaign(uint256 goal, uint256 durationInDays) external returns (uint256 campaignId) {
        if (goal == 0) revert Crowdfunding__GoalMustBeGreaterThanZero();
        if (goal > type(uint128).max) revert Crowdfunding__GoalTooLarge();
        if (durationInDays == 0) revert Crowdfunding__DurationMustBeAtLeastOneDay();

        campaignId = campaignCount;

        unchecked {
            campaignCount++;
        }

        uint64 deadline = uint64(block.timestamp + (durationInDays * 1 days));

        campaigns[campaignId] =
            Campaign({creator: msg.sender, deadline: deadline, goal: uint128(goal), amountRaised: 0, withdrawn: false});

        emit CampaignCreated(campaignId, msg.sender, goal, deadline);
    }

    /// @notice Fund an active campaign
    /// @param campaignId ID of the campaign
    function fundCampaign(uint256 campaignId) external payable nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);

        // Checks
        if (msg.value == 0) revert Crowdfunding__ZeroContributionNotAllowed();
        if (block.timestamp >= campaign.deadline) {
            revert Crowdfunding__CampaignPassedDeadline();
        }

        // Effects
        contributions[campaignId][msg.sender] += msg.value;
        campaign.amountRaised += uint128(msg.value);

        emit CampaignFunded(campaignId, msg.sender, msg.value);
    }

    /// @notice Withdraw funds if campaign succeeded
    /// @param campaignId ID of the campaign
    function withdrawFunds(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);

        // Checks
        if (msg.sender != campaign.creator) revert Crowdfunding__OnlyCreatorCanWithdraw();
        if (block.timestamp < campaign.deadline) revert Crowdfunding__CampaignStillActive();
        if (campaign.amountRaised < campaign.goal) revert Crowdfunding__GoalNotReached();
        if (campaign.withdrawn) revert Crowdfunding__AlreadyWithdrawn();

        // Effects
        campaign.withdrawn = true;
        uint256 amount = campaign.amountRaised;

        // Interaction
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert Crowdfunding__TransferFailed();

        emit CampaignWithdrawn(campaignId, msg.sender, amount);
    }

    /// @notice Refund contributors if campaign failed
    /// @param campaignId ID of the campaign
    function refund(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);

        // Checks
        if (block.timestamp < campaign.deadline) revert Crowdfunding__CampaignStillActive();
        if (campaign.amountRaised >= campaign.goal) revert Crowdfunding__CampaignWasSuccessful();

        uint256 refundAmount = contributions[campaignId][msg.sender];
        if (refundAmount == 0) revert Crowdfunding__NoContributionToRefund();

        // Effects
        contributions[campaignId][msg.sender] = 0;

        // Interaction
        (bool success,) = payable(msg.sender).call{value: refundAmount}("");
        if (!success) revert Crowdfunding__TransferFailed();

        emit RefundIssued(campaignId, msg.sender, refundAmount);
    }

    /// @notice Get full campaign details
    /// @param campaignId ID of the campaign
    /// @return Campaign struct
    function getCampaign(uint256 campaignId) external view returns (Campaign memory) {
        Campaign storage campaign = _getCampaign(campaignId);
        return campaign;
    }

    /// @notice Get total amount raised
    /// @param campaignId ID of the campaign
    /// @return amountRaised Total ETH raised
    function getAmountRaised(uint256 campaignId) external view returns (uint256) {
        Campaign storage campaign = _getCampaign(campaignId);
        return campaign.amountRaised;
    }

    /// @notice Prevent accidental ETH transfers
    receive() external payable {
        revert Crowdfunding__DirectTransferNotAllowed();
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Fetch campaign or revert if it does not exist
    /// @param campaignId ID of the campaign
    /// @return campaign Campaign storage reference
    function _getCampaign(uint256 campaignId) internal view returns (Campaign storage campaign) {
        campaign = campaigns[campaignId];
        if (campaign.creator == address(0)) {
            revert Crowdfunding__CampaignDoesNotExist();
        }
    }
}
