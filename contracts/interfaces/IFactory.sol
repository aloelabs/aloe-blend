// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IVolatilityOracle.sol";

interface IFactory {
    /// @notice The address of the volatility oracle
    function volatilityOracle() external view returns (IVolatilityOracle);
}
