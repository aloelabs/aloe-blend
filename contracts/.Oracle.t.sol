// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "ds-test/test.sol";

import "./Oracle.sol";

contract OracleExposed is Oracle {
    function exposed_estimateIV(
        PoolMetadata memory _metadata,
        PoolData memory _data,
        uint128 _positionLiquidity,
        uint128 _tokensOwed0,
        uint128 _tokensOwed1,
        uint32 _ageOfPositionRevenue
    ) external pure returns (uint256) {
        return _estimateIV(_metadata, _data, _positionLiquidity, _tokensOwed0, _tokensOwed1, _ageOfPositionRevenue);
    }

    function exposed_computeGammaTPositionRevenue(
        int24 _arithmeticMeanTick,
        uint24 _gamma0,
        uint24 _gamma1,
        uint128 _tokensOwed0,
        uint128 _tokensOwed1
    ) external pure returns (uint256 positionRevenue) {
        return _computeGammaTPositionRevenue(_arithmeticMeanTick, _gamma0, _gamma1, _tokensOwed0, _tokensOwed1);
    }

    function exposed_computeSqrtPoolRevenue(
        uint256 _positionRevenue,
        uint128 _positionLiquidity,
        uint128 _harmonicMeanLiquidity
    ) external pure returns (uint128 sqrtPoolRevenue) {
        return _computeSqrtPoolRevenue(_positionRevenue, _positionLiquidity, _harmonicMeanLiquidity);
    }

    function exposed_computeTickTVL(
        int24 _currentTick,
        int24 _tickSpacing,
        uint160 _sqrtPriceX96,
        uint128 _poolLiquidity
    ) external pure returns (uint192 tickTVL) {
        return _computeTickTVL(_currentTick, _tickSpacing, _sqrtPriceX96, _poolLiquidity);
    }
}

contract OracleTest is DSTest {
    OracleExposed oracleExposed;

    function setUp() public {
        oracleExposed = new OracleExposed();
    }

    function test_cacheMetadataFor() public {
        IUniswapV3Pool pool = IUniswapV3Pool(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);

        (uint32 oldestObservation, uint24 gamma0, uint24 gamma1, int24 tickSpacing) = oracleExposed.cachedPoolMetadata(
            address(pool)
        );
        assertEq(oldestObservation, 0);
        assertEq(gamma0, 0);
        assertEq(gamma1, 0);
        assertEq(tickSpacing, 0);

        oracleExposed.cacheMetadataFor(pool);
        (oldestObservation, gamma0, gamma1, tickSpacing) = oracleExposed.cachedPoolMetadata(address(pool));
        assertEq(oldestObservation, 356414);
        assertEq(gamma0, 3000);
        assertEq(gamma1, 3000);
        assertEq(tickSpacing, 60);
    }

    function test_view_estimateIV() public {
        IUniswapV3Pool pool = IUniswapV3Pool(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);
        oracleExposed.cacheMetadataFor(pool);

        uint256 dailyIV = oracleExposed.estimateIV(
            pool,
            IUniswapV3PoolSlot(address(pool)).slot0(),
            347873518912231,
            750000,
            195000000000000,
            77820
        );

        assertEq(dailyIV, 12647682461913853); // 1.265%
    }

    function test_pure_estimateIV1() public {
        Oracle.PoolMetadata memory metadata = Oracle.PoolMetadata(3600, 3000, 3000, 60);
        Oracle.PoolData memory data = Oracle.PoolData(
            1278673744380353403099539498152303, // sqrtPriceX96
            193789, // currentTick
            193730, // arithmeticMeanTick
            19743397700000000000, // harmonicMeanLiquidity
            19685271204911047580 // poolLiquidity
        );
        uint256 dailyIV = oracleExposed.exposed_estimateIV(
            metadata,
            data,
            347873518912231, // positionLiquidity
            750000, // tokensOwed0
            195000000000000, // tokensOwed1
            77820 // ageOfPositionRevenue
        );

        assertEq(dailyIV, 17581497014297400); // 1.758%
    }

    function test_pure_estimateIV2(
        uint128 positionLiquidity,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    ) public {
        Oracle.PoolMetadata memory metadata = Oracle.PoolMetadata(3600, 3000, 3000, 60);
        Oracle.PoolData memory data = Oracle.PoolData(
            1278673744380353403099539498152303, // sqrtPriceX96
            193789, // currentTick
            193730, // arithmeticMeanTick
            19743397700000000000, // harmonicMeanLiquidity
            19685271204911047580 // poolLiquidity
        );
        uint256 dailyIV = oracleExposed.exposed_estimateIV(
            metadata,
            data,
            positionLiquidity,
            tokensOwed0,
            tokensOwed1,
            86400
        );

        if (
            (1_000_000 < positionLiquidity) &&
            (positionLiquidity < data.harmonicMeanLiquidity) &&
            (tokensOwed0 > 1e6 || tokensOwed1 > 1e6)
        ) assertGt(dailyIV, 0);
    }

    function test_pure_computeGammaTPositionRevenue(
        int24 _arithmeticMeanTick,
        uint16 _gamma0,
        uint16 _gamma1,
        uint128 _tokensOwed0,
        uint128 _tokensOwed1
    ) public {
        if (_arithmeticMeanTick < TickMath.MIN_TICK) _arithmeticMeanTick = TickMath.MIN_TICK;
        if (_arithmeticMeanTick > TickMath.MAX_TICK) _arithmeticMeanTick = TickMath.MAX_TICK;

        // Ensure it doesn't revert
        uint256 positionRevenue = oracleExposed.exposed_computeGammaTPositionRevenue(
            _arithmeticMeanTick,
            _gamma0,
            _gamma1,
            _tokensOwed0,
            _tokensOwed1
        );

        // Check that it's non-zero in cases where we don't expect truncation
        int24 lowerBound = TickMath.MIN_TICK / 2;
        int24 upperBound = TickMath.MAX_TICK / 2;
        if (
            (lowerBound < _arithmeticMeanTick && _arithmeticMeanTick < upperBound) &&
            (_tokensOwed0 != 0 || _tokensOwed1 != 0)
        ) assertGt(positionRevenue, 0);
    }

    function test_pure_computeSqrtPoolRevenue(
        uint256 _positionRevenue,
        uint128 _positionLiquidity,
        uint128 _harmonicMeanLiquidity
    ) public {
        if (_positionLiquidity == 0) return;

        uint128 sqrtPoolRevenue = oracleExposed.exposed_computeSqrtPoolRevenue(
            _positionRevenue,
            _positionLiquidity,
            _harmonicMeanLiquidity
        );

        uint256 ratio = (10 * uint256(_harmonicMeanLiquidity)) / _positionLiquidity;
        if (_positionRevenue != 0 && ratio > 1) assertGt(sqrtPoolRevenue, 0);
    }

    function test_pure_computeTickTVL(
        int24 _currentTick,
        uint8 _tickSpacing,
        uint128 _poolLiquidity
    ) public {
        if (_tickSpacing == 0) return; // Always true in the real world
        int24 tickSpacing = int24(uint24(_tickSpacing));

        if (_currentTick < TickMath.MIN_TICK) _currentTick = TickMath.MIN_TICK + tickSpacing;
        if (_currentTick > TickMath.MAX_TICK) _currentTick = TickMath.MAX_TICK - tickSpacing;
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_currentTick);

        // Ensure it doesn't revert
        uint192 tickTVL = oracleExposed.exposed_computeTickTVL(
            _currentTick,
            int24(uint24(tickSpacing)),
            sqrtPriceX96,
            _poolLiquidity
        );

        // Check that it's non-zero in cases where we don't expect truncation
        int24 lowerBound = TickMath.MIN_TICK / 2;
        int24 upperBound = TickMath.MAX_TICK / 2;
        if (_poolLiquidity > 1_000_000 && _currentTick < lowerBound && _currentTick > upperBound) assertGt(tickTVL, 0);
    }
}
