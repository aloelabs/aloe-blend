// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IAloeBlendState {
    /// @dev The size of the budget available for things like `rebalance()` rewards (token0)
    function maintenanceBudget0() external view returns (uint256);

    /// @dev The size of the budget available for things like `rebalance()` rewards (token1)
    function maintenanceBudget1() external view returns (uint256);

    /// @dev The Uniswap position harvesting fees in the combined token0-token1 pool
    function primary()
        external
        view
        returns (
            IUniswapV3Pool pool,
            int24 lower,
            int24 upper
        );
}
