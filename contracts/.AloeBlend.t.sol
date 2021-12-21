// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "ds-test/test.sol";

import "./AloeBlend.sol";

contract AloeBlendFake is AloeBlend {
    constructor(
        IUniswapV3Pool _uniPool,
        ISilo _silo0,
        ISilo _silo1
    ) AloeBlend(_uniPool, _silo0, _silo1) {}

    function computeNextPositionWidth(uint256 IV) external pure returns (uint24 width) {
        width = _computeNextPositionWidth(IV);
    }
}

contract AloeBlendTest is DSTest {
    AloeBlendFake blend;

    function setUp() public {
        blend = new AloeBlendFake(
            IUniswapV3Pool(0xF1B63cD9d80f922514c04b0fD0a30373316dd75b),
            ISilo(0x8E35ec3f2C8e14bf7A0E67eA6667F6965938aD2d),
            ISilo(0x908f6DF3df3c25365172F350670d055541Ec362E)
        );
    }

    function test_computeNextPositionWidth(uint256 IV) public {
        uint24 width = blend.computeNextPositionWidth(IV);

        assertGe(width, blend.MIN_WIDTH());
        assertLe(width, blend.MAX_WIDTH());
    }

    function test_spec_computeNextPositionWidth() public {
        assertEq(blend.computeNextPositionWidth(5e15), 201);
        assertEq(blend.computeNextPositionWidth(1e17), 4054);
        assertEq(blend.computeNextPositionWidth(2e17), 8473);
        assertEq(blend.computeNextPositionWidth(4e17), 13864);
    }
}
