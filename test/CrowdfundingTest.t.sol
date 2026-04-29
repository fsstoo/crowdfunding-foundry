// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Crowdfunding} from "../src/Crowdfunding.sol";
import {DeployCrowdfunding} from "../script/DeployCrowdfunding.s.sol";
import {RejectEther} from "../test/RejectEther.sol";

contract CrowdFundingTest is Test {
    Crowdfunding funding;
    DeployCrowdfunding deployer;

    address CREATOR = makeAddr("CREATOR");
    address FUNDER = makeAddr("FUNDER");
    address FUNDER2 = makeAddr("FUNDER2");
    address FUNDER3 = makeAddr("FUNDER3");

    uint256 constant STARTING_BALANCE = 1_000 ether;
    uint256 constant GOAL = 500 ether;
    uint256 constant DURATION = 3;
    uint256 constant FUND_AMOUNT = 200 ether;

    uint256 campaignId;

    //campaign struct
    address creator;
    uint256 goal;
    uint256 deadline;
    uint256 amountRaised;
    bool withdrawn;

    function setUp() public {
        deployer = new DeployCrowdfunding();
        funding = deployer.run();

        vm.deal(CREATOR, STARTING_BALANCE);
        vm.deal(FUNDER, STARTING_BALANCE);
        vm.deal(FUNDER2, STARTING_BALANCE);
        vm.deal(FUNDER3, STARTING_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                             CREATE CAMPAIGN
    //////////////////////////////////////////////////////////////*/

    function testCreateCampaign() public {
        vm.prank(CREATOR);
        campaignId = funding.createCampaign(GOAL, DURATION);
        (creator, deadline, goal, amountRaised, withdrawn) = funding.campaigns(campaignId);

        assertEq(campaignId, 0);
        assertEq(creator, CREATOR);
        assertEq(GOAL, goal);
        assertEq(deadline, block.timestamp + (DURATION * 1 days));
        assertEq(amountRaised, 0);
        assertFalse(withdrawn);
    }

    function testCreateCampaignRevertsIfGoalZero() public {
        uint256 fundingGoal = 0;

        vm.prank(CREATOR);
        vm.expectRevert(Crowdfunding.Crowdfunding__GoalMustBeGreaterThanZero.selector);

        funding.createCampaign(fundingGoal, DURATION);
    }

    function testCreateCampaignRevertsIfDurationZero() public {
        uint256 fundingDuration = 0;

        vm.prank(CREATOR);
        vm.expectRevert(Crowdfunding.Crowdfunding__DurationMustBeAtLeastOneDay.selector);

        funding.createCampaign(GOAL, fundingDuration);
    }

    function testFuzz_CreateCampaign(uint256 goalAmount, uint256 duration) public {
        goalAmount = bound(goalAmount, 1 ether, 100 ether);
        duration = bound(duration, 1, 30);

        vm.prank(CREATOR);
        campaignId = funding.createCampaign(goalAmount, duration);
        (, deadline, goal,,) = funding.campaigns(campaignId);

        assertEq(deadline, block.timestamp + (duration * 1 days));
        assertEq(goalAmount, goal);
    }

    // /*//////////////////////////////////////////////////////////////
    //                          FUND CAMPAIGN
    // //////////////////////////////////////////////////////////////*/

    modifier campaignCreated() {
        vm.prank(CREATOR);
        campaignId = funding.createCampaign(GOAL, DURATION);
        _;
    }

    function testFundUpdatesState() public campaignCreated {
        uint256 fundAmount = 5 ether;

        vm.prank(FUNDER);
        funding.fundCampaign{value: fundAmount}(campaignId);

        (,,, amountRaised,) = funding.campaigns(campaignId);

        assertEq(amountRaised, fundAmount);
        assertEq(funding.contributions(campaignId, FUNDER), fundAmount);
    }

    function testFundRevertsIfZero() public campaignCreated {
        uint256 fundAmount = 0 ether;

        vm.prank(FUNDER);
        vm.expectRevert(Crowdfunding.Crowdfunding__ZeroContributionNotAllowed.selector);
        funding.fundCampaign{value: fundAmount}(campaignId);
    }

    function testFundRevertsIfPastDeadline() public campaignCreated {
        (,, deadline,,) = funding.campaigns(campaignId);

        vm.warp(deadline + 1);

        vm.prank(FUNDER);
        vm.expectRevert(Crowdfunding.Crowdfunding__CampaignPassedDeadline.selector);
        funding.fundCampaign{value: FUND_AMOUNT}(campaignId);
    }

    function testMultipleFundersIncreaseAmountRaised() public campaignCreated {
        vm.prank(FUNDER);
        funding.fundCampaign{value: 5 ether}(campaignId);

        vm.prank(FUNDER2);
        funding.fundCampaign{value: 10 ether}(campaignId);

        (,,, amountRaised,) = funding.campaigns(campaignId);

        assertEq(amountRaised, 15 ether);
    }

    function testFuzz_FundCampaign(uint256 amount) public campaignCreated {
        amount = bound(amount, 1, GOAL / 2);

        vm.deal(FUNDER, amount);

        vm.prank(FUNDER);
        funding.fundCampaign{value: amount}(campaignId);

        assertEq(funding.contributions(campaignId, FUNDER), amount);
    }

    function testFuzz_MultipleFunders(uint256 a, uint256 b) public campaignCreated {
        a = bound(a, 1, GOAL / 2);
        b = bound(b, 1, GOAL / 2);

        vm.deal(FUNDER2, a);
        vm.deal(FUNDER3, b);

        vm.prank(FUNDER2);
        funding.fundCampaign{value: a}(campaignId);

        vm.prank(FUNDER3);
        funding.fundCampaign{value: b}(campaignId);

        (,,, uint256 raised,) = funding.campaigns(campaignId);

        assertEq(raised, a + b);
        assertEq(funding.contributions(campaignId, FUNDER2), a);
        assertEq(funding.contributions(campaignId, FUNDER3), b);
    }

    // /*//////////////////////////////////////////////////////////////
    //                          WITHDRAW FUNDS
    // //////////////////////////////////////////////////////////////*/

    modifier campaignFunded() {
        vm.prank(FUNDER);
        funding.fundCampaign{value: FUND_AMOUNT}(campaignId);
        vm.prank(FUNDER2);
        funding.fundCampaign{value: FUND_AMOUNT}(campaignId);
        vm.prank(FUNDER3);
        funding.fundCampaign{value: FUND_AMOUNT}(campaignId);
        _;
    }

    function testWithdrawSuccess() public campaignCreated campaignFunded {
        (,, deadline,,) = funding.campaigns(campaignId);
        vm.warp(deadline + 1);

        (,,,, bool withdrawnBefore) = funding.campaigns(campaignId);
        assertFalse(withdrawnBefore);

        uint256 before = CREATOR.balance;

        vm.prank(CREATOR);
        funding.withdrawFunds(campaignId);

        (,,, uint256 _amountRaised, bool withdrawnAfter) = funding.campaigns(campaignId);

        assertEq(CREATOR.balance, before + _amountRaised);
        assertTrue(withdrawnAfter);
    }

    function testWithdrawRevertsIfNotCreator() public campaignCreated campaignFunded {
        (,, deadline,,) = funding.campaigns(campaignId);
        vm.warp(deadline + 1);

        vm.prank(FUNDER);
        vm.expectRevert(Crowdfunding.Crowdfunding__OnlyCreatorCanWithdraw.selector);
        funding.withdrawFunds(campaignId);
    }

    function testWithdrawRevertsIfCampaignStillActive() public campaignCreated campaignFunded {
        vm.prank(CREATOR);
        vm.expectRevert(Crowdfunding.Crowdfunding__CampaignStillActive.selector);
        funding.withdrawFunds(campaignId);
    }

    function testWithdrawRevertsIfGoalNotReached() public campaignCreated {
        vm.prank(FUNDER);
        funding.fundCampaign{value: FUND_AMOUNT}(campaignId);

        (,, deadline,,) = funding.campaigns(campaignId);
        vm.warp(deadline + 1);

        vm.prank(CREATOR);
        vm.expectRevert(Crowdfunding.Crowdfunding__GoalNotReached.selector);
        funding.withdrawFunds(campaignId);
    }

    function testWithdrawRevertsIfAlreadyWithdrawn() public campaignCreated campaignFunded {
        (,, deadline,,) = funding.campaigns(campaignId);
        vm.warp(deadline + 1);

        vm.prank(CREATOR);
        funding.withdrawFunds(campaignId);

        vm.prank(CREATOR);
        vm.expectRevert(Crowdfunding.Crowdfunding__AlreadyWithdrawn.selector);
        funding.withdrawFunds(campaignId);
    }

    function testWithdrawRevertsIfTransferFails() public {
        RejectEther rejectEther = new RejectEther();

        vm.prank(address(rejectEther));
        campaignId = funding.createCampaign(GOAL, DURATION);

        vm.prank(FUNDER);
        funding.fundCampaign{value: GOAL}(campaignId);

        (,, deadline,,) = funding.campaigns(campaignId);
        vm.warp(deadline + 1);

        vm.prank(address(rejectEther));
        vm.expectRevert(Crowdfunding.Crowdfunding__TransferFailed.selector);
        funding.withdrawFunds(campaignId);
    }

    // /*//////////////////////////////////////////////////////////////
    //                              REFUND
    // //////////////////////////////////////////////////////////////*/

    modifier campaignFailed() {
        vm.prank(FUNDER);
        funding.fundCampaign{value: FUND_AMOUNT}(campaignId);
        vm.prank(FUNDER2);
        funding.fundCampaign{value: FUND_AMOUNT}(campaignId);

        //campaign didn't reached the goal, deadline passed

        (,, deadline,,) = funding.campaigns(campaignId);
        vm.warp(deadline + 1);
        _;
    }

    function testRefund() public campaignCreated campaignFailed {
        uint256 funderBalanceBefore = FUNDER.balance;
        uint256 funder2BalanceBefore = FUNDER2.balance;

        uint256 contributor1 = funding.contributions(campaignId, FUNDER);
        (,,, amountRaised,) = funding.campaigns(campaignId);

        assertEq(contributor1, FUND_AMOUNT);
        assertEq(amountRaised, funding.getAmountRaised(campaignId));

        vm.prank(FUNDER);
        funding.refund(campaignId);

        uint256 funderBalanceAfter = FUNDER.balance;
        uint256 funder2BalanceAfter = FUNDER2.balance;

        assertEq(funderBalanceAfter, funderBalanceBefore + FUND_AMOUNT);
        assertEq(funder2BalanceAfter, funder2BalanceBefore);
    }

    function testMultipleRefundsClearContributions() public campaignCreated campaignFailed {
        vm.prank(FUNDER);
        funding.refund(campaignId);

        vm.prank(FUNDER2);
        funding.refund(campaignId);

        assertEq(funding.contributions(campaignId, FUNDER), 0);
        assertEq(funding.contributions(campaignId, FUNDER2), 0);
    }

    function testRefundRevertsIfCampaignStillActive() public campaignCreated campaignFunded {
        vm.prank(CREATOR);
        vm.expectRevert(Crowdfunding.Crowdfunding__CampaignStillActive.selector);
        funding.refund(campaignId);
    }

    function testRefundRevertsIfCampaignWasSuccessful() public campaignCreated campaignFunded {
        (,, deadline,,) = funding.campaigns(campaignId);
        vm.warp(deadline + 1);

        vm.prank(CREATOR);
        vm.expectRevert(Crowdfunding.Crowdfunding__CampaignWasSuccessful.selector);
        funding.refund(campaignId);
    }

    function testRefundRevertsIfNoContributionToRefund() public campaignCreated campaignFailed {
        vm.prank(FUNDER);
        funding.refund(campaignId);

        vm.prank(FUNDER);
        vm.expectRevert(Crowdfunding.Crowdfunding__NoContributionToRefund.selector);
        funding.refund(campaignId);
    }

    function testRefundRevertsIfNeverContributed() public campaignCreated campaignFailed {
        vm.prank(FUNDER3); // FUNDER3 never contributed
        vm.expectRevert(Crowdfunding.Crowdfunding__NoContributionToRefund.selector);
        funding.refund(campaignId);
    }

    function testRefundRevertsIfTransferFailed() public {
        RejectEther rejectEther = new RejectEther();
        vm.deal(address(rejectEther), STARTING_BALANCE);

        vm.prank(CREATOR);
        campaignId = funding.createCampaign(GOAL, DURATION);

        vm.prank(address(rejectEther));
        funding.fundCampaign{value: FUND_AMOUNT}(campaignId);

        (,, deadline,,) = funding.campaigns(campaignId);
        vm.warp(deadline + 1);

        vm.prank(address(rejectEther));
        vm.expectRevert(Crowdfunding.Crowdfunding__TransferFailed.selector);
        funding.refund(campaignId);
    }

    function testFuzz_Refund(uint256 amount) public campaignCreated {
        amount = bound(amount, 1, GOAL - 1 ether);

        uint256 balanceBefore = FUNDER2.balance;

        vm.prank(FUNDER2);
        funding.fundCampaign{value: amount}(campaignId);

        (,, deadline,,) = funding.campaigns(campaignId);
        vm.warp(deadline + 1);

        vm.prank(FUNDER2);
        funding.refund(campaignId);

        assertEq(funding.contributions(campaignId, FUNDER2), 0);
        assertEq(FUNDER2.balance, balanceBefore);
    }
}
