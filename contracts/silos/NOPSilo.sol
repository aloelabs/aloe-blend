// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "contracts/interfaces/ISilo.sol";

contract NOPSilo is ISilo {
    /// @inheritdoc ISilo
    string public constant name = "No-Op Silo";

    /// @inheritdoc ISilo
    function poke() external override {}

    /// @inheritdoc ISilo
    function deposit(uint256 amount) external override {}

    /// @inheritdoc ISilo
    function withdraw(uint256 amount) external override {}

    /// @inheritdoc ISilo
    function balanceOf(address) external pure override returns (uint256 balance) {
        balance = 0;
    }

    /// @inheritdoc ISilo
    function shouldAllowRemovalOf(address) external pure override returns (bool shouldAllow) {
        shouldAllow = true;
    }
}
