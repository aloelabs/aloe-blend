// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/FullMath.sol";
import "./libraries/TickMath.sol";

import "./external/Compound.sol";
import "./external/Uniswap.sol";

import "./interfaces/IAloeBlend.sol";

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

contract AloeBlend is AloeBlendERC20, UniswapMinter, IAloeBlend {
    using SafeERC20 for IERC20;
    using Uniswap for Uniswap.Position;
    using Compound for Compound.Market;

    /// @inheritdoc IAloeBlendImmutables
    int24 public constant override MIN_WIDTH = 1000; // 1000 --> 2.5% of total inventory

    /// @inheritdoc IAloeBlendState
    uint8 public override K = 20;

    /// @inheritdoc IAloeBlendState
    Uniswap.Position public override combine;

    /// @inheritdoc IAloeBlendState
    Compound.Market public override silo0;

    /// @inheritdoc IAloeBlendState
    Compound.Market public override silo1;

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

    constructor(
        IUniswapV3Pool uniPool,
        address cToken0,
        address cToken1
    ) AloeBlendERC20() UniswapMinter(uniPool) {
        combine.pool = uniPool;
        silo0.initialize(cToken0);
        silo1.initialize(cToken1);
    }

    /// @inheritdoc IAloeBlendDerivedState
    function getInventory() public view override returns (uint256 inventory0, uint256 inventory1) {
        // Everything in Uniswap
        (inventory0, inventory1) = combine.collectableAmountsAsOfLastPoke();
        // Everything in Compound
        inventory0 += silo0.getBalance();
        inventory1 += silo1.getBalance();
        // Everything in the contract
        inventory0 += TOKEN0.balanceOf(address(this));
        inventory1 += TOKEN1.balanceOf(address(this));
    }

    /// @inheritdoc IAloeBlendDerivedState
    function getNextPositionWidth() public view override returns (int24 width) {
        (uint176 mean, uint176 sigma) = fetchPriceStatistics();
        width = TickMath.getTickAtSqrtRatio(uint160(TWO_96 + FullMath.mulDiv(TWO_96, K * sigma, mean)));
        if (width < MIN_WIDTH) width = MIN_WIDTH;
    }

    /// @inheritdoc IAloeBlendActions
    /// @dev LOCK MODIFIER IS APPLIED IN AloeBlendCapped!!!
    function deposit(
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 amount0Min,
        uint256 amount1Min
    )
        public
        virtual
        override
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(amount0Max != 0 || amount1Max != 0, "Aloe: 0 deposit");

        combine.poke();
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

    /// @inheritdoc IAloeBlendActions
    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        require(shares != 0, "Aloe: 0 shares");
        uint256 totalSupply = totalSupply() + 1;
        uint256 temp0;
        uint256 temp1;

        // Portion from contract
        // NOTE: Must be done FIRST to ensure we don't double count things after exiting Uniswap/Compound
        amount0 = FullMath.mulDiv(TOKEN0.balanceOf(address(this)), shares, totalSupply);
        amount1 = FullMath.mulDiv(TOKEN1.balanceOf(address(this)), shares, totalSupply);

        // Portion from Uniswap
        (temp0, temp1) = combine.withdrawFraction(shares, totalSupply);
        amount0 += temp0;
        amount1 += temp1;

        // Portion from Compound
        temp0 = FullMath.mulDiv(silo0.getBalance(), shares, totalSupply);
        temp1 = FullMath.mulDiv(silo1.getBalance(), shares, totalSupply);
        silo0.withdraw(temp0);
        silo1.withdraw(temp1);
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

    struct RebalanceCache {
        uint160 sqrtPriceX96;
        uint96 magic;
        int24 tick;
        int24 w;
        uint224 priceX96;
    }

    /// @inheritdoc IAloeBlendActions
    function rebalance() external override lock {
        Uniswap.Position memory _combine = combine;
        RebalanceCache memory cache;

        // Get current tick & price
        (cache.sqrtPriceX96, cache.tick, , , , , ) = _combine.pool.slot0();
        cache.priceX96 = uint224(FullMath.mulDiv(cache.sqrtPriceX96, cache.sqrtPriceX96, TWO_96));
        // Get new position width & inventory usage fraction
        cache.w = getNextPositionWidth() >> 1;
        cache.magic = uint96(TWO_96 - TickMath.getSqrtRatioAtTick(-cache.w));

        // Exit current Uniswap position
        {
            (uint128 liquidity, , , , ) = _combine.info();
            _combine.withdraw(liquidity);
        }

        // Compute amounts that should be placed in Uniswap position
        uint256 amount0;
        uint256 amount1;
        (uint256 inventory0, uint256 inventory1) = getInventory();
        if (FullMath.mulDiv(inventory0, cache.priceX96, TWO_96) > inventory1) {
            amount1 = FullMath.mulDiv(inventory1, cache.magic, TWO_96);
            amount0 = FullMath.mulDiv(amount1, TWO_96, cache.priceX96);
        } else {
            amount0 = FullMath.mulDiv(inventory0, cache.magic, TWO_96);
            amount1 = FullMath.mulDiv(amount0, cache.priceX96, TWO_96);
        }

        uint256 balance0 = TOKEN0.balanceOf(address(this));
        uint256 balance1 = TOKEN1.balanceOf(address(this));
        bool hasExcessToken0 = balance0 > amount0;
        bool hasExcessToken1 = balance1 > amount1;

        // Because of cToken exchangeRate rounding, we may withdraw too much
        // here. That's okay; dust will just sit in contract till next rebalance
        if (!hasExcessToken0) silo0.withdraw(amount0 - balance0);
        if (!hasExcessToken1) silo1.withdraw(amount1 - balance1);

        // Update combine's ticks
        _combine.lower = cache.tick - cache.w;
        _combine.upper = cache.tick + cache.w;
        _combine = _coerceTicksToSpacing(_combine);
        combine.lower = _combine.lower;
        combine.upper = _combine.upper;

        // Place some liquidity in Uniswap
        delete lastMintedAmount0;
        delete lastMintedAmount1;
        _combine.deposit(_combine.liquidityForAmounts(cache.sqrtPriceX96, amount0, amount1));

        // Place excess into Compound
        if (hasExcessToken0) silo0.deposit(balance0 - lastMintedAmount0);
        if (hasExcessToken1) silo1.deposit(balance1 - lastMintedAmount1);

        emit Rebalance(_combine.lower, _combine.upper, cache.magic, inventory0, inventory1);
    }

    /// @inheritdoc IAloeBlendDerivedState
    function fetchPriceStatistics() public view override returns (uint176 mean, uint176 sigma) {
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

    /// @inheritdoc IAloeBlendDerivedState
    function selectedOracleTimetable() public pure override returns (uint32[] memory secondsAgos) {
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

    /// @dev Calculates the largest possible `amount0` and `amount1` such that
    /// they're in the same proportion as total amounts, but not greater than
    /// `amount0Max` and `amount1Max` respectively.
    function _computeLPShares(uint256 amount0Max, uint256 amount1Max)
        private
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

    function _coerceTicksToSpacing(Uniswap.Position memory p) private view returns (Uniswap.Position memory) {
        int24 tickSpacing = TICK_SPACING;
        p.lower = p.lower - (p.lower < 0 ? tickSpacing + (p.lower % tickSpacing) : p.lower % tickSpacing);
        p.upper = p.upper + (p.upper < 0 ? -p.upper % tickSpacing : tickSpacing - (p.upper % tickSpacing));
        return p;
    }
}
