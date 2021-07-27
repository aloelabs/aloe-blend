// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Accumulators.sol";
import "./Bounds.sol";

struct EpochSummary {
    Bounds groundTruth;
    Accumulators accumulators;
}
