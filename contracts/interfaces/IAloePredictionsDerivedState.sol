// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../structs/Bounds.sol";

interface IAloePredictionsDerivedState {
    /**
     * @notice Statistics for the most recent crowdsourced probability density function, evaluated about current price
     * @return areInverted Whether the reported values are for inverted prices
     * @return mean Result of `computeMean()`
     * @return sigmaL The sqrt of the lower semivariance
     * @return sigmaU The sqrt of the upper semivariance
     */
    function current()
        external
        view
        returns (
            bool areInverted,
            uint176 mean,
            uint128 sigmaL,
            uint128 sigmaU
        );

    /// @notice The earliest time at which the epoch can end
    function epochExpectedEndTime() external view returns (uint32);

    /**
     * @notice Aggregates proposals in the previous `epoch`. Only the top `NUM_PROPOSALS_TO_AGGREGATE`, ordered by
     * stake, will be considered.
     * @return mean The mean of the crowdsourced probability density function (1st Raw Moment)
     */
    function computeMean() external view returns (uint176 mean);

    /**
     * @notice Aggregates proposals in the previous `epoch`. Only the top `NUM_PROPOSALS_TO_AGGREGATE`, ordered by
     * stake, will be considered.
     * @return lower The lower semivariance of the crowdsourced probability density function (2nd Central Moment, Lower)
     * @return upper The upper semivariance of the crowdsourced probability density function (2nd Central Moment, Upper)
     */
    function computeSemivariancesAbout(uint176 center) external view returns (uint256 lower, uint256 upper);

    /**
     * @notice Fetches Uniswap prices over 10 discrete intervals in the past hour. Computes mean and standard
     * deviation of these samples, and returns "ground truth" bounds that should enclose ~95% of trading activity
     * @return bounds The "ground truth" price range that will be used when computing rewards
     * @return shouldInvertPricesNext Whether proposals in the next epoch should be submitted with inverted bounds
     */
    function fetchGroundTruth() external view returns (Bounds memory bounds, bool shouldInvertPricesNext);

    /**
     * @notice Builds a memory array that can be passed to Uniswap V3's `observe` function to specify
     * intervals over which mean prices should be fetched
     * @return secondsAgos From how long ago each cumulative tick and liquidity value should be returned
     */
    function selectedOracleTimetable() external pure returns (uint32[] memory secondsAgos);
}
