// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAloePredictionsImmutables {
    /// @dev The maximum number of proposals that should be aggregated
    function NUM_PROPOSALS_TO_AGGREGATE() external view returns (uint8);

    /// @dev The number of standard deviations to +/- from the mean when computing ground truth bounds
    function GROUND_TRUTH_STDDEV_SCALE() external view returns (uint256);

    /// @dev The minimum length of an epoch, in seconds. Epochs may be longer if no one calls `advance`
    function EPOCH_LENGTH_SECONDS() external view returns (uint32);

    /// @dev The ALOE token used for staking
    function ALOE() external view returns (address);

    /// @dev The Uniswap pair for which predictions should be made
    function UNI_POOL() external view returns (address);

    /// @dev The incentive vault to use for staking extras and `advance()` reward
    function INCENTIVE_VAULT() external view returns (address);
}
