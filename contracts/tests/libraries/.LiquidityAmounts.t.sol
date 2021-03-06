// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "ds-test/test.sol";

import "contracts/libraries/TickMath.sol";
import "contracts/libraries/LiquidityAmounts.sol";

contract LiquidityAmountsTest is DSTest {
    function setUp() public {}

    function test_spec_getAmountsForLiquidity() public {
        uint160 current = 79226859512860901259714;
        uint160 lower = TickMath.getSqrtRatioAtTick(-290188);
        uint160 upper = TickMath.getSqrtRatioAtTick(-262460);
        uint128 liquidity = 998992023844159;

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(current, lower, upper, liquidity);
        assertEq(amount0, 499522173722583583538);
        assertEq(amount1, 499487993);
    }

    function test_getAmountsForLiquidity(
        uint160 sqrtPrice,
        uint160 sqrtLower,
        uint160 sqrtUpper,
        uint128 liquidity
    ) public {
        sqrtPrice = TickMath.MIN_SQRT_RATIO + (sqrtPrice % (TickMath.MAX_SQRT_RATIO - TickMath.MIN_SQRT_RATIO));
        sqrtLower = TickMath.MIN_SQRT_RATIO + (sqrtLower % (TickMath.MAX_SQRT_RATIO - TickMath.MIN_SQRT_RATIO));
        sqrtUpper = TickMath.MIN_SQRT_RATIO + (sqrtUpper % (TickMath.MAX_SQRT_RATIO - TickMath.MIN_SQRT_RATIO));

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPrice,
            sqrtLower,
            sqrtUpper,
            liquidity
        );
        assertLe(amount0, type(uint224).max);
        assertLe(amount1, type(uint192).max);
    }
}
