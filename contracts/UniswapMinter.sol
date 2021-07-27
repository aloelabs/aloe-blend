// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./libraries/LiquidityAmounts.sol";
import "./libraries/TickMath.sol";

import "./structs/Ticks.sol";

contract UniswapMinter is IUniswapV3MintCallback {
    using SafeERC20 for IERC20;

    IUniswapV3Pool public immutable UNI_POOL;

    uint24 public immutable UNI_FEE;

    int24 public immutable TICK_SPACING;

    IERC20 public immutable TOKEN0;

    IERC20 public immutable TOKEN1;

    uint256 internal lastMintedAmount0;

    uint256 internal lastMintedAmount1;

    constructor(IUniswapV3Pool uniPool) {
        UNI_POOL = uniPool;
        UNI_FEE = uniPool.fee();
        TICK_SPACING = uniPool.tickSpacing();
        TOKEN0 = IERC20(uniPool.token0());
        TOKEN1 = IERC20(uniPool.token1());
    }

    /// @dev Do zero-burns to poke the Uniswap pools so earned fees are updated
    function _uniswapPoke(Ticks memory ticks) internal {
        (uint128 liquidity, , , , ) = _position(ticks);
        if (liquidity == 0) return;
        UNI_POOL.burn(ticks.lower, ticks.upper, 0);
    }

    /// @dev Deposits liquidity in a range on the Uniswap pool.
    function _uniswapEnter(Ticks memory ticks, uint128 liquidity) internal {
        if (liquidity == 0) return;
        UNI_POOL.mint(address(this), ticks.lower, ticks.upper, liquidity, "");
    }

    /// @dev Withdraws liquidity from a range and collects all fees in the process.
    function _uniswapExit(Ticks memory ticks, uint128 liquidity)
        internal
        returns (
            uint256 burned0,
            uint256 burned1,
            uint256 earned0,
            uint256 earned1
        )
    {
        if (liquidity != 0) {
            (burned0, burned1) = UNI_POOL.burn(ticks.lower, ticks.upper, liquidity);
        }

        // Collect all owed tokens including earned fees
        (uint256 collected0, uint256 collected1) =
            UNI_POOL.collect(address(this), ticks.lower, ticks.upper, type(uint128).max, type(uint128).max);

        earned0 = collected0 - burned0;
        earned1 = collected1 - burned1;
    }

    /**
     * @notice Amounts of TOKEN0 and TOKEN1 held in vault's position. Includes
     * owed fees, except those accrued since last poke.
     */
    function _collectableAmountsAsOfLastPoke(Ticks memory ticks) public view returns (uint256, uint256) {
        (uint128 liquidity, , , uint128 earnable0, uint128 earnable1) = _position(ticks);
        (uint160 sqrtPriceX96, , , , , , ) = UNI_POOL.slot0();
        (uint256 burnable0, uint256 burnable1) = _amountsForLiquidity(ticks, liquidity, sqrtPriceX96);

        return (burnable0 + earnable0, burnable1 + earnable1);
    }

    /// @dev Wrapper around `IUniswapV3Pool.positions()`.
    function _position(Ticks memory ticks)
        internal
        view
        returns (
            uint128, // liquidity
            uint256, // feeGrowthInside0LastX128
            uint256, // feeGrowthInside1LastX128
            uint128, // tokensOwed0
            uint128 // tokensOwed1
        )
    {
        return UNI_POOL.positions(keccak256(abi.encodePacked(address(this), ticks.lower, ticks.upper)));
    }

    /// @dev Wrapper around `LiquidityAmounts.getAmountsForLiquidity()`.
    function _amountsForLiquidity(Ticks memory ticks, uint128 liquidity, uint160 sqrtPriceX96) internal pure returns (uint256, uint256) {
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(ticks.lower),
                TickMath.getSqrtRatioAtTick(ticks.upper),
                liquidity
            );
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmounts()`.
    function _liquidityForAmounts(
        Ticks memory ticks,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(ticks.lower),
                TickMath.getSqrtRatioAtTick(ticks.upper),
                amount0,
                amount1
            );
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmount0()`.
    function _liquidityForAmount0(Ticks memory ticks, uint256 amount0) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(ticks.lower),
                TickMath.getSqrtRatioAtTick(ticks.upper),
                amount0
            );
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmount1()`.
    function _liquidityForAmount1(Ticks memory ticks, uint256 amount1) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(ticks.lower),
                TickMath.getSqrtRatioAtTick(ticks.upper),
                amount1
            );
    }

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        require(msg.sender == address(UNI_POOL), "Fake callback");
        if (amount0 != 0) TOKEN0.safeTransfer(msg.sender, amount0);
        if (amount1 != 0) TOKEN1.safeTransfer(msg.sender, amount1);

        lastMintedAmount0 = amount0;
        lastMintedAmount1 = amount1;
    }
}
