// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Crowdfunding} from "../../src/Crowdfunding.sol";

contract Handler is Test {
    Crowdfunding public funding;

    address[] public users;
    uint256 public campaignId;

    // tracking
    mapping(address => uint256) public ghostContributions;
    uint256 public ghostTotalContributed;

    constructor(Crowdfunding _funding, uint256 _campaignId) {
        funding = _funding;
        campaignId = _campaignId;

        // create users
        for (uint256 i = 0; i < 15; i++) {
            address user = makeAddr(string(abi.encodePacked("USER", i)));
            users.push(user);
            vm.deal(user, 1_000 ether);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ACTIONS
    //////////////////////////////////////////////////////////////*/

    function fund(uint256 userIndex, uint256 amount) public {
        address user = users[userIndex % users.length];
        amount = bound(amount, 1, 50 ether);

        if (user.balance < amount) {
            vm.deal(user, amount);
        }

        vm.startPrank(user);
        try funding.fundCampaign{value: amount}(campaignId) {
            ghostContributions[user] += amount;
            ghostTotalContributed += amount;
        } catch {}
        vm.stopPrank();
    }

    function refund(uint256 userIndex) public {
        address user = users[userIndex % users.length];

        vm.startPrank(user);
        try funding.refund(campaignId) {
            ghostTotalContributed -= ghostContributions[user];
            ghostContributions[user] = 0;
        } catch {}
        vm.stopPrank();
    }

    function withdraw() public {
        (address creator,,,,) = funding.campaigns(campaignId);
        address[] memory _users = users;

        vm.startPrank(creator);
        try funding.withdrawFunds(campaignId) {
            ghostTotalContributed = 0;
            // Sync individual ghost contributions too
            for (uint256 i = 0; i < _users.length; i++) {
                ghostContributions[_users[i]] = 0;
            }
        } catch {}
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function getUsers() external view returns (address[] memory) {
        return users;
    }
}
