// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Bounds {
    // Q128.48 price at tickLower of a Uniswap position
    uint176 lower;
    // Q128.48 price at tickUpper of a Uniswap position
    uint176 upper;
}
