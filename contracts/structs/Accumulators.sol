// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/UINT512.sol";

struct Accumulators {
    // The number of (proposals added - proposals removed) during the epoch
    uint40 proposalCount;
    // The total amount of ALOE staked; fits in uint80 because max supply is 1000000 with 18 decimals
    uint80 stakeTotal;
    // For the remaining properties, read comments as if `stake`, `lower`, and `upper` are NumPy arrays.
    // Each index represents a proposal, e.g. proposal 0 would be `(stake[0], lower[0], upper[0])`

    // `(stake * (upper - lower)).sum()`
    uint256 stake0thMomentRaw;
    // `lower.sum()`
    uint256 sumOfLowerBounds;
    // `(stake * lower).sum()`
    uint256 sumOfLowerBoundsWeighted;
    // `upper.sum()`
    uint256 sumOfUpperBounds;
    // `(stake * upper).sum()`
    uint256 sumOfUpperBoundsWeighted;
    // `(np.square(lower) + np.square(upper)).sum()`
    UINT512 sumOfSquaredBounds;
    // `(stake * (np.square(lower) + np.square(upper))).sum()`
    UINT512 sumOfSquaredBoundsWeighted;
}
