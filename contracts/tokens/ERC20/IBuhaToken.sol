// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBuhaToken {
    event Minted(
        address indexed user,
        uint64 term,
        uint64 maturityTs,
        uint64 rank,
        uint64 amplifier,
        uint64 eaaRate
    );
}
