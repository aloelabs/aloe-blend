// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../external/Compound.sol";
import "../external/Uniswap.sol";

interface IAloeBlendState {
    /// @dev The number of standard deviations to +/- from mean when setting Uniswap position
    function K() external view returns (uint8);

    /// @dev The Uniswap position harvesting fees in the combined token0-token1 pool
    function combine()
        external
        view
        returns (
            IUniswapV3Pool pool,
            int24 lower,
            int24 upper
        );

    /// @dev The Compound market where excess token0 is stored
    function silo0() external view returns (address cToken, address uToken);

    /// @dev The Compound market where excess token1 is stored
    function silo1() external view returns (address cToken, address uToken);
}
