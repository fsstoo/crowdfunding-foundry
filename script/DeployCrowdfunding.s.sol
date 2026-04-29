// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Crowdfunding} from "../src/Crowdfunding.sol";

/// @title DeployCrowdfunding Script
/// @author FSTO
/// @notice Deploys the Crowdfunding contract to a network
contract DeployCrowdfunding is Script {
    /// @notice Deploys the Crowdfunding contract
    /// @return crowdfunding The deployed contract instance
    function run() external returns (Crowdfunding crowdfunding) {
        vm.startBroadcast();

        crowdfunding = new Crowdfunding();

        vm.stopBroadcast();

        return crowdfunding;
    }
}
