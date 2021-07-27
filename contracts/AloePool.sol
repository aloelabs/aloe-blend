// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./libraries/FullMath.sol";
import "./libraries/LiquidityAmounts.sol";
import "./libraries/Math.sol";
import "./libraries/TickMath.sol";

import "./interfaces/IAloePredictions.sol";
import "./interfaces/IAloePredictionsImmutables.sol";

import "./AloePoolERC20.sol";
import "./UniswapMinter.sol";

uint256 constant TWO_144 = 2**144;

struct PDF {
    bool isInverted;
    uint176 mean;
    uint128 sigmaL;
    uint128 sigmaU;
}

contract AloePool is AloePoolERC20, UniswapMinter {
    using SafeERC20 for IERC20;

    event Deposit(address indexed sender, uint256 shares, uint256 amount0, uint256 amount1);

    event Withdraw(address indexed sender, uint256 shares, uint256 amount0, uint256 amount1);

    event Snapshot(int24 tick, uint256 totalAmount0, uint256 totalAmount1, uint256 totalSupply);

    /// @dev The number of standard deviations to +/- from mean when setting position bounds
    uint48 public K = 5;

    /// @dev The number of seconds to look back when computing current price. Makes manipulation harder
    uint32 public constant CURRENT_PRICE_WINDOW = 360;

    /// @dev The predictions market that provides this pool with next-price distribution data
    IAloePredictions public immutable PREDICTIONS;

    /// @dev The most recent predictions market epoch during which this pool was rebalanced
    uint24 public epoch;

    /// @dev The elastic position stretches to accomodate unpredictable price movements
    Ticks public elastic;

    /// @dev The cushion position consumes leftover funds after `elastic` is stretched
    Ticks public cushion;

    /// @dev The excess position is made up of funds that didn't fit into `elastic` when rebalancing
    Ticks public excess;

    /// @dev The current statistics from prediction market (representing a probability density function)
    PDF public pdf;

    /// @dev Whether the pool had excess token0 as of the most recent rebalance
    bool public didHaveExcessToken0;

    /// @dev For reentrancy check
    bool private locked;

    bool public allowRebalances = true;

    modifier lock() {
        require(!locked, "Aloe: Locked");
        locked = true;
        _;
        locked = false;
    }

    constructor(address predictions)
        AloePoolERC20()
        UniswapMinter(IUniswapV3Pool(IAloePredictionsImmutables(predictions).UNI_POOL()))
    {
        PREDICTIONS = IAloePredictions(predictions);
    }

    /**
     * @notice Calculates the vault's total holdings of TOKEN0 and TOKEN1 - in
     * other words, how much of each token the vault would hold if it withdrew
     * all its liquidity from Uniswap.
     */
    function getReserves() public view returns (uint256 reserve0, uint256 reserve1) {
        reserve0 = TOKEN0.balanceOf(address(this));
        reserve1 = TOKEN1.balanceOf(address(this));
        uint256 temp0;
        uint256 temp1;
        (temp0, temp1) = _collectableAmountsAsOfLastPoke(elastic);
        reserve0 += temp0;
        reserve1 += temp1;
        (temp0, temp1) = _collectableAmountsAsOfLastPoke(cushion);
        reserve0 += temp0;
        reserve1 += temp1;
        (temp0, temp1) = _collectableAmountsAsOfLastPoke(excess);
        reserve0 += temp0;
        reserve1 += temp1;
    }

    function getNextElasticTicks() public view returns (Ticks memory) {
        // Define the window over which we want to fetch price
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = CURRENT_PRICE_WINDOW;
        secondsAgos[1] = 0;

        // Fetch price and account for possible inversion
        (int56[] memory tickCumulatives, ) = UNI_POOL.observe(secondsAgos);
        uint176 price =
            TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(CURRENT_PRICE_WINDOW)))
            );
        if (pdf.isInverted) price = type(uint160).max / price;
        price = uint176(FullMath.mulDiv(price, price, TWO_144));

        return _getNextElasticTicks(price, pdf.mean, pdf.sigmaL, pdf.sigmaU, pdf.isInverted);
    }

    function _getNextElasticTicks(
        uint176 price,
        uint176 mean,
        uint128 sigmaL,
        uint128 sigmaU,
        bool areInverted
    ) private view returns (Ticks memory ticks) {
        uint48 n;
        uint176 widthL;
        uint176 widthU;

        if (price < mean) {
            n = uint48((mean - price) / sigmaL);
            widthL = uint176(sigmaL) * uint176(K + n);
            widthU = uint176(sigmaU) * uint176(K);
        } else {
            n = uint48((price - mean) / sigmaU);
            widthL = uint176(sigmaL) * uint176(K);
            widthU = uint176(sigmaU) * uint176(K + n);
        }

        uint176 l = mean > widthL ? mean - widthL : 1;
        uint176 u = mean < type(uint176).max - widthU ? mean + widthU : type(uint176).max;
        uint160 sqrtPriceX96;

        if (areInverted) {
            sqrtPriceX96 = uint160(uint256(type(uint128).max) / Math.sqrt(u << 80));
            ticks.lower = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
            sqrtPriceX96 = uint160(uint256(type(uint128).max) / Math.sqrt(l << 80));
            ticks.upper = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        } else {
            sqrtPriceX96 = uint160(Math.sqrt(l << 80) << 32);
            ticks.lower = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
            sqrtPriceX96 = uint160(Math.sqrt(u << 80) << 32);
            ticks.upper = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        }
    }

    /**
     * @notice Deposits tokens in proportion to the vault's current holdings.
     * @dev These tokens sit in the vault and are not used for liquidity on
     * Uniswap until the next rebalance. Also note it's not necessary to check
     * if user manipulated price to deposit cheaper, as the value of range
     * orders can only by manipulated higher.
     * @dev LOCK MODIFIER IS APPLIED IN AloePoolCapped!!!
     * @param amount0Max Max amount of TOKEN0 to deposit
     * @param amount1Max Max amount of TOKEN1 to deposit
     * @param amount0Min Ensure `amount0` is greater than this
     * @param amount1Min Ensure `amount1` is greater than this
     * @return shares Number of shares minted
     * @return amount0 Amount of TOKEN0 deposited
     * @return amount1 Amount of TOKEN1 deposited
     */
    function deposit(
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 amount0Min,
        uint256 amount1Min
    )
        public
        virtual
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(amount0Max != 0 || amount1Max != 0, "Aloe: 0 deposit");

        _uniswapPoke(elastic);
        _uniswapPoke(cushion);
        _uniswapPoke(excess);

        (shares, amount0, amount1) = _computeLPShares(amount0Max, amount1Max);
        require(shares != 0, "Aloe: 0 shares");
        require(amount0 >= amount0Min, "Aloe: amount0 too low");
        require(amount1 >= amount1Min, "Aloe: amount1 too low");

        // Pull in tokens from sender
        if (amount0 != 0) TOKEN0.safeTransferFrom(msg.sender, address(this), amount0);
        if (amount1 != 0) TOKEN1.safeTransferFrom(msg.sender, address(this), amount1);

        // Mint shares
        _mint(msg.sender, shares);
        emit Deposit(msg.sender, shares, amount0, amount1);
    }

    /// @dev Calculates the largest possible `amount0` and `amount1` such that
    /// they're in the same proportion as total amounts, but not greater than
    /// `amount0Max` and `amount1Max` respectively.
    function _computeLPShares(uint256 amount0Max, uint256 amount1Max)
        internal
        view
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        uint256 totalSupply = totalSupply();
        (uint256 reserve0, uint256 reserve1) = getReserves();

        // If total supply > 0, pool can't be empty
        assert(totalSupply == 0 || reserve0 != 0 || reserve1 != 0);

        if (totalSupply == 0) {
            // For first deposit, just use the amounts desired
            amount0 = amount0Max;
            amount1 = amount1Max;
            shares = amount0 > amount1 ? amount0 : amount1; // max
        } else if (reserve0 == 0) {
            amount1 = amount1Max;
            shares = FullMath.mulDiv(amount1, totalSupply, reserve1);
        } else if (reserve1 == 0) {
            amount0 = amount0Max;
            shares = FullMath.mulDiv(amount0, totalSupply, reserve0);
        } else {
            amount0 = FullMath.mulDiv(amount1Max, reserve0, reserve1);

            if (amount0 < amount0Max) {
                amount1 = amount1Max;
                shares = FullMath.mulDiv(amount1, totalSupply, reserve1);
            } else {
                amount0 = amount0Max;
                amount1 = FullMath.mulDiv(amount0, reserve1, reserve0);
                shares = FullMath.mulDiv(amount0, totalSupply, reserve0);
            }
        }
    }

    /**
     * @notice Withdraws tokens in proportion to the vault's holdings.
     * @param shares Shares burned by sender
     * @param amount0Min Revert if resulting `amount0` is smaller than this
     * @param amount1Min Revert if resulting `amount1` is smaller than this
     * @return amount0 Amount of TOKEN0 sent to recipient
     * @return amount1 Amount of TOKEN1 sent to recipient
     */
    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min
    ) external lock returns (uint256 amount0, uint256 amount1) {
        require(shares != 0, "Aloe: 0 shares");
        uint256 totalSupply = totalSupply() + 1;

        // Calculate token amounts proportional to unused balances
        amount0 = FullMath.mulDiv(TOKEN0.balanceOf(address(this)), shares, totalSupply);
        amount1 = FullMath.mulDiv(TOKEN1.balanceOf(address(this)), shares, totalSupply);

        // Withdraw proportion of liquidity from Uniswap pool
        uint256 temp0;
        uint256 temp1;
        (temp0, temp1) = _uniswapExitFraction(shares, totalSupply, elastic);
        amount0 += temp0;
        amount1 += temp1;
        (temp0, temp1) = _uniswapExitFraction(shares, totalSupply, cushion);
        amount0 += temp0;
        amount1 += temp1;
        (temp0, temp1) = _uniswapExitFraction(shares, totalSupply, excess);
        amount0 += temp0;
        amount1 += temp1;

        // Check constraints
        require(amount0 >= amount0Min, "Aloe: amount0 too low");
        require(amount1 >= amount1Min, "Aloe: amount1 too low");

        // Transfer tokens
        if (amount0 != 0) TOKEN0.safeTransfer(msg.sender, amount0);
        if (amount1 != 0) TOKEN1.safeTransfer(msg.sender, amount1);

        // Burn shares
        _burn(msg.sender, shares);
        emit Withdraw(msg.sender, shares, amount0, amount1);
    }

    /// @dev Withdraws share of liquidity in a range from Uniswap pool. All fee earnings
    /// will be collected and left unused afterwards
    function _uniswapExitFraction(
        uint256 numerator,
        uint256 denominator,
        Ticks memory ticks
    ) internal returns (uint256 amount0, uint256 amount1) {
        assert(numerator < denominator);

        (uint128 liquidity, , , , ) = _position(ticks);
        liquidity = uint128(FullMath.mulDiv(liquidity, numerator, denominator));

        uint256 earned0;
        uint256 earned1;
        (amount0, amount1, earned0, earned1) = _uniswapExit(ticks, liquidity);

        // Add share of fees
        amount0 += FullMath.mulDiv(earned0, numerator, denominator);
        amount1 += FullMath.mulDiv(earned1, numerator, denominator);
    }

    function rebalance() external lock {
        require(allowRebalances, "Disabled");
        uint24 _epoch = PREDICTIONS.epoch();
        require(_epoch > epoch, "Aloe: Too early");

        // Update P.D.F from prediction market
        (pdf.isInverted, pdf.mean, pdf.sigmaL, pdf.sigmaU) = PREDICTIONS.current();
        epoch = _epoch;

        int24 tickSpacing = TICK_SPACING;
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = UNI_POOL.slot0();

        // Exit all current Uniswap positions
        {
            (uint128 liquidityElastic, , , , ) = _position(elastic);
            (uint128 liquidityCushion, , , , ) = _position(cushion);
            (uint128 liquidityExcess, , , , ) = _position(excess);
            _uniswapExit(elastic, liquidityElastic);
            _uniswapExit(cushion, liquidityCushion);
            _uniswapExit(excess, liquidityExcess);
        }

        // Emit snapshot to record balances and supply
        uint256 balance0 = TOKEN0.balanceOf(address(this));
        uint256 balance1 = TOKEN1.balanceOf(address(this));
        emit Snapshot(tick, balance0, balance1, totalSupply());

        // Place elastic order on Uniswap
        Ticks memory elasticNew = _coerceTicksToSpacing(getNextElasticTicks());
        uint128 liquidity = _liquidityForAmounts(elasticNew, sqrtPriceX96, balance0, balance1);
        delete lastMintedAmount0;
        delete lastMintedAmount1;
        _uniswapEnter(elasticNew, liquidity);
        elastic = elasticNew;

        // Place excess order on Uniswap
        Ticks memory active = _coerceTicksToSpacing(Ticks(tick, tick));
        if (lastMintedAmount0 * balance1 < lastMintedAmount1 * balance0) {
            _placeExcessUpper(active, TOKEN0.balanceOf(address(this)), tickSpacing);
            didHaveExcessToken0 = true;
        } else {
            _placeExcessLower(active, TOKEN1.balanceOf(address(this)), tickSpacing);
            didHaveExcessToken0 = false;
        }
    }

    function shouldStretch() external view returns (bool) {
        Ticks memory elasticNew = _coerceTicksToSpacing(getNextElasticTicks());
        return elasticNew.lower != elastic.lower || elasticNew.upper != elastic.upper;
    }

    function stretch() external lock {
        require(allowRebalances, "Disabled");
        int24 tickSpacing = TICK_SPACING;
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = UNI_POOL.slot0();

        // Check if stretching is necessary
        Ticks memory elasticNew = _coerceTicksToSpacing(getNextElasticTicks());
        require(elasticNew.lower != elastic.lower || elasticNew.upper != elastic.upper, "Aloe: Already stretched");

        // Exit previous elastic and cushion, and place as much value as possible in new elastic
        (uint256 elastic0, uint256 elastic1, , , uint256 available0, uint256 available1) =
            _exit2Enter1(sqrtPriceX96, elastic, cushion, elasticNew);
        elastic = elasticNew;

        // Place new cushion
        Ticks memory active = _coerceTicksToSpacing(Ticks(tick, tick));
        if (lastMintedAmount0 * elastic1 < lastMintedAmount1 * elastic0) {
            _placeCushionUpper(active, available0, tickSpacing);
        } else {
            _placeCushionLower(active, available1, tickSpacing);
        }
    }

    function snipe() external lock {
        require(allowRebalances, "Disabled");
        int24 tickSpacing = TICK_SPACING;
        (uint160 sqrtPriceX96, int24 tick, , , , uint8 feeProtocol, ) = UNI_POOL.slot0();

        (
            uint256 excess0,
            uint256 excess1,
            uint256 maxReward0,
            uint256 maxReward1,
            uint256 available0,
            uint256 available1
        ) = _exit2Enter1(sqrtPriceX96, excess, cushion, elastic);

        Ticks memory active = _coerceTicksToSpacing(Ticks(tick, tick));
        uint128 reward = UNI_FEE;

        if (didHaveExcessToken0) {
            // Reward caller
            if (feeProtocol >> 4 != 0) reward -= UNI_FEE / (feeProtocol >> 4);
            reward = (uint128(excess1) * reward) / 1e6;
            assert(reward <= maxReward1);
            if (reward != 0) TOKEN1.safeTransfer(msg.sender, reward);

            // Replace excess and cushion positions
            if (excess0 >= available0) {
                // We converted so much token0 to token1 that the cushion has to go
                // on the other side now
                _placeExcessUpper(active, available0, tickSpacing);
                _placeCushionLower(active, available1, tickSpacing);
            } else {
                // Both excess and cushion still have token0 to eat through
                _placeExcessUpper(active, excess0, tickSpacing);
                _placeCushionUpper(active, available0 - excess0, tickSpacing);
            }
        } else {
            // Reward caller
            if (feeProtocol % 16 != 0) reward -= UNI_FEE / (feeProtocol % 16);
            reward = (uint128(excess0) * reward) / 1e6;
            assert(reward <= maxReward0);
            if (reward != 0) TOKEN0.safeTransfer(msg.sender, reward);

            // Replace excess and cushion positions
            if (excess1 >= available1) {
                // We converted so much token1 to token0 that the cushion has to go
                // on the other side now
                _placeExcessLower(active, available1, tickSpacing);
                _placeCushionUpper(active, available0, tickSpacing);
            } else {
                // Both excess and cushion still have token1 to eat through
                _placeExcessLower(active, excess1, tickSpacing);
                _placeCushionLower(active, available1 - excess1, tickSpacing);
            }
        }
    }

    /// @dev Exits positions a and b, and moves as much value as possible to position c.
    /// Position a must have non-zero liquidity.
    function _exit2Enter1(
        uint160 sqrtPriceX96,
        Ticks memory a,
        Ticks memory b,
        Ticks memory c
    )
        private
        returns (
            uint256 a0,
            uint256 a1,
            uint256 aEarned0,
            uint256 aEarned1,
            uint256 available0,
            uint256 available1
        )
    {
        // Exit position A
        (uint128 liquidity, , , , ) = _position(a);
        require(liquidity != 0, "Aloe: Expected liquidity");
        (a0, a1, aEarned0, aEarned1) = _uniswapExit(a, liquidity);

        // Exit position B if it exists
        uint256 b0;
        uint256 b1;
        (liquidity, , , , ) = _position(b);
        if (liquidity != 0) {
            (b0, b1, , ) = _uniswapExit(b, liquidity);
        }

        // Add to position c
        available0 = a0 + b0;
        available1 = a1 + b1;
        liquidity = _liquidityForAmounts(c, sqrtPriceX96, available0, available1);
        delete lastMintedAmount0;
        delete lastMintedAmount1;
        _uniswapEnter(c, liquidity);

        unchecked {
            available0 = available0 > lastMintedAmount0 ? available0 - lastMintedAmount0 : 0;
            available1 = available1 > lastMintedAmount1 ? available1 - lastMintedAmount1 : 0;
        }
    }

    function _placeCushionLower(
        Ticks memory active,
        uint256 balance1,
        int24 tickSpacing
    ) private {
        Ticks memory _cushion;
        (_cushion.lower, _cushion.upper) = (elastic.lower, active.lower);
        if (_cushion.lower == _cushion.upper) _cushion.lower -= tickSpacing;
        _uniswapEnter(_cushion, _liquidityForAmount1(_cushion, balance1));
        cushion = _cushion;
    }

    function _placeCushionUpper(
        Ticks memory active,
        uint256 balance0,
        int24 tickSpacing
    ) private {
        Ticks memory _cushion;
        (_cushion.lower, _cushion.upper) = (active.upper, elastic.upper);
        if (_cushion.lower == _cushion.upper) _cushion.upper += tickSpacing;
        _uniswapEnter(_cushion, _liquidityForAmount0(_cushion, balance0));
        cushion = _cushion;
    }

    function _placeExcessLower(
        Ticks memory active,
        uint256 balance1,
        int24 tickSpacing
    ) private {
        Ticks memory _excess;
        (_excess.lower, _excess.upper) = (active.lower - tickSpacing, active.lower);
        _uniswapEnter(_excess, _liquidityForAmount1(_excess, balance1));
        excess = _excess;
    }

    function _placeExcessUpper(
        Ticks memory active,
        uint256 balance0,
        int24 tickSpacing
    ) private {
        Ticks memory _excess;
        (_excess.lower, _excess.upper) = (active.upper, active.upper + tickSpacing);
        _uniswapEnter(_excess, _liquidityForAmount0(_excess, balance0));
        excess = _excess;
    }

    function _coerceTicksToSpacing(Ticks memory ticks) private view returns (Ticks memory ticksCoerced) {
        ticksCoerced.lower =
            ticks.lower -
            (ticks.lower < 0 ? TICK_SPACING + (ticks.lower % TICK_SPACING) : ticks.lower % TICK_SPACING);
        ticksCoerced.upper =
            ticks.upper +
            (ticks.upper < 0 ? -ticks.upper % TICK_SPACING : TICK_SPACING - (ticks.upper % TICK_SPACING));
        assert(ticksCoerced.lower <= ticks.lower);
        assert(ticksCoerced.upper >= ticks.upper);
    }
}
