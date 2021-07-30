// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAloeBlendDerivedState {
    /**
     * @notice Calculates the vault's total holdings - in other words, how much of each token
     * the vault would hold if it withdrew all its liquidity from Uniswap and Compound.
     * @return inventory0 The amount of token0, as of last pokes
     * @return inventory1 The amount of token1, as of last pokes
     */
    function getInventory() external view returns (uint256 inventory0, uint256 inventory1);

    /**
     * @notice Calculates what the Uniswap position's width *should* be based on current volatility
     * @return width The width as a number of ticks
     */
    function getNextPositionWidth() external view returns (int24 width);

    /**
     * @notice Fetches Uniswap prices over 10 discrete intervals in the past hour, then computes statistics
     * @return mean The mean of the samples
     * @return sigma The standard deviation of the samples
     */
    function fetchPriceStatistics() external view returns (uint176 mean, uint176 sigma);

    /**
     * @notice Builds a memory array that can be passed to Uniswap V3's `observe` function to specify
     * intervals over which mean prices should be fetched
     * @return secondsAgos From how long ago each cumulative tick and liquidity value should be returned
     */
    function selectedOracleTimetable() external pure returns (uint32[] memory secondsAgos);
}
