// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "ds-test/test.sol";

import "contracts/AloeBlend.sol";

contract AloeBlendFake is AloeBlend {
    constructor(
        IUniswapV3Pool _uniPool,
        ISilo _silo0,
        ISilo _silo1
    ) AloeBlend(_uniPool, _silo0, _silo1) {}

    function computeNextPositionWidth(uint256 IV) external pure returns (uint24 width) {
        width = _computeNextPositionWidth(IV);
    }

    function computeMagicAmounts(
        uint256 inventory0,
        uint256 inventory1,
        uint24 halfWidth
    )
        external
        pure
        returns (
            uint96,
            uint256,
            uint256
        )
    {
        return _computeMagicAmounts(inventory0, inventory1, halfWidth);
    }

    function computeLPShares(
        uint256 _totalSupply,
        uint256 _inventory0,
        uint256 _inventory1,
        uint256 _amount0Max,
        uint256 _amount1Max,
        uint160 _sqrtPriceX96
    )
        external
        pure
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        return _computeLPShares(_totalSupply, _inventory0, _inventory1, _amount0Max, _amount1Max, _sqrtPriceX96);
    }
}

contract VolatilityOracleFake {
    function cachedPoolMetadata(address)
        external
        pure
        returns (
            uint32,
            uint24,
            uint24,
            int24
        )
    {
        return (1 hours, 0, 0, 0);
    }

    function estimate24H(
        IUniswapV3Pool,
        uint160,
        int24
    ) external pure returns (uint256 IV) {
        return 2e18;
    }
}

contract FactoryFake {
    IVolatilityOracle public immutable VOLATILITY_ORACLE;

    constructor(IVolatilityOracle _volatilityOracle) {
        VOLATILITY_ORACLE = _volatilityOracle;
    }

    function create(
        IUniswapV3Pool _uniPool,
        ISilo _silo0,
        ISilo _silo1
    ) external returns (AloeBlendFake) {
        return new AloeBlendFake(_uniPool, _silo0, _silo1);
    }
}

// TODO test that primary.liquidity and limit.liquidity are equal to pool.info(...) number

contract AloeBlendTest is DSTest {
    AloeBlendFake blend;

    function setUp() public {
        IVolatilityOracle oracle = IVolatilityOracle(address(new VolatilityOracleFake()));
        FactoryFake factory = new FactoryFake(oracle);
        blend = factory.create(
            IUniswapV3Pool(0xF1B63cD9d80f922514c04b0fD0a30373316dd75b),
            ISilo(0x8E35ec3f2C8e14bf7A0E67eA6667F6965938aD2d),
            ISilo(0x908f6DF3df3c25365172F350670d055541Ec362E)
        );
    }

    function test_spec_computeRebalanceUrgency() public {
        // TODO
    }

    function test_computeNextPositionWidth(uint256 IV) public {
        uint24 width = blend.computeNextPositionWidth(IV);

        assertGe(width, blend.MIN_WIDTH());
        assertLe(width, blend.MAX_WIDTH());
    }

    function test_spec_computeNextPositionWidth() public {
        assertEq(blend.computeNextPositionWidth(1e16), 402);
        assertEq(blend.computeNextPositionWidth(2e16), 800);
        assertEq(blend.computeNextPositionWidth(1e17), 4054);
        assertEq(blend.computeNextPositionWidth(2e17), 8473);
        assertEq(blend.computeNextPositionWidth(3e17), 13863);
        assertEq(blend.computeNextPositionWidth(4e17), 21973);
        assertEq(blend.computeNextPositionWidth(5e17), 27728);
    }

    function test_computeMagicAmounts(
        uint256 inventory0,
        uint256 inventory1,
        uint24 halfWidth
    ) public {
        if (halfWidth < blend.MIN_WIDTH() / 2) return;
        if (halfWidth > blend.MAX_WIDTH() / 2) return;

        (uint96 magic, uint256 amount0, uint256 amount1) = blend.computeMagicAmounts(
            inventory0,
            inventory1,
            halfWidth
        );

        assertLt(amount0, inventory0);
        assertLt(amount1, inventory1);
        assertLt(magic, 2**96);
    }

    function test_spec_computeMagicAmounts() public {
        uint256 amount0;
        uint256 amount1;
        uint96 magic;

        (magic, amount0, amount1) = blend.computeMagicAmounts(0, 0, blend.MIN_WIDTH() / 2);
        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(magic, 792215870747104703836069196);

        (magic, amount0, amount1) = blend.computeMagicAmounts(1111111, 2222222, blend.MAX_WIDTH() / 2);
        assertEq(amount0, 555565);
        assertEq(amount1, 1111131);
        assertEq(magic, 39614800711660855234216192339);
    }

    function test_computeLPShares(
        uint128 _totalSupplyDiff,
        uint256 _inventory0,
        uint256 _inventory1,
        uint256 _amount0Max,
        uint256 _amount1Max,
        uint160 _sqrtPriceX96
    ) public {
        if (_inventory0 > type(uint256).max - _inventory1) return;
        if (_totalSupplyDiff > _inventory0 + _inventory1) return;

        uint256 _totalSupply = _inventory0 + _inventory1 - _totalSupplyDiff;
        if (_amount0Max > type(uint256).max / _totalSupply || _amount1Max > type(uint256).max / _totalSupply) return;

        (uint256 shares, uint256 amount0, uint256 amount1) = blend.computeLPShares(
            _totalSupply,
            _inventory0,
            _inventory1,
            _amount0Max,
            _amount1Max,
            _sqrtPriceX96
        );

        assertLe(amount0, _amount0Max);
        assertLe(amount1, _amount1Max);

        if (
            _inventory0 > type(uint256).max - amount0 ||
            _inventory1 > type(uint256).max - amount1 ||
            _totalSupply > type(uint256).max - shares
        ) return;

        uint256 reverse0 = FullMath.mulDiv(_inventory0 + amount0, shares, _totalSupply + shares);
        uint256 reverse1 = FullMath.mulDiv(_inventory1 + amount1, shares, _totalSupply + shares);
        assertLe(reverse0, amount0);
        assertLe(reverse1, amount1);
        if (amount0 > 100000) assertGe(reverse0, amount0 - 1);
        if (amount1 > 100000) assertGe(reverse1, amount1 - 1);
    }

    function test_spec_computeLPShares() public {
        uint256 shares;
        uint256 amount0;
        uint256 amount1;

        (shares, amount0, amount1) = blend.computeLPShares(0, 0, 0, 10000000, 20000001, 1.120455419e29);
        assertEq(shares, 10000000);
        assertEq(amount0, 10000000);
        assertEq(amount1, 19999999);
        (shares, amount0, amount1) = blend.computeLPShares(0, 0, 0, 10000001, 20000000, 1.120455419e29);
        assertEq(shares, 20000000);
        assertEq(amount0, 10000000);
        assertEq(amount1, 20000000);
        (shares, amount0, amount1) = blend.computeLPShares(
            20000000,
            10000000,
            20000000,
            20000000,
            40000000,
            1.120455419e29
        );
        assertEq(shares, 40000000);
        assertEq(amount0, 20000000);
        assertEq(amount1, 40000000);
        (shares, amount0, amount1) = blend.computeLPShares(
            60000000,
            30000000,
            60000000,
            20000000,
            40000000,
            1.58456325e29
        );
        assertEq(shares, 40000000);
        assertEq(amount0, 20000000);
        assertEq(amount1, 40000000);
    }
}
