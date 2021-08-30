// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/FullMath.sol";
import "./libraries/TickMath.sol";
import "./libraries/Silo.sol";

import "./external/Uniswap.sol";
import "./external/WETH.sol";

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
    using Silo for ISilo;

    /// @inheritdoc IAloeBlendImmutables
    uint8 public constant override DIVISOR_OF_REBALANCE_REWARD = 4;

    /// @inheritdoc IAloeBlendImmutables
    uint8 public constant override DIVISOR_OF_SHRINK_URGENCY = 2;

    /// @inheritdoc IAloeBlendImmutables
    uint24 public constant override MIN_WIDTH = 1000; // 1000 --> 2.5% of total inventory

    /// @inheritdoc IAloeBlendState
    uint8 public override K = 20;

    /// @inheritdoc IAloeBlendState
    uint256 public override maintenanceFee = 2500; // 2500 --> 25% of swap fees

    /// @inheritdoc IAloeBlendState
    uint256 public override maintenanceBudget0;

    /// @inheritdoc IAloeBlendState
    uint256 public override maintenanceBudget1;

    /// @inheritdoc IAloeBlendState
    Uniswap.Position public override uniswap;

    /// @inheritdoc IAloeBlendState
    ISilo public override silo0;

    /// @inheritdoc IAloeBlendState
    ISilo public override silo1;

    /// @dev For reentrancy check
    bool private locked;

    modifier lock() {
        require(!locked, "Aloe: Locked");
        locked = true;
        _;
        locked = false;
    }

    /// @dev Required for some silos
    receive() external payable {}

    constructor(
        IUniswapV3Pool uniPool,
        ISilo _silo0,
        ISilo _silo1
    ) AloeBlendERC20() UniswapMinter(uniPool) {
        uniswap.pool = uniPool;
        silo0 = _silo0;
        silo1 = _silo1;
    }

    /// @inheritdoc IAloeBlendDerivedState
    function getInventory() public view override returns (uint256 inventory0, uint256 inventory1) {
        // Everything in Uniswap
        (inventory0, inventory1) = uniswap.collectableAmountsAsOfLastPoke();
        // Everything in silos
        inventory0 += silo0.balanceOf(address(this));
        inventory1 += silo1.balanceOf(address(this));
        // Everything in the contract, except maintenance budget
        inventory0 += _balance0();
        inventory1 += _balance1();
    }

    /// @inheritdoc IAloeBlendDerivedState
    function getRebalanceUrgency() public view override returns (uint16 urgency) {
        (uint24 width, int24 tickTWAP) = getNextPositionWidth();
        urgency = _computeRebalanceUrgency(uniswap, width, tickTWAP);
    }

    /// @inheritdoc IAloeBlendDerivedState
    function getNextPositionWidth() public virtual view override returns (uint24 width, int24 tickTWAP) {
        uint176 mean;
        uint176 sigma;
        (mean, sigma, tickTWAP) = fetchPriceStatistics();

        if (mean != 0) {
            width = uint24(
                TickMath.getTickAtSqrtRatio(uint160(TWO_96 + FullMath.mulDiv(TWO_96, uint176(K) * sigma, mean)))
            );
        }
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
        Uniswap.Position memory _uniswap = uniswap;

        // Poke all assets
        _uniswap.poke();
        silo0.delegate_poke();
        silo1.delegate_poke();

        // Fetch instantaneous price from Uniswap
        (uint160 sqrtPriceX96, , , , , , ) = UNI_POOL.slot0();
        uint224 priceX96 = uint224(FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, TWO_96));

        (shares, amount0, amount1) = _computeLPShares(amount0Max, amount1Max, priceX96);
        require(shares != 0, "Aloe: 0 shares");
        require(amount0 >= amount0Min, "Aloe: amount0 too low");
        require(amount1 >= amount1Min, "Aloe: amount1 too low");

        // Pull in tokens from sender
        TOKEN0.safeTransferFrom(msg.sender, address(this), amount0);
        TOKEN1.safeTransferFrom(msg.sender, address(this), amount1);

        // Put portion in Uniswap so that we don't deviate from 50/50 ratio in interim between
        // deposit and next rebalance
        if (_uniswap.lower != _uniswap.upper) {
            uint24 halfWidth = uint24(_uniswap.upper - _uniswap.lower) >> 1;
            (uint256 uni0, uint256 uni1, ) = _computeAmountsForUniswap(amount0, amount1, priceX96, halfWidth);
            _uniswap.deposit(_uniswap.liquidityForAmounts(sqrtPriceX96, uni0, uni1));
        }

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
        // NOTE: Must be done FIRST to ensure we don't double count things after exiting Uniswap/silos
        amount0 = FullMath.mulDiv(_balance0(), shares, totalSupply);
        amount1 = FullMath.mulDiv(_balance1(), shares, totalSupply);

        // Portion from Uniswap
        (temp0, temp1) = _withdrawFractionFromUniswap(shares, totalSupply);
        amount0 += temp0;
        amount1 += temp1;

        // Portion from silos
        temp0 = FullMath.mulDiv(silo0.balanceOf(address(this)), shares, totalSupply);
        temp1 = FullMath.mulDiv(silo1.balanceOf(address(this)), shares, totalSupply);
        silo0.delegate_withdraw(temp0);
        silo1.delegate_withdraw(temp1);
        amount0 += temp0;
        amount1 += temp1;

        // Check constraints
        require(amount0 >= amount0Min, "Aloe: amount0 too low");
        require(amount1 >= amount1Min, "Aloe: amount1 too low");

        // Transfer tokens
        TOKEN0.safeTransfer(msg.sender, amount0);
        TOKEN1.safeTransfer(msg.sender, amount1);

        // Burn shares
        _burn(msg.sender, shares);
        emit Withdraw(msg.sender, shares, amount0, amount1);
    }

    struct RebalanceCache {
        uint160 sqrtPriceX96;
        uint96 magic;
        int24 tick;
        int24 tickTWAP;
        uint24 w;
        uint16 urgency;
        uint224 priceX96;
    }

    /// @inheritdoc IAloeBlendActions
    function rebalance(uint8 rewardMode) external override lock {
        Uniswap.Position memory _uniswap = uniswap;
        RebalanceCache memory cache;

        // Get current tick & price
        (cache.sqrtPriceX96, cache.tick, , , , , ) = _uniswap.pool.slot0();
        cache.priceX96 = uint224(FullMath.mulDiv(cache.sqrtPriceX96, cache.sqrtPriceX96, TWO_96));
        // Get new position width and rebalance urgency
        (cache.w, cache.tickTWAP) = getNextPositionWidth();
        cache.urgency = _computeRebalanceUrgency(_uniswap, cache.w, cache.tickTWAP);

        // Exit current Uniswap position
        {
            (uint128 liquidity, , , , ) = _uniswap.info();
            (, , uint256 earned0, uint256 earned1) = _uniswap.withdraw(liquidity);
            _earmarkSomeForMaintenance(earned0, earned1);
        }

        // Compute amounts that should be placed in new Uniswap position
        uint256 amount0;
        uint256 amount1;
        (uint256 inventory0, uint256 inventory1) = getInventory();
        cache.w = cache.w >> 1;
        (amount0, amount1, cache.magic) = _computeAmountsForUniswap(inventory0, inventory1, cache.priceX96, cache.w);

        uint256 balance0 = _balance0();
        uint256 balance1 = _balance1();
        bool hasExcessToken0 = balance0 > amount0;
        bool hasExcessToken1 = balance1 > amount1;

        // Because of cToken exchangeRate rounding, we may withdraw too much
        // here. That's okay; dust will just sit in contract till next rebalance
        if (!hasExcessToken0) silo0.delegate_withdraw(amount0 - balance0);
        if (!hasExcessToken1) silo1.delegate_withdraw(amount1 - balance1);

        // Update Uniswap position's ticks
        _uniswap.lower = cache.tick - int24(cache.w);
        _uniswap.upper = cache.tick + int24(cache.w);
        _uniswap = _coerceTicksToSpacing(_uniswap);

        // Place some liquidity in Uniswap
        delete lastMintedAmount0;
        delete lastMintedAmount1;
        _uniswap.deposit(_uniswap.liquidityForAmounts(cache.sqrtPriceX96, amount0, amount1));
        uniswap.lower = _uniswap.lower;
        uniswap.upper = _uniswap.upper;

        // Place excess into silos
        if (hasExcessToken0) silo0.delegate_deposit(balance0 - lastMintedAmount0);
        if (hasExcessToken1) silo1.delegate_deposit(balance1 - lastMintedAmount1);

        // Reward caller
        {
            uint256 _divisor = 10_000 * uint256(DIVISOR_OF_REBALANCE_REWARD);
            if (rewardMode % 2 == 0) {
                amount0 = FullMath.mulDiv(maintenanceBudget0, cache.urgency, _divisor);
                TOKEN0.safeTransfer(msg.sender, amount0);
                maintenanceBudget0 -= amount0;
            }
            if (rewardMode != 0) {
                amount1 = FullMath.mulDiv(maintenanceBudget1, cache.urgency, _divisor);
                TOKEN1.safeTransfer(msg.sender, amount1);
                maintenanceBudget1 -= amount1;
            }
        }

        emit Rebalance(
            _uniswap.lower,
            _uniswap.upper,
            cache.magic,
            cache.urgency,
            totalSupply(),
            inventory0,
            inventory1
        );
    }

    /// @inheritdoc IAloeBlendDerivedState
    function fetchPriceStatistics()
        public
        view
        override
        returns (
            uint176 mean,
            uint176 sigma,
            int24 tickTWAP
        )
    {
        int56[] memory tickCumulatives;

        // Contract is neutered without more oracle data, but can still function
        (, , , bool hasSufficientData) = uniswap.pool.observations(720);
        if (!hasSufficientData) {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = 360;
            secondsAgos[1] = 0;

            (tickCumulatives, ) = UNI_POOL.observe(secondsAgos);
            return (0, 0, int24((tickCumulatives[1] - tickCumulatives[0]) / 360));
        }

        (tickCumulatives, ) = UNI_POOL.observe(selectedOracleTimetable());
        tickTWAP = int24((tickCumulatives[10] - tickCumulatives[9]) / 360);

        // Compute mean price over the entire 108 minute period
        mean = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[9] - tickCumulatives[0]) / 6480));
        mean = uint176(FullMath.mulDiv(mean, mean, TWO_144));

        // `stat` variable will take on a few different statistical values
        // Here it's MAD (Mean Absolute Deviation), except not yet divided by number of samples
        uint184 stat;
        uint176 sample;

        for (uint8 i = 0; i < 9; i++) {
            // Compute mean price over a 6 minute period
            sample = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[i + 1] - tickCumulatives[i]) / 720));
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
        secondsAgos = new uint32[](11);
        secondsAgos[0] = 6840;
        secondsAgos[1] = 6120;
        secondsAgos[2] = 5400;
        secondsAgos[3] = 4680;
        secondsAgos[4] = 3960;
        secondsAgos[5] = 3240;
        secondsAgos[6] = 2520;
        secondsAgos[7] = 1800;
        secondsAgos[8] = 1080;
        secondsAgos[9] = 360;
        secondsAgos[10] = 0;
    }

    /// @dev Calculates the largest possible `amount0` and `amount1` such that
    /// they're in the same proportion as total amounts, but not greater than
    /// `amount0Max` and `amount1Max` respectively.
    function _computeLPShares(
        uint256 amount0Max,
        uint256 amount1Max,
        uint224 priceX96
    )
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
            // For first deposit, enforce 50/50 ratio
            amount0 = FullMath.mulDiv(amount1Max, TWO_96, priceX96);

            if (amount0 < amount0Max) {
                amount1 = amount1Max;
                shares = amount1;
            } else {
                amount0 = amount0Max;
                amount1 = FullMath.mulDiv(amount0, priceX96, TWO_96);
                shares = amount0;
            }
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

    /// @dev Computes amounts that should be placed in Uniswap position
    function _computeAmountsForUniswap(
        uint256 inventory0,
        uint256 inventory1,
        uint224 priceX96,
        uint24 halfWidth
    )
        private
        pure
        returns (
            uint256 amount0,
            uint256 amount1,
            uint96 magic
        )
    {
        magic = uint96(TWO_96 - TickMath.getSqrtRatioAtTick(-int24(halfWidth)));
        if (FullMath.mulDiv(inventory0, priceX96, TWO_96) > inventory1) {
            amount1 = FullMath.mulDiv(inventory1, magic, TWO_96);
            amount0 = FullMath.mulDiv(amount1, TWO_96, priceX96);
        } else {
            amount0 = FullMath.mulDiv(inventory0, magic, TWO_96);
            amount1 = FullMath.mulDiv(amount0, priceX96, TWO_96);
        }
    }

    /// @dev Withdraws fraction of liquidity from Uniswap, but collects *all* fees from it
    function _withdrawFractionFromUniswap(uint256 numerator, uint256 denominator)
        private
        returns (uint256 amount0, uint256 amount1)
    {
        assert(numerator < denominator);
        Uniswap.Position memory _uniswap = uniswap;

        (uint128 liquidity, , , , ) = _uniswap.info();
        liquidity = uint128(FullMath.mulDiv(liquidity, numerator, denominator));

        uint256 earned0;
        uint256 earned1;
        (amount0, amount1, earned0, earned1) = _uniswap.withdraw(liquidity);
        (earned0, earned1) = _earmarkSomeForMaintenance(earned0, earned1);

        // Add share of earned fees
        amount0 += FullMath.mulDiv(earned0, numerator, denominator);
        amount1 += FullMath.mulDiv(earned1, numerator, denominator);
    }

    /// @dev Earmark some earned fees for maintenance, according to `maintenanceFee`. Return what's leftover
    function _earmarkSomeForMaintenance(uint256 earned0, uint256 earned1) private returns (uint256, uint256) {
        uint256 _maintenanceFee = maintenanceFee;
        if (_maintenanceFee != 0) {
            uint256 toMaintenance;
            // Accrue token0
            toMaintenance = FullMath.mulDiv(earned0, _maintenanceFee, 10_000);
            earned0 -= toMaintenance;
            maintenanceBudget0 += toMaintenance;
            // Accrue token1
            toMaintenance = FullMath.mulDiv(earned1, _maintenanceFee, 10_000);
            earned1 -= toMaintenance;
            maintenanceBudget1 += toMaintenance;
        }
        return (earned0, earned1);
    }

    function _computeRebalanceUrgency(
        Uniswap.Position memory current,
        uint24 newW,
        int24 tickTWAP
    ) private pure returns (uint16) {
        unchecked {
            int48 diff = (current.lower + current.upper) / 2 - tickTWAP;
            uint24 w = uint24(current.upper - current.lower);
            if (w == 0) return 0;

            uint48 urgency = (40_000 * uint48(diff**2)) / uint48(w)**2;
            if (urgency > 10_000) {
                urgency = 10_000;
            } else if (newW < w) {
                uint24 shrinkUrgency = (10_000 - (10_000 * newW) / w) / uint24(DIVISOR_OF_SHRINK_URGENCY);
                urgency = urgency + shrinkUrgency - ((urgency * uint48(shrinkUrgency)) / 10_000);
            }
            return uint16(urgency);
        }
    }

    function _coerceTicksToSpacing(Uniswap.Position memory p) private view returns (Uniswap.Position memory) {
        int24 tickSpacing = TICK_SPACING;
        p.lower = p.lower - (p.lower < 0 ? tickSpacing + (p.lower % tickSpacing) : p.lower % tickSpacing);
        p.upper = p.upper + (p.upper < 0 ? -p.upper % tickSpacing : tickSpacing - (p.upper % tickSpacing));
        return p;
    }

    function _balance0() private view returns (uint256) {
        return TOKEN0.balanceOf(address(this)) - maintenanceBudget0;
    }

    function _balance1() private view returns (uint256) {
        return TOKEN1.balanceOf(address(this)) - maintenanceBudget1;
    }
}
