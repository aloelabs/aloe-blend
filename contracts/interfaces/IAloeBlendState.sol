// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../external/Uniswap.sol";

import "./ISilo.sol";

interface IAloeBlendState {
    /// @dev The number of standard deviations to +/- from mean when setting Uniswap position
    function K() external view returns (uint8);

    /// @dev The portion of swap fees (in basis points) that goes toward maintenance
    function maintenanceFee() external view returns (uint256);

    /// @dev The size of the budget available for things like `rebalance()` rewards (token0)
    function maintenanceBudget0() external view returns (uint256);

    /// @dev The size of the budget available for things like `rebalance()` rewards (token1)
    function maintenanceBudget1() external view returns (uint256);

    /// @dev The Uniswap position harvesting fees in the combined token0-token1 pool
    function uniswap()
        external
        view
        returns (
            IUniswapV3Pool pool,
            int24 lower,
            int24 upper
        );

    /// @dev The silo where excess token0 is stored
    function silo0() external view returns (ISilo silo);

    /// @dev The silo where excess token1 is stored
    function silo1() external view returns (ISilo silo);
}
