// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAloeBlendImmutables {
    /// @dev Indicates how much of `maintenanceBudget{0,1}` can be used in single rebalance
    function DIVISOR_OF_REBALANCE_REWARD() external view returns (uint8);

    /// @dev Indicates the priority given to shrinking the Uniswap position to account for
    /// decreased volatility. A value of 2 means that shrinking is half as important as
    /// sliding.
    function DIVISOR_OF_SHRINK_URGENCY() external view returns (uint8);

    /// @dev The minimum width (in ticks) of the Uniswap position
    function MIN_WIDTH() external view returns (uint24);
}
