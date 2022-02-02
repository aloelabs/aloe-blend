// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "contracts/libraries/FullMath.sol";
import "contracts/interfaces/ISilo.sol";

interface IYearnVault {
    /// @notice The vault's name. ex: UNI yVault
    function name() external view returns (string memory);

    /// @notice The number of decimals on the yToken
    function decimals() external view returns (uint256);

    /// @notice The address of the underlying token
    function token() external view returns (address);

    /// @notice Similar to Compound's `exchangeRateStored()`, but scaled by `10 ** decimals()` instead of `10 ** 18`
    function pricePerShare() external view returns (uint256);

    /// @notice A standard ERC20 balance getter
    function balanceOf(address user) external view returns (uint256 shares);

    /// @notice The maximum `amount` of underlying that can be deposited
    function availableDepositLimit() external view returns (uint256 amount);

    /// @notice The maximum number of `shares` that can be withdrawn atomically
    function maxAvailableShares() external view returns (uint256 shares);

    /// @notice Deposits `amount` of underlying to the vault
    function deposit(uint256 amount) external returns (uint256 shares);

    /// @notice Burns up to `maxShares` shares and gives `amount` of underlying
    function withdraw(uint256 maxShares, address recipient, uint256 maxLoss) external returns (uint256 amount);
}

contract YearnSilo is ISilo {
    /// @inheritdoc ISilo
    string public name;

    IYearnVault public immutable vault;

    uint256 public immutable maxYearnWithdrawLoss;

    address public immutable underlying;

    uint256 private immutable decimals;

    constructor(IYearnVault _vault, uint256 _maxYearnWithdrawLoss) {
        vault = _vault;
        maxYearnWithdrawLoss = _maxYearnWithdrawLoss;
        underlying = vault.token();
        decimals = vault.decimals();

        // ex: UNI yVault Silo
        name = string(
            abi.encodePacked(
                vault.name(),
                " Silo"
            )
        );
    }

    /// @inheritdoc ISilo
    function poke() external override {}

    /// @inheritdoc ISilo
    function deposit(uint256 amount) external override {
        if (amount == 0) return;

        // If Yearn deposits are capped, deposit as much as possible and hold the rest in Blend contract
        uint256 maxDepositable = vault.availableDepositLimit();
        if (amount > maxDepositable) amount = maxDepositable;

        _approve(underlying, address(vault), amount);
        vault.deposit(amount);
    }

    /// @inheritdoc ISilo
    function withdraw(uint256 amount) external override {
        if (amount == 0) return;
        
        uint256 shares = FullMath.mulDivRoundingUp(
            amount,
            10_000 * 10 ** decimals,
            vault.pricePerShare() * (10_000 - maxYearnWithdrawLoss)
        );

        require(vault.withdraw(shares, address(this), maxYearnWithdrawLoss) >= amount, "Yearn: withdraw failed");
    }

    /// @inheritdoc ISilo
    function balanceOf(address account) external view override returns (uint256 balance) {
        uint256 shares = vault.balanceOf(account);
        uint256 maxWithdrawable = vault.maxAvailableShares();
        // If Blend isn't able to atomically withdraw shares, it doesn't *really* own them
        if (shares > maxWithdrawable) shares = maxWithdrawable;

        balance = FullMath.mulDiv(
            shares,
            vault.pricePerShare() * (10_000 - maxYearnWithdrawLoss),
            10_000 * 10 ** decimals
        );
    }

    /// @inheritdoc ISilo
    function shouldAllowRemovalOf(address token) external view override returns (bool shouldAllow) {
        shouldAllow = token != address(vault);
    }

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
