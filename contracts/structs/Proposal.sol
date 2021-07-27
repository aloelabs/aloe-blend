// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Proposal {
    // The address that submitted the proposal
    address source;
    // The epoch in which the proposal was submitted
    uint24 epoch;
    // Q128.48 price at tickLower of proposed Uniswap position
    uint176 lower;
    // Q128.48 price at tickUpper of proposed Uniswap position
    uint176 upper;
    // The amount of ALOE held; fits in uint80 because max supply is 1000000 with 18 decimals
    uint80 stake;
}
