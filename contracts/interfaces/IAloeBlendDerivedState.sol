// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IAloeBlendDerivedState {
    /**
     * @notice Calculates the rebalance urgency. Caller's reward is proportional to this value.
     * @return urgency How badly the vault wants its `rebalance()` function to be called
     */
    function getRebalanceUrgency() external view returns (uint32 urgency);

    /**
     * @notice Estimate's the vault's liabilities to users -- in other words, how much would be paid out if all
     * holders redeemed their LP tokens at once.
     * @dev Underestimates the true payout unless both silos and Uniswap positions have just been poked. Also
     * assumes that the maximum amount will accrue to the maintenance budget during the next `rebalance()`. If
     * it takes less than that for the budget to reach capacity, then the values reported here may increase after
     * calling `rebalance()`.
     * @return inventory0 The amount of token0 underlying all LP tokens
     * @return inventory1 The amount of token1 underlying all LP tokens
     */
    function getInventory() external view returns (uint256 inventory0, uint256 inventory1);
}
