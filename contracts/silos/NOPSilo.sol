// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "contracts/interfaces/ISilo.sol";

contract NOPSilo is ISilo {
    /// @inheritdoc ISilo
    string public name;

    constructor(address _token) {
        name = string(abi.encodePacked(IERC20Metadata(_token).symbol(), " no-op Silo"));
    }

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
