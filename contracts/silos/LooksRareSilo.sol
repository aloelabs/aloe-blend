// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "contracts/libraries/FullMath.sol";
import "contracts/interfaces/ISilo.sol";

interface ILooksRareFeeSharingSystem {
    function PRECISION_FACTOR() external view returns (uint256);
    function looksRareToken() external view returns (address);
    function calculateSharesValueInLOOKS(address user) external view returns (uint256);
    function calculateSharePriceInLOOKS() external view returns (uint256);
    function deposit(uint256 amount, bool claimRewardToken) external;
    function withdraw(uint256 shares, bool claimRewardToken) external;
    function userInfo(address user) external view returns (uint256 shares, uint256 userRewardPerTokenPaid, uint256 rewards);
}

contract LooksRareSilo is ISilo {
    /// @inheritdoc ISilo
    string public constant name = "LooksRare Silo";

    ILooksRareFeeSharingSystem public immutable feeSharingSystem;

    uint256 public immutable precisionFactor;

    address public immutable LOOKS;

    constructor(ILooksRareFeeSharingSystem _feeSharingSystem) {
        feeSharingSystem = _feeSharingSystem;
        precisionFactor = feeSharingSystem.PRECISION_FACTOR();
        LOOKS = feeSharingSystem.looksRareToken();
    }

    /// @inheritdoc ISilo
    function poke() external override {}

    /// @inheritdoc ISilo
    function deposit(uint256 amount) external override {
        if (amount < precisionFactor) return;
        _approve(LOOKS, address(feeSharingSystem), amount);
        feeSharingSystem.deposit(amount, false);
    }

    /// @inheritdoc ISilo
    function withdraw(uint256 amount) external override {
        if (amount == 0) return;
        uint256 shares = 1 + FullMath.mulDiv(amount, 1e18, feeSharingSystem.calculateSharePriceInLOOKS());
        (uint256 maxShares, , ) = feeSharingSystem.userInfo(address(this));
        if (shares > maxShares) shares = maxShares;

        feeSharingSystem.withdraw(shares, true);
    }

    /// @inheritdoc ISilo
    function balanceOf(address account) external view override returns (uint256 balance) {
        return feeSharingSystem.calculateSharesValueInLOOKS(account);
    }

    /// @inheritdoc ISilo
    function shouldAllowRemovalOf(address token) external view override returns (bool shouldAllow) {}

    function _approve(
        address token,
        address spender,
        uint256 amount
    ) private {
        // 200 gas to read uint256
        if (IERC20(token).allowance(address(this), spender) < amount) {
            // 20000 gas to write uint256 if changing from zero to non-zero
            // 5000  gas to write uint256 if changing from non-zero to non-zero
            IERC20(token).approve(spender, type(uint256).max);
        }
    }
}
