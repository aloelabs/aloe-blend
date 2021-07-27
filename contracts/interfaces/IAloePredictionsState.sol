// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../structs/EpochSummary.sol";
import "../structs/Proposal.sol";

interface IAloePredictionsState {
    /// @dev A mapping containing every proposal. These get deleted when claimed
    function proposals(uint40 key)
        external
        view
        returns (
            address source,
            uint24 submissionEpoch,
            uint176 lower,
            uint176 upper,
            uint80 stake
        );

    /// @dev The unique ID that will be assigned to the next submitted proposal
    function nextProposalKey() external view returns (uint40);

    /// @dev The current epoch. May increase up to once per hour. Never decreases
    function epoch() external view returns (uint24);

    /// @dev The time at which the current epoch started
    function epochStartTime() external view returns (uint32);

    /// @dev Whether new proposals should be submitted with inverted prices
    function shouldInvertPrices() external view returns (bool);

    /// @dev Whether proposals in `epoch - 1` were submitted with inverted prices
    function didInvertPrices() external view returns (bool);
}
