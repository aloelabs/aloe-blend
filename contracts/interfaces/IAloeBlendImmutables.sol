// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAloeBlendImmutables {
    /// @dev The minimum width (in ticks) of the Uniswap position
    function MIN_WIDTH() external view returns (uint24);
}
