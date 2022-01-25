// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "contracts/libraries/FullMath.sol";
import "contracts/interfaces/ISilo.sol";

interface IFEther {
    function accrueInterest() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function mint() external payable;

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function isCEther() external view returns (bool);
}

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;
}

IWETH constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

contract FuseFEtherSilo is ISilo {
    /// @inheritdoc ISilo
    string public constant name = "Rari Fuse WETH Silo";

    IFEther public immutable fEther;

    constructor(IFEther _fEther) {
        require(_fEther.isCEther(), "Aloe: not fEther");
        fEther = _fEther;
    }

    /// @inheritdoc ISilo
    function poke() external override {
        fEther.accrueInterest();
    }

    /// @inheritdoc ISilo
    function deposit(uint256 amount) external override {
        if (amount == 0) return;
        WETH.withdraw(amount);
        fEther.mint{value: amount}();
    }

    /// @inheritdoc ISilo
    function withdraw(uint256 amount) external override {
        if (amount == 0) return;
        require(fEther.redeemUnderlying(amount) == 0, "Fuse: redeem ETH failed");
        WETH.deposit{value: amount}();
    }

    /// @inheritdoc ISilo
    function balanceOf(address account) external view override returns (uint256 balance) {
        return FullMath.mulDiv(fEther.balanceOf(account), fEther.exchangeRateStored(), 1e18);
    }

    /// @inheritdoc ISilo
    function shouldAllowRemovalOf(address token) external view override returns (bool shouldAllow) {
        shouldAllow = token != address(fEther);
    }
}
