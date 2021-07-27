// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAloePredictionsActions {
    /// @notice Advances the epoch no more than once per hour
    function advance() external;

    /**
     * @notice Allows users to submit proposals in `epoch`. These proposals specify aggregate position
     * in `epoch + 1` and adjusted stakes become claimable in `epoch + 2`
     * @param lower The Q128.48 price at the lower bound, unless `shouldInvertPrices`, in which case
     * this should be `1 / (priceAtUpperBound * 2 ** 16)`
     * @param upper The Q128.48 price at the upper bound, unless `shouldInvertPrices`, in which case
     * this should be `1 / (priceAtLowerBound * 2 ** 16)`
     * @param stake The amount of ALOE to stake on this proposal. Once submitted, you can't unsubmit!
     * @return key The unique ID of this proposal, used to update bounds and claim reward
     */
    function submitProposal(
        uint176 lower,
        uint176 upper,
        uint80 stake
    ) external returns (uint40 key);

    /**
     * @notice Allows users to update bounds of a proposal they submitted previously. This only
     * works if the epoch hasn't increased since submission
     * @param key The key of the proposal that should be updated
     * @param lower The Q128.48 price at the lower bound, unless `shouldInvertPrices`, in which case
     * this should be `1 / (priceAtUpperBound * 2 ** 16)`
     * @param upper The Q128.48 price at the upper bound, unless `shouldInvertPrices`, in which case
     * this should be `1 / (priceAtLowerBound * 2 ** 16)`
     */
    function updateProposal(
        uint40 key,
        uint176 lower,
        uint176 upper
    ) external;

    /**
     * @notice Allows users to reclaim ALOE that they staked in previous epochs, as long as
     * the epoch has ground truth information
     * @dev ALOE is sent to `proposal.source` not `msg.sender`, so anyone can trigger a claim
     * for anyone else
     * @param key The key of the proposal that should be judged and rewarded
     * @param extras An array of tokens for which extra incentives should be claimed
     */
    function claimReward(uint40 key, address[] calldata extras) external;
}
