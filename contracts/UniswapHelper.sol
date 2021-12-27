// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract UniswapHelper is IUniswapV3MintCallback {
    using SafeERC20 for IERC20;

    IUniswapV3Pool public immutable UNI_POOL;

    IERC20 public immutable TOKEN0;

    IERC20 public immutable TOKEN1;

    int24 public immutable TICK_SPACING;

    uint256 internal lastMintedAmount0;

    uint256 internal lastMintedAmount1;

    constructor(IUniswapV3Pool _pool) {
        UNI_POOL = _pool;
        TOKEN0 = IERC20(_pool.token0());
        TOKEN1 = IERC20(_pool.token1());
        TICK_SPACING = _pool.tickSpacing();
    }

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3MintCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata
    ) external {
        require(msg.sender == address(UNI_POOL));
        if (_amount0 != 0) TOKEN0.safeTransfer(msg.sender, _amount0);
        if (_amount1 != 0) TOKEN1.safeTransfer(msg.sender, _amount1);

        lastMintedAmount0 = _amount0;
        lastMintedAmount1 = _amount1;
    }
}
