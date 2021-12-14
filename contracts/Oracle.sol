// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "./libraries/FullMath.sol";
import "./libraries/Math.sol";
import "./libraries/TickMath.sol";
import "./libraries/OracleLibrary.sol";
import "./libraries/Uniswap.sol";

contract Oracle {
    using Uniswap for Uniswap.Position;

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    struct PoolMetadata {
        uint32 oldestObservation;
        uint24 gamma0;
        uint24 gamma1;
        int24 tickSpacing;
    }

    struct PoolData {
        // the current price (from pool.slot0())
        uint160 sqrtPriceX96;
        // the current tick (from pool.slot0())
        int24 currentTick;
        // the mean tick over some period (from OracleLibrary.consult(...))
        int24 arithmeticMeanTick;
        // the mean liquidity over some period (from OracleLibrary.consult(...))
        uint128 harmonicMeanLiquidity;
        // the active liquidity (from pool.liquidity())
        uint128 poolLiquidity;
    }

    mapping(address => PoolMetadata) public cachedPoolMetadata;

    function cacheMetadataFor(IUniswapV3Pool _pool) external {
        PoolMetadata memory poolMetadata;

        (, , uint16 observationIndex, uint16 observationCardinality, , uint8 feeProtocol, ) = _pool.slot0();
        poolMetadata.oldestObservation = OracleLibrary.getOldestObservation(
            _pool,
            observationIndex,
            observationCardinality
        );

        uint24 fee = _pool.fee();
        poolMetadata.gamma0 = fee;
        poolMetadata.gamma1 = fee;
        if (feeProtocol % 16 != 0) poolMetadata.gamma0 -= fee / (feeProtocol % 16);
        if (feeProtocol >> 4 != 0) poolMetadata.gamma1 -= fee / (feeProtocol >> 4);

        poolMetadata.tickSpacing = _pool.tickSpacing();

        cachedPoolMetadata[address(_pool)] = poolMetadata;
    }

    /// MARK: View functions ⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇

    function estimateIV(
        IUniswapV3Pool _pool,
        Slot0 memory _slot0,
        // These come from pool.positions(key):
        uint128 _positionLiquidity,
        uint128 _tokensOwed0,
        uint128 _tokensOwed1,
        // Caller should keep track of this themselves:
        uint32 _ageOfPositionRevenue
    ) external view returns (uint256) {
        PoolMetadata memory poolMetadata = cachedPoolMetadata[address(_pool)];

        uint32 secondsAgo = poolMetadata.oldestObservation;
        if (secondsAgo > 1 days) secondsAgo = 1 days;
        // Throws if secondsAgo == 0
        (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity) = OracleLibrary.consult(_pool, secondsAgo);

        return
            _estimateIV(
                poolMetadata,
                PoolData(
                    _slot0.sqrtPriceX96,
                    _slot0.tick,
                    arithmeticMeanTick,
                    harmonicMeanLiquidity,
                    _pool.liquidity()
                ),
                _positionLiquidity,
                _tokensOwed0,
                _tokensOwed1,
                _ageOfPositionRevenue
            );
    }

    /// MARK: Pure functions ⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇︎⬇

    function _estimateIV(
        PoolMetadata memory _metadata,
        PoolData memory _data,
        // These come from pool.positions(...):
        uint128 _positionLiquidity,
        uint128 _tokensOwed0,
        uint128 _tokensOwed1,
        // Caller should keep track of this themselves:
        uint32 _ageOfPositionRevenue
    ) internal pure returns (uint256) {
        if (_data.poolLiquidity == 0 || _positionLiquidity == 0) return 0;

        uint128 sqrtPoolRevenue = _computeSqrtPoolRevenue(
            _computePositionRevenueXGamma(
                _data.arithmeticMeanTick,
                _metadata.gamma0,
                _metadata.gamma1,
                _tokensOwed0,
                _tokensOwed1
            ),
            _data.harmonicMeanLiquidity,
            _positionLiquidity
        );
        uint128 sqrtTickTVLX32 = uint128(
            Math.sqrt(
                uint256(
                    _computeTickTVL(_data.currentTick, _metadata.tickSpacing, _data.sqrtPriceX96, _data.poolLiquidity)
                ) << 64
            )
        );
        uint48 timeAdjustmentX32 = uint48(Math.sqrt((uint256(1 days) << 64) / _ageOfPositionRevenue));

        if (sqrtTickTVLX32 == 0) return 0;
        return (uint256(20_000) * timeAdjustmentX32 * sqrtPoolRevenue) / sqrtTickTVLX32;
    }

    function _computePositionRevenueXGamma(
        int24 _arithmeticMeanTick,
        uint24 _gamma0,
        uint24 _gamma1,
        uint128 _tokensOwed0,
        uint128 _tokensOwed1
    ) internal pure returns (uint256 positionRevenue) {
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_arithmeticMeanTick);
        uint224 geometricMeanPrice = uint224(FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96));

        // Doesn't overflow because swap fees must be <<< 100%
        unchecked {
            _tokensOwed0 = uint128((uint256(_tokensOwed0) * _gamma1) / 1e6);
            _tokensOwed1 = uint128((uint256(_tokensOwed1) * _gamma0) / 1e6);
        }

        // This is an approximation. Ideally the fees earned during each swap would be multiplied by the price
        // *at that swap*, but that's not possible here. But for prices simulated with GBM and swap sizes
        // either normally or uniformly distributed, the error you get from using geometric mean price is
        // <1% even with high drift and volatility.
        positionRevenue = FullMath.mulDiv(_tokensOwed0, geometricMeanPrice, FixedPoint96.Q96) + _tokensOwed1;
    }

    /// @dev assumes _positionLiquidity != 0
    function _computeSqrtPoolRevenue(
        uint256 _positionRevenue,
        uint128 _positionLiquidity,
        uint128 _harmonicMeanLiquidity
    ) internal pure returns (uint128 sqrtPoolRevenue) {
        // Apply heuristic: Since `_tokensOwed1` fits in a uint128 and `positionRevenue` has the same units
        // (it's expressed in token1), we constrain this to be < type(uint128).max
        if (_positionRevenue > type(uint128).max) _positionRevenue = type(uint128).max;
        unchecked {
            sqrtPoolRevenue = uint128(Math.sqrt((_positionRevenue * _harmonicMeanLiquidity) / _positionLiquidity));
        }
    }

    function _computeTickTVL(
        int24 _currentTick,
        int24 _tickSpacing,
        uint160 _sqrtPriceX96,
        uint128 _poolLiquidity
    ) internal pure returns (uint192 tickTVL) {
        Uniswap.Position memory current;
        int24 mod = _currentTick % _tickSpacing;

        if (_currentTick < 0) current.lower = _currentTick + mod;
        else current.lower = _currentTick - mod;
        current.upper = current.lower + _tickSpacing;

        tickTVL = current.valueOfLiquidity(_sqrtPriceX96, _poolLiquidity);
    }
}
