// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAloePredictionsActions.sol";
import "./IAloePredictionsDerivedState.sol";
import "./IAloePredictionsEvents.sol";
import "./IAloePredictionsState.sol";

/// @title Aloe predictions market interface
/// @dev The interface is broken up into many smaller pieces
interface IAloePredictions is
    IAloePredictionsActions,
    IAloePredictionsDerivedState,
    IAloePredictionsEvents,
    IAloePredictionsState
{

}
