// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./libraries/Equations.sol";
import "./libraries/UINT512.sol";

import "./structs/Accumulators.sol";
import "./structs/EpochSummary.sol";
import "./structs/Proposal.sol";

import "./interfaces/IAloePredictionsState.sol";

contract AloePredictionsState is IAloePredictionsState {
    using UINT512Math for UINT512;

    /// @dev The maximum number of proposals that should be aggregated
    uint8 public constant NUM_PROPOSALS_TO_AGGREGATE = 100;

    /// @dev A mapping containing a summary of every epoch
    mapping(uint24 => EpochSummary) public summaries;

    /// @inheritdoc IAloePredictionsState
    mapping(uint40 => Proposal) public override proposals;

    /// @dev An array containing keys of the highest-stake proposals. Outer index 0 corresponds to
    /// most recent even-numbered epoch; outer index 1 corresponds to most recent odd-numbered epoch
    uint40[NUM_PROPOSALS_TO_AGGREGATE][2] public highestStakeKeys;

    /// @inheritdoc IAloePredictionsState
    uint40 public override nextProposalKey = 0;

    /// @inheritdoc IAloePredictionsState
    uint24 public override epoch;

    /// @inheritdoc IAloePredictionsState
    uint32 public override epochStartTime;

    /// @inheritdoc IAloePredictionsState
    bool public override shouldInvertPrices;

    /// @inheritdoc IAloePredictionsState
    bool public override didInvertPrices;

    /// @dev Should run after `_submitProposal`, otherwise `accumulators.proposalCount` will be off by 1
    function _organizeProposals(uint40 newestProposalKey, uint80 newestProposalStake) internal {
        uint40 insertionIdx = summaries[epoch].accumulators.proposalCount - 1;
        uint24 parity = epoch % 2;

        if (insertionIdx < NUM_PROPOSALS_TO_AGGREGATE) {
            highestStakeKeys[parity][insertionIdx] = newestProposalKey;
            return;
        }

        // Start off by assuming the first key in the array corresponds to min stake
        insertionIdx = 0;
        uint80 stakeMin = proposals[highestStakeKeys[parity][0]].stake;
        uint80 stake;
        // Now iterate through rest of keys and update [insertionIdx, stakeMin] as needed
        for (uint8 i = 1; i < NUM_PROPOSALS_TO_AGGREGATE; i++) {
            stake = proposals[highestStakeKeys[parity][i]].stake;
            if (stake < stakeMin) {
                insertionIdx = i;
                stakeMin = stake;
            }
        }

        // `>=` (instead of `>`) prefers newer proposals to old ones. This is what we want,
        // since newer proposals will have more market data on which to base bounds.
        if (newestProposalStake >= stakeMin) highestStakeKeys[parity][insertionIdx] = newestProposalKey;
    }

    function _submitProposal(
        uint80 stake,
        uint176 lower,
        uint176 upper
    ) internal returns (uint40 key) {
        require(stake != 0, "Aloe: Need stake");
        require(lower < upper, "Aloe: Impossible bounds");

        summaries[epoch].accumulators.proposalCount++;
        accumulate(stake, lower, upper);

        key = nextProposalKey;
        proposals[key] = Proposal(msg.sender, epoch, lower, upper, stake);
        nextProposalKey++;
    }

    function _updateProposal(
        uint40 key,
        uint176 lower,
        uint176 upper
    ) internal {
        require(lower < upper, "Aloe: Impossible bounds");

        Proposal storage proposal = proposals[key];
        require(proposal.source == msg.sender, "Aloe: Not yours");
        require(proposal.epoch == epoch, "Aloe: Not fluid");

        unaccumulate(proposal.stake, proposal.lower, proposal.upper);
        accumulate(proposal.stake, lower, upper);

        proposal.lower = lower;
        proposal.upper = upper;
    }

    function accumulate(
        uint80 stake,
        uint176 lower,
        uint176 upper
    ) private {
        unchecked {
            Accumulators storage accumulators = summaries[epoch].accumulators;

            accumulators.stakeTotal += stake;
            accumulators.stake0thMomentRaw += uint256(stake) * uint256(upper - lower);
            accumulators.sumOfLowerBounds += lower;
            accumulators.sumOfUpperBounds += upper;
            accumulators.sumOfLowerBoundsWeighted += uint256(stake) * uint256(lower);
            accumulators.sumOfUpperBoundsWeighted += uint256(stake) * uint256(upper);

            (uint256 LS0, uint256 MS0, uint256 LS1, uint256 MS1) = Equations.eqn0(stake, lower, upper);

            // update each storage slot only once
            accumulators.sumOfSquaredBounds.iadd(LS0, MS0);
            accumulators.sumOfSquaredBoundsWeighted.iadd(LS1, MS1);
        }
    }

    function unaccumulate(
        uint80 stake,
        uint176 lower,
        uint176 upper
    ) private {
        unchecked {
            Accumulators storage accumulators = summaries[epoch].accumulators;

            accumulators.stakeTotal -= stake;
            accumulators.stake0thMomentRaw -= uint256(stake) * uint256(upper - lower);
            accumulators.sumOfLowerBounds -= lower;
            accumulators.sumOfUpperBounds -= upper;
            accumulators.sumOfLowerBoundsWeighted -= uint256(stake) * uint256(lower);
            accumulators.sumOfUpperBoundsWeighted -= uint256(stake) * uint256(upper);

            (uint256 LS0, uint256 MS0, uint256 LS1, uint256 MS1) = Equations.eqn0(stake, lower, upper);

            // update each storage slot only once
            accumulators.sumOfSquaredBounds.isub(LS0, MS0);
            accumulators.sumOfSquaredBoundsWeighted.isub(LS1, MS1);
        }
    }

    /// @dev Consolidate accumulators into variables better-suited for reward math
    function _consolidateAccumulators(uint24 inEpoch) internal {
        EpochSummary storage summary = summaries[inEpoch];
        require(summary.groundTruth.upper != 0, "Aloe: Need ground truth");

        uint256 stakeTotal = summary.accumulators.stakeTotal;

        // Reassign sumOfSquaredBounds to sumOfSquaredErrors
        summary.accumulators.sumOfSquaredBounds = Equations.eqn1(
            summary.accumulators.sumOfSquaredBounds,
            summary.accumulators.sumOfLowerBounds,
            summary.accumulators.sumOfUpperBounds,
            summary.accumulators.proposalCount,
            summary.groundTruth.lower,
            summary.groundTruth.upper
        );

        // Compute reward denominator
        UINT512 memory denom = summary.accumulators.sumOfSquaredBounds;
        // --> Scale this initial term by total stake
        (denom.LS, denom.MS) = denom.muls(stakeTotal);
        // --> Subtract sum of all weighted squared errors
        UINT512 memory temp =
            Equations.eqn1(
                summary.accumulators.sumOfSquaredBoundsWeighted,
                summary.accumulators.sumOfLowerBoundsWeighted,
                summary.accumulators.sumOfUpperBoundsWeighted,
                stakeTotal,
                summary.groundTruth.lower,
                summary.groundTruth.upper
            );
        (denom.LS, denom.MS) = denom.sub(temp.LS, temp.MS);

        // Reassign sumOfSquaredBoundsWeighted to denom
        summary.accumulators.sumOfSquaredBoundsWeighted = denom;

        delete summary.accumulators.stake0thMomentRaw;
        delete summary.accumulators.sumOfLowerBounds;
        delete summary.accumulators.sumOfLowerBoundsWeighted;
        delete summary.accumulators.sumOfUpperBounds;
        delete summary.accumulators.sumOfUpperBoundsWeighted;
    }
}
