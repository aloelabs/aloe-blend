// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAloePredictionsEvents {
    event ProposalSubmitted(
        address indexed source,
        uint24 indexed epoch,
        uint40 key,
        uint176 lower,
        uint176 upper,
        uint80 stake
    );

    event ProposalUpdated(address indexed source, uint24 indexed epoch, uint40 key, uint176 lower, uint176 upper);

    event FetchedGroundTruth(uint176 lower, uint176 upper, bool didInvertPrices);

    event Advanced(uint24 epoch, uint32 epochStartTime);

    event ClaimedReward(address indexed recipient, uint24 indexed epoch, uint40 key, uint80 amount);
}
