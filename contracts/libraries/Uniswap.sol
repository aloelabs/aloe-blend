// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./LiquidityAmounts.sol";
import "./TickMath.sol";

library Uniswap {
    struct Position {
        // The pool the position is in
        IUniswapV3Pool pool;
        // Lower tick of the position
        int24 lower;
        // Upper tick of the position
        int24 upper;
    }

    /// @dev Do zero-burns to poke the Uniswap pools so earned fees are updated
    function poke(Position memory position) internal {
        if (position.lower == position.upper) return;
        (uint128 liquidity, , , , ) = info(position);
        if (liquidity != 0) {
            position.pool.burn(position.lower, position.upper, 0);
        }
    }

    /// @dev Deposits liquidity in a range on the Uniswap pool.
    function deposit(Position memory position, uint128 liquidity) internal returns (uint256 amount0, uint256 amount1) {
        if (liquidity != 0) {
            (amount0, amount1) = position.pool.mint(address(this), position.lower, position.upper, liquidity, "");
        }
    }

    /// @dev Withdraws all liquidity and collects all fees
    function withdraw(Position memory position, uint128 liquidity)
        internal
        returns (
            uint256 burned0,
            uint256 burned1,
            uint256 earned0,
            uint256 earned1
        )
    {
        if (liquidity != 0) {
            (burned0, burned1) = position.pool.burn(position.lower, position.upper, liquidity);
        }

        // Collect all owed tokens including earned fees
        (uint256 collected0, uint256 collected1) = position.pool.collect(
            address(this),
            position.lower,
            position.upper,
            type(uint128).max,
            type(uint128).max
        );

        unchecked {
            earned0 = collected0 - burned0;
            earned1 = collected1 - burned1;
        }
    }

    /**
     * @notice Amounts of TOKEN0 and TOKEN1 held in vault's position. Includes
     * owed fees, except those accrued since last poke.
     */
    function collectableAmountsAsOfLastPoke(Position memory position, uint160 sqrtPriceX96)
        internal
        view
        returns (
            uint256,
            uint256,
            uint128
        )
    {
        if (position.lower == position.upper) return (0, 0, 0);

        (uint128 liquidity, , , uint128 earnable0, uint128 earnable1) = info(position);
        (uint256 burnable0, uint256 burnable1) = amountsForLiquidity(position, sqrtPriceX96, liquidity);

        return (burnable0 + earnable0, burnable1 + earnable1, liquidity);
    }

    /// @dev Wrapper around `IUniswapV3Pool.positions()`.
    function info(Position memory position)
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
        return position.pool.positions(keccak256(abi.encodePacked(address(this), position.lower, position.upper)));
    }

    /// @dev Wrapper around `LiquidityAmounts.getAmountsForLiquidity()`.
    function amountsForLiquidity(
        Position memory position,
        uint160 sqrtPriceX96,
        uint128 liquidity
    ) internal pure returns (uint256, uint256) {
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                liquidity
            );
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmounts()`.
    function liquidityForAmounts(
        Position memory position,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                amount0,
                amount1
            );
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmount0()`.
    function liquidityForAmount0(Position memory position, uint256 amount0) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                amount0
            );
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmount1()`.
    function liquidityForAmount1(Position memory position, uint256 amount1) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                amount1
            );
    }
}
