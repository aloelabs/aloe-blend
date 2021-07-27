// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./libraries/LiquidityAmounts.sol";
import "./libraries/TickMath.sol";

import "./interfaces/IAloePredictions.sol";

import "./structs/Ticks.sol";

import "./AloePoolCapped.sol";
import "./IncentiveVault.sol";

interface ICHI {
    function mint(uint256 value) external;

    function freeUpTo(uint256 value) external returns (uint256);
}

contract Helper {
    using SafeERC20 for IERC20;

    address public constant CHI = 0x0000000000004946c0e9F43F4Dee607b0eF1fA1c;

    address public constant ALOE = 0xa10Ee8A7bFA188E762a7bc7169512222a621Fab4;

    address public constant MULTISIG = 0xf63ff43C9155F25E3272F2b092943333C3Db6308;

    AloePoolCapped public constant pool = AloePoolCapped(0xf5F30EaF55Fd9fFc70651b13b791410aAd663846);

    IAloePredictions public constant predictions = IAloePredictions(0x263C5BDFe39c48aDdE8362DC0Ec2BbD770A09c3a);

    IncentiveVault public constant incentives = IncentiveVault(0xec0c69449dBc79CB3483FC3e3A4285C8A2D3dD45);

    modifier discountCHI {
        uint256 gasStart = gasleft();
        _;
        uint256 gasSpent = 21000 + gasStart - gasleft() + 16 * msg.data.length;
        ICHI(CHI).freeUpTo((gasSpent + 14154) / 41947);
    }

    /// @notice Whether advance() should be called on the predictions market
    /// @dev Doesn't check whether any proposals have actually been submitted in this epoch
    function shouldAdvance() public view returns (bool) {
        return uint32(block.timestamp) > predictions.epochExpectedEndTime();
    }

    /// @notice Whether rebalance() should be called on the pool
    function shouldRebalance() public view returns (bool) {
        return predictions.epoch() > pool.epoch();
    }

    /// @notice Whether stretch() should be called on the pool
    function shouldStretch() public view returns (bool) {
        return pool.shouldStretch();
    }

    /// @notice Whether snipe() should be called on the pool
    function wouldSnipeHaveImpact() public view returns (bool) {
        IUniswapV3Pool uniPool = pool.UNI_POOL();
        int24 tickSpacing = uniPool.tickSpacing();
        (, int24 tick, , , , , ) = uniPool.slot0();
        (int24 lower, int24 upper) = pool.excess();

        if (pool.didHaveExcessToken0()) {
            return tick < upper || tick - upper > tickSpacing;
        } else {
            return tick > lower || lower - tick > tickSpacing;
        }
    }

    /// @notice The swap fees that will be sent to caller if they call snipe
    function computeSnipeReward() public view returns (uint256 reward0, uint256 reward1) {
        IUniswapV3Pool uniPool = pool.UNI_POOL();
        (uint160 sqrtPriceX96, , , , , uint8 feeProtocol, ) = uniPool.slot0();

        (int24 lower, int24 upper) = pool.excess();
        (uint128 liquidity, , , , ) = uniPool.positions(keccak256(abi.encodePacked(address(pool), lower, upper)));
        (uint256 amount0, uint256 amount1) =
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(lower),
                TickMath.getSqrtRatioAtTick(upper),
                liquidity
            );

        if (pool.didHaveExcessToken0()) {
            if (feeProtocol >> 4 != 0) reward1 -= uniPool.fee() / (feeProtocol >> 4);
            reward1 = (uint128(amount1) * reward1) / 1e6;
        } else {
            if (feeProtocol % 16 != 0) reward0 -= uniPool.fee() / (feeProtocol % 16);
            reward0 = (uint128(amount0) * reward0) / 1e6;
        }
    }

    function go() external discountCHI {
        if (shouldAdvance()) {
            try predictions.advance() {
                IERC20(ALOE).transfer(msg.sender, IERC20(ALOE).balanceOf(address(this)));
                return;
            } catch {}
        }

        if (shouldRebalance()) {
            pool.rebalance();
        } else if (shouldStretch()) {
            pool.stretch();
        } else {
            pool.snipe();
        }

        incentives.claimAdvanceIncentive(ALOE, msg.sender);
    }

    function sweep(IERC20 token, uint256 amount) external {
        token.safeTransfer(MULTISIG, amount);
    }
}
