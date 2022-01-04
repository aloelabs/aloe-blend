// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IAloeBlendState {
    /// @notice The Uniswap position harvesting fees in the combined token0-token1 pool
    // function primary() external view returns (int24 lower, int24 upper, uint128 liquidity);

    /// @notice The Uniswap position used to rebalance when the vault deviates too far from 50/50
    // function limit() external view returns (int24 lower, int24 upper, uint128 liquidity);

    /// @notice The block.timestamp from the most recent call to `recenter()`
    // function recenterTimestamp() external view returns (uint256);

    function packedSlot()
        external
        view
        returns (
            int24 primaryLower,
            int24 primaryUpper,
            int24 limitLower,
            int24 limitUpper,
            uint64 epoch,
            uint48 recenterTimestamp,
            bool locked
        );

    /// @notice The size of the budget available for things like `rebalance()` rewards (token0)
    function maintenanceBudget0() external view returns (uint256);

    /// @notice The size of the budget available for things like `rebalance()` rewards (token1)
    function maintenanceBudget1() external view returns (uint256);
}
