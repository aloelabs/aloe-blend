// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Ticks {
    // Lower tick of a Uniswap position
    int24 lower;
    // Upper tick of a Uniswap position
    int24 upper;
}
