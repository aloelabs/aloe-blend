// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./libraries/Compound.sol";
import "./libraries/FullMath.sol";
import "./libraries/LiquidityAmounts.sol";
import "./libraries/Math.sol";
import "./libraries/TickMath.sol";

import "./AloeBlendERC20.sol";
import "./UniswapMinter.sol";

/*
                                                                                                                        
                                                   #                                                                    
                                                  ###                                                                   
                                                  #####                                                                 
                               #                 #######                                *###*                           
                                ###             #########                         ########                              
                                #####         ###########                   ###########                                 
                                ########    ############               ############                                     
                                 ########    ###########         *##############                                        
                                ###########   ########      #################                                           
                                ############   ###      #################                                               
                                ############       ##################                                                   
                               #############    #################*         *#############*                              
                              ##############    #############      #####################################                
                             ###############   ####******      #######################*                                 
                           ################                                                                             
                         #################   *############################*                                             
                           ##############    ######################################                                     
                               ########    ################*                     **######*                              
                                   ###    ###                                                                           
                                                                                                                        
         ___       ___       ___       ___            ___       ___       ___       ___       ___       ___       ___   
        /\  \     /\__\     /\  \     /\  \          /\  \     /\  \     /\  \     /\  \     /\  \     /\  \     /\__\  
       /::\  \   /:/  /    /::\  \   /::\  \        /::\  \   /::\  \   /::\  \   _\:\  \    \:\  \   /::\  \   /:/  /  
      /::\:\__\ /:/__/    /:/\:\__\ /::\:\__\      /:/\:\__\ /::\:\__\ /::\:\__\ /\/::\__\   /::\__\ /::\:\__\ /:/__/   
      \/\::/  / \:\  \    \:\/:/  / \:\:\/  /      \:\ \/__/ \/\::/  / \/\::/  / \::/\/__/  /:/\/__/ \/\::/  / \:\  \   
        /:/  /   \:\__\    \::/  /   \:\/  /        \:\__\     /:/  /     \/__/   \:\__\    \/__/      /:/  /   \:\__\  
        \/__/     \/__/     \/__/     \/__/          \/__/     \/__/               \/__/               \/__/     \/__/  
*/

uint256 constant TWO_96 = 2**96;
uint256 constant TWO_144 = 2**144;

struct PDF {
    bool isInverted;
    uint176 mean;
    uint128 sigmaL;
    uint128 sigmaU;
}

contract AloeBlend is AloeBlendERC20, UniswapMinter {
    using SafeERC20 for IERC20;

    using Compound for Compound.Market;

    event Deposit(address indexed sender, uint256 shares, uint256 amount0, uint256 amount1);

    event Withdraw(address indexed sender, uint256 shares, uint256 amount0, uint256 amount1);

    event Snapshot(int24 tick, uint256 totalAmount0, uint256 totalAmount1, uint256 totalSupply);

    /// @dev The number of standard deviations to +/- from mean when setting position bounds
    uint8 public K = 20;

    int24 public MIN_WIDTH = 1000; // at minimum, around 2.5% of total inventory will be in Uniswap

    /// @dev The elastic position stretches to accomodate unpredictable price movements
    Ticks public elastic;

    Compound.Market public silo0;

    Compound.Market public silo1;

    /// @dev For reentrancy check
    bool private locked;

    modifier lock() {
        require(!locked, "Aloe: Locked");
        locked = true;
        _;
        locked = false;
    }

    /// @dev Required for Compound library to work
    receive() external payable {
        require(msg.sender == address(WETH) || msg.sender == address(Compound.CETH));
    }

    constructor(address uniPool, address cToken0, address cToken1)
        AloeBlendERC20()
        UniswapMinter(IUniswapV3Pool(uniPool))
    {
        silo0.initialize(cToken0);
        silo1.initialize(cToken1);
    }

    /**
     * @notice Calculates the vault's total holdings of TOKEN0 and TOKEN1 - in
     * other words, how much of each token the vault would hold if it withdrew
     * all its liquidity from Uniswap and Compound.
     */
    function getInventory() public view returns (uint256 inventory0, uint256 inventory1) {
        // Everything in Uniswap
        (inventory0, inventory1) = _collectableAmountsAsOfLastPoke(elastic);
        // Everything in Compound
        inventory0 += silo0.getBalance();
        inventory1 += silo1.getBalance();
        // Everything in the contract
        inventory0 += TOKEN0.balanceOf(address(this));
        inventory1 += TOKEN1.balanceOf(address(this));
    }

    function getNextPositionWidth() public view returns (int24 width) {
        (uint176 mean, uint176 sigma) = fetchPriceStatistics();
        width = TickMath.getTickAtSqrtRatio(uint160(TWO_96 + FullMath.mulDiv(TWO_96, K * sigma, mean)));
        if (width < MIN_WIDTH) width = MIN_WIDTH;
    }

    /**
     * @notice Deposits tokens in proportion to the vault's current holdings.
     * @dev These tokens sit in the vault and are not used for liquidity on
     * Uniswap until the next rebalance. Also note it's not necessary to check
     * if user manipulated price to deposit cheaper, as the value of range
     * orders can only by manipulated higher.
     * @dev LOCK MODIFIER IS APPLIED IN AloeBlendCapped!!!
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
        silo0.poke();
        silo1.poke();

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
        (uint256 inventory0, uint256 inventory1) = getInventory();

        // If total supply > 0, pool can't be empty
        assert(totalSupply == 0 || inventory0 != 0 || inventory1 != 0);

        if (totalSupply == 0) {
            // For first deposit, just use the amounts desired
            amount0 = amount0Max;
            amount1 = amount1Max;
            shares = amount0 > amount1 ? amount0 : amount1; // max
        } else if (inventory0 == 0) {
            amount1 = amount1Max;
            shares = FullMath.mulDiv(amount1, totalSupply, inventory1);
        } else if (inventory1 == 0) {
            amount0 = amount0Max;
            shares = FullMath.mulDiv(amount0, totalSupply, inventory0);
        } else {
            amount0 = FullMath.mulDiv(amount1Max, inventory0, inventory1);

            if (amount0 < amount0Max) {
                amount1 = amount1Max;
                shares = FullMath.mulDiv(amount1, totalSupply, inventory1);
            } else {
                amount0 = amount0Max;
                amount1 = FullMath.mulDiv(amount0, inventory1, inventory0);
                shares = FullMath.mulDiv(amount0, totalSupply, inventory0);
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

        // Portion from Uniswap
        (amount0, amount1) = _uniswapExitFraction(shares, totalSupply, elastic);

        // Portion from Compound
        uint256 temp0 = FullMath.mulDiv(silo0.getBalance(), shares, totalSupply);
        uint256 temp1 = FullMath.mulDiv(silo1.getBalance(), shares, totalSupply);
        silo0.withdraw(temp0);
        silo1.withdraw(temp1);
        amount0 += temp0;
        amount1 += temp1;

        // Portion from contract
        amount0 += FullMath.mulDiv(TOKEN0.balanceOf(address(this)), shares, totalSupply);
        amount1 += FullMath.mulDiv(TOKEN1.balanceOf(address(this)), shares, totalSupply);

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
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = UNI_POOL.slot0();
        uint224 priceX96 = uint224(FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, TWO_96));
        int24 w = getNextPositionWidth() >> 1;
        uint96 magic = uint96(TWO_96 - TickMath.getSqrtRatioAtTick(-w));
        uint128 liquidity;

        // Exit current Uniswap positions
        {
            (liquidity, , , , ) = _position(elastic);
            _uniswapExit(elastic, liquidity);
        }

        (uint256 inventory0, uint256 inventory1) = getInventory();
        uint256 amount0;
        uint256 amount1;
        if (FullMath.mulDiv(inventory0, priceX96, TWO_96) > inventory1) {
            amount1 = FullMath.mulDiv(inventory1, magic, TWO_96);
            amount0 = FullMath.mulDiv(amount1, TWO_96, priceX96);
        } else {
            amount0 = FullMath.mulDiv(inventory0, magic, TWO_96);
            amount1 = FullMath.mulDiv(amount0, priceX96, TWO_96);
        }

        uint256 balance0 = TOKEN0.balanceOf(address(this));
        uint256 balance1 = TOKEN1.balanceOf(address(this));
        bool hasExcessToken0 = balance0 > amount0;
        bool hasExcessToken1 = balance1 > amount1;

        if (!hasExcessToken0) silo0.withdraw(amount0 - balance0);
        if (!hasExcessToken1) silo1.withdraw(amount1 - balance1);

        // Place elastic order on Uniswap
        Ticks memory elasticNew = _coerceTicksToSpacing(Ticks(tick - w, tick + w));
        liquidity = _liquidityForAmounts(elasticNew, sqrtPriceX96, amount0, amount1);
        delete lastMintedAmount0;
        delete lastMintedAmount1;
        _uniswapEnter(elasticNew, liquidity);
        elastic = elasticNew;

        // Place excess into Compound
        if (hasExcessToken0) silo0.deposit(inventory0 - lastMintedAmount0);
        if (hasExcessToken1) silo1.deposit(inventory1 - lastMintedAmount1);
    }

    function _coerceTicksToSpacing(Ticks memory ticks) private view returns (Ticks memory ticksCoerced) {
        int24 tickSpacing = TICK_SPACING;
        ticksCoerced.lower =
            ticks.lower -
            (ticks.lower < 0 ? tickSpacing + (ticks.lower % tickSpacing) : ticks.lower % tickSpacing);
        ticksCoerced.upper =
            ticks.upper +
            (ticks.upper < 0 ? -ticks.upper % tickSpacing : tickSpacing - (ticks.upper % tickSpacing));
        assert(ticksCoerced.lower <= ticks.lower);
        assert(ticksCoerced.upper >= ticks.upper);
    }

    function fetchPriceStatistics() public view returns (uint176 mean, uint176 sigma) {
        (int56[] memory tickCumulatives, ) = UNI_POOL.observe(selectedOracleTimetable());

        // Compute mean price over the entire 54 minute period
        mean = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[9] - tickCumulatives[0]) / 3240));
        mean = uint176(FullMath.mulDiv(mean, mean, TWO_144));

        // `stat` variable will take on a few different statistical values
        // Here it's MAD (Mean Absolute Deviation), except not yet divided by number of samples
        uint184 stat;
        uint176 sample;

        for (uint8 i = 0; i < 9; i++) {
            // Compute mean price over a 6 minute period
            sample = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[i + 1] - tickCumulatives[i]) / 360));
            sample = uint176(FullMath.mulDiv(sample, sample, TWO_144));

            // Accumulate
            stat += sample > mean ? sample - mean : mean - sample;
        }

        // MAD = stat / n, here n = 10
        // STDDEV = MAD * sqrt(2/pi) for a normal distribution
        sigma = uint176((uint256(stat) * 79788) / 1000000);
    }

    function selectedOracleTimetable() public pure returns (uint32[] memory secondsAgos) {
        secondsAgos = new uint32[](10);
        secondsAgos[0] = 3420;
        secondsAgos[1] = 3060;
        secondsAgos[2] = 2700;
        secondsAgos[3] = 2340;
        secondsAgos[4] = 1980;
        secondsAgos[5] = 1620;
        secondsAgos[6] = 1260;
        secondsAgos[7] = 900;
        secondsAgos[8] = 540;
        secondsAgos[9] = 180;
    }
}
