// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IAloeBlendState {
    /// @notice A variety of key parameters used frequently in the vault's code, stored in a single slot to save gas
    /// @return primaryLower The primary position's lower tick bound
    /// @return primaryUpper The primary position's upper tick bound
    /// @return limitLower The limit order's lower tick bound
    /// @return limitUpper The limit order's upper tick bound
    /// @return recenterTimestamp The `block.timestamp` from the last time the primary position moved
    /// @return maintenanceIsSustainable Whether `maintenanceBudget0` or `maintenanceBudget1` has filled up according to `K`
    /// @return locked Whether the vault is currently locked to reentrancy
    /// @dev If lower and upper bounds of a Uniswap position are equal, then the vault hasn't deposited liquidity to it
    function packedSlot()
        external
        view
        returns (
            int24 primaryLower,
            int24 primaryUpper,
            int24 limitLower,
            int24 limitUpper,
            uint48 recenterTimestamp,
            bool maintenanceIsSustainable,
            bool locked
        );

    /// @notice The size of the budget available for things like `rebalance()` rewards (token0)
    function maintenanceBudget0() external view returns (uint256);

    /// @notice The size of the budget available for things like `rebalance()` rewards (token1)
    function maintenanceBudget1() external view returns (uint256);
}
