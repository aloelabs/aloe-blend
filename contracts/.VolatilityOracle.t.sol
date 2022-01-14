// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "ds-test/test.sol";

import "./VolatilityOracle.sol";

interface HEVM {
    function warp(uint256 timestamp) external;
}

contract VolatilityOracleTest is DSTest {
    VolatilityOracle volatilityOracle;
    IUniswapV3Pool pool;
    HEVM hevm;

    function setUp() public {
        volatilityOracle = new VolatilityOracle();
        pool = IUniswapV3Pool(0x3416cF6C708Da44DB2624D63ea0AAef7113527C6);
        hevm = HEVM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    }

    // function invariant_readIndex() public {
    //     assertLt(volatilityOracle.feeGrowthGlobalsReadIndex(address(pool)), 25);
    // }

    // function invariant_writeIndex() public {
    //     assertLt(volatilityOracle.feeGrowthGlobalsWriteIndex(address(pool)), 25);
    // }

    function test_cacheMetadataFor() public {
        volatilityOracle.cacheMetadataFor(pool);
        (uint32 maxSecondsAgo, uint24 gamma0, uint24 gamma1, int24 tickSpacing) = volatilityOracle.cachedPoolMetadata(
            address(pool)
        );

        assertEq(maxSecondsAgo, 118982);
        assertEq(gamma0, 100);
        assertEq(gamma1, 100);
        assertEq(tickSpacing, 1);
    }

    function test_lens_gas() public {
        volatilityOracle.cacheMetadataFor(pool);

        uint256 gas = gasleft();
        volatilityOracle.lens(pool);
        assertEq(gas - gasleft(), 725213);
    }

    function test_estimate24H_gas() public {
        volatilityOracle.cacheMetadataFor(pool);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();

        uint256 gas = gasleft();
        volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);
        assertEq(gas - gasleft(), 132272);
    }

    function test_estimate24H_1() public {
        volatilityOracle.cacheMetadataFor(pool);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        uint256 IV = volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);
        assertEq(IV, 41376993386267);

        (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1, uint256 timestamp) = volatilityOracle.feeGrowthGlobals(
            address(pool),
            1
        );
        assertEq(feeGrowthGlobal0, 785983140346722755185121678846038);
        assertEq(feeGrowthGlobal1, 782243160630302075618982773013645);
        assertEq(timestamp, 1639531906);
    }

    function test_estimate24H_2() public {
        volatilityOracle.cacheMetadataFor(pool);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        uint256 IV1 = volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);
        assertEq(IV1, 41376993386267);

        hevm.warp(block.timestamp + 30 minutes);

        uint256 IV2 = volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);
        assertEq(IV2, 0);

        (, , uint256 timestamp) = volatilityOracle.feeGrowthGlobals(address(pool), 1);
        assertEq(timestamp, 1639531906);
        (, , timestamp) = volatilityOracle.feeGrowthGlobals(address(pool), 2);
        assertEq(timestamp, 0);

        hevm.warp(block.timestamp + 31 minutes);
        assertEq(block.timestamp, 1639535566);

        volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);

        (, , timestamp) = volatilityOracle.feeGrowthGlobals(address(pool), 1);
        assertEq(timestamp, 1639531906);
        (, , timestamp) = volatilityOracle.feeGrowthGlobals(address(pool), 2);
        assertEq(timestamp, 1639535566);
    }

    function test_estimate24H_3() public {
        volatilityOracle.cacheMetadataFor(pool);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();

        uint256 timestamp;
        uint8 readIndex;
        uint8 writeIndex;

        for (uint8 i; i < 28; i++) {
            volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);
            (readIndex, writeIndex) = volatilityOracle.feeGrowthGlobalsIndices(address(pool));

            if (i == 0) assertEq(readIndex, 0);
            else if (i < 25) assertEq(readIndex, 1);
            else assertEq(readIndex, (i + 2) % 25);
            assertEq(writeIndex, (i + 1) % 25);

            (, , timestamp) = volatilityOracle.feeGrowthGlobals(address(pool), writeIndex);
            assertEq(timestamp, block.timestamp);

            if (i >= 24) {
                (, , timestamp) = volatilityOracle.feeGrowthGlobals(address(pool), readIndex);
                assertEq(block.timestamp - timestamp, 24 hours + 24 minutes);
            }

            hevm.warp(block.timestamp + 61 minutes);
        }

        uint256 gas = gasleft();
        volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);
        assertEq(gas - gasleft(), 25215);
    }

    function test_estimate24H_4() public {
        volatilityOracle.cacheMetadataFor(pool);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();

        volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);
        hevm.warp(block.timestamp + 61 minutes);
        volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);
        hevm.warp(block.timestamp + 61 minutes);
        volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);
        hevm.warp(block.timestamp + 24 hours);
        volatilityOracle.estimate24H(pool, sqrtPriceX96, tick);

        (uint8 readIndex, ) = volatilityOracle.feeGrowthGlobalsIndices(address(pool));
        assertEq(readIndex, 3);
    }
}
