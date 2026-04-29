// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract RejectEther {
    receive() external payable {
        revert();
    }
}
