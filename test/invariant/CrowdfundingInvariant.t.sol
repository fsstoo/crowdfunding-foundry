// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Crowdfunding} from "../../src/Crowdfunding.sol";
import {DeployCrowdfunding} from "../../script/DeployCrowdfunding.s.sol";
import {Handler} from "./Handler.t.sol";

contract CrowdfundingInvariant is StdInvariant, Test {
    Crowdfunding funding;
    Handler handler;

    uint256 campaignId;

    function setUp() public {
        DeployCrowdfunding deployer = new DeployCrowdfunding();
        funding = deployer.run();

        address creator = makeAddr("CREATOR");
        vm.deal(creator, 1_000 ether);

        vm.prank(creator);
        campaignId = funding.createCampaign(500 ether, 3);

        handler = new Handler(funding, campaignId);

        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANTS
    //////////////////////////////////////////////////////////////*/

    ///  Core invariant: accounting must match
    function invariant_TotalContributionsMatch() public {
        (,,, uint256 amountRaised,) = funding.campaigns(campaignId);

        assertEq(amountRaised, handler.ghostTotalContributed());
    }

    ///  No user has more contribution than total raised
    function invariant_UserContributionBounded() public {
        address[] memory users = handler.getUsers();

        (,,, uint256 amountRaised,) = funding.campaigns(campaignId);

        for (uint256 i = 0; i < users.length; i++) {
            uint256 contrib = funding.contributions(campaignId, users[i]);
            assertLe(contrib, amountRaised);
        }
    }

    ///  Contract balance should match accounting (unless withdrawn)
    function invariant_BalanceMatchesRaised() public {
        (,,, uint256 amountRaised, bool withdrawn) = funding.campaigns(campaignId);

        if (!withdrawn) {
            assertEq(address(funding).balance, amountRaised);
        }
    }

    /// sum of user contributions == total
    function invariant_SumOfUsersMatchesTotal() public {
        address[] memory users = handler.getUsers();

        uint256 sum;

        for (uint256 i = 0; i < users.length; i++) {
            sum += funding.contributions(campaignId, users[i]);
        }

        (,,, uint256 amountRaised,) = funding.campaigns(campaignId);

        assertEq(sum, amountRaised);
    }

    /// after withdrawn funds should be clear
    function invariant_WithdrawClearsBalance() public {
        (,,, uint256 amountRaised, bool withdrawn) = funding.campaigns(campaignId);

        if (withdrawn) {
            assertEq(address(funding).balance, 0);
            assertEq(amountRaised, 0);
        }
    }
}
