// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "contracts/libraries/FullMath.sol";
import "contracts/interfaces/ISilo.sol";

interface IX2Y2FeeSharingSystem {
    function PRECISION_FACTOR() external view returns (uint256);

    function x2y2Token() external view returns (address);

    function calculateSharesValueInX2Y2(address user) external view returns (uint256);

    function calculateSharePriceInX2Y2() external view returns (uint256);

    function deposit(uint256 amount, bool claimRewardToken) external;

    function withdraw(uint256 shares, bool claimRewardToken) external;

    function userInfo(address user)
        external
        view
        returns (
            uint256 shares,
            uint256 userRewardPerTokenPaid,
            uint256 rewards
        );
}

contract X2Y2Silo is ISilo {
    /// @inheritdoc ISilo
    string public constant name = "X2Y2 Silo";

    IX2Y2FeeSharingSystem public immutable feeSharingSystem;

    uint256 public immutable precisionFactor;

    address public immutable x2y2;

    constructor(IX2Y2FeeSharingSystem _feeSharingSystem) {
        feeSharingSystem = _feeSharingSystem;
        precisionFactor = feeSharingSystem.PRECISION_FACTOR();
        x2y2 = feeSharingSystem.x2y2Token();
    }

    /// @inheritdoc ISilo
    function poke() external override {}

    /// @inheritdoc ISilo
    function deposit(uint256 amount) external override {
        if (amount < precisionFactor) return;
        _approve(x2y2, address(feeSharingSystem), amount);
        feeSharingSystem.deposit(amount, false);
    }

    /// @inheritdoc ISilo
    function withdraw(uint256 amount) external override {
        if (amount == 0) return;
        uint256 shares = 1 + FullMath.mulDiv(amount, 1e18, feeSharingSystem.calculateSharePriceInX2Y2());
        (uint256 maxShares, , ) = feeSharingSystem.userInfo(address(this));
        if (shares > maxShares) shares = maxShares;

        feeSharingSystem.withdraw(shares, true);
    }

    /// @inheritdoc ISilo
    function balanceOf(address account) external view override returns (uint256 balance) {
        return feeSharingSystem.calculateSharesValueInX2Y2(account);
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
