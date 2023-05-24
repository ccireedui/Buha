// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBuhaToken {
    event MintStarted(address indexed user, uint256 term, uint256 rank);

    event Claimed(address indexed user, uint256 amount);

    event Staked(address indexed user, uint256 amount, uint256 term);

    event Withdrawn(address indexed user, uint256 amount, uint256 reward);
}
