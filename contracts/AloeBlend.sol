// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";

import "./libraries/FullMath.sol";
import "./libraries/TickMath.sol";
import "./libraries/Silo.sol";
import "./libraries/Uniswap.sol";

import "./interfaces/IAloeBlend.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IVolatilityOracle.sol";

import "./AloeBlendERC20.sol";
import "./UniswapHelper.sol";

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
*/

uint256 constant Q96 = 2**96;

contract AloeBlend is AloeBlendERC20, UniswapHelper, ReentrancyGuard, IAloeBlend {
    using SafeERC20 for IERC20;
    using Uniswap for Uniswap.Position;
    using Silo for ISilo;

    /// @inheritdoc IAloeBlendImmutables
    uint24 public constant MIN_WIDTH = 201; // 1% of inventory in primary Uniswap position

    /// @inheritdoc IAloeBlendImmutables
    uint24 public constant MAX_WIDTH = 13864; // 50% of inventory in primary Uniswap position

    /// @inheritdoc IAloeBlendImmutables
    uint8 public constant K = 10; // maintenance budget should cover at least 10 rebalances

    /// @inheritdoc IAloeBlendImmutables
    uint8 public constant B = 2; // primary Uniswap position should cover 95% of trading activity

    /// @inheritdoc IAloeBlendImmutables
    uint8 public constant MAINTENANCE_FEE = 10; // 1/10th of earnings from primary Uniswap position

    /// @inheritdoc IAloeBlendImmutables
    IVolatilityOracle public immutable volatilityOracle;

    /// @inheritdoc IAloeBlendImmutables
    ISilo public immutable silo0;

    /// @inheritdoc IAloeBlendImmutables
    ISilo public immutable silo1;

    struct PackedSlot {
        int24 primaryLower;
        int24 primaryUpper;
        bool primaryIsActive;
        int24 limitLower;
        int24 limitUpper;
        bool limitIsActive;
        uint64 rebalanceCount;
        uint48 recenterTimestamp;
    }

    PackedSlot public packedSlot;

    /// @inheritdoc IAloeBlendState
    uint256 public maintenanceBudget0;

    /// @inheritdoc IAloeBlendState
    uint256 public maintenanceBudget1;

    uint256[10] public rewardPerGas0Array;

    uint256[10] public rewardPerGas1Array;

    uint256 public rewardPerGas0Average;

    uint256 public rewardPerGas1Average;

    /// @dev Required for some silos
    receive() external payable {}

    constructor(
        IUniswapV3Pool _uniPool,
        ISilo _silo0,
        ISilo _silo1
    )
        AloeBlendERC20(
            // ex: Aloe Blend USDC/WETH
            string(
                abi.encodePacked(
                    "Aloe Blend ",
                    IERC20Metadata(_uniPool.token0()).symbol(),
                    "/",
                    IERC20Metadata(_uniPool.token1()).symbol()
                )
            )
        )
        UniswapHelper(_uniPool)
    {
        volatilityOracle = IFactory(msg.sender).VOLATILITY_ORACLE();
        silo0 = _silo0;
        silo1 = _silo1;

        (uint32 maxSecondsAgo, , , ) = volatilityOracle.cachedPoolMetadata(address(_uniPool));
        require(maxSecondsAgo >= 1 hours, "Aloe: oracle");
    }

    /// @inheritdoc IAloeBlendActions
    function deposit(
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        nonReentrant
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(amount0Max != 0 || amount1Max != 0, "Aloe: 0 deposit");

        // Poke all assets
        (Uniswap.Position memory primary, Uniswap.Position memory limit, , ) = parsePackedSlot();
        primary.poke();
        limit.poke();
        silo0.delegate_poke();
        silo1.delegate_poke();

        (uint160 sqrtPriceX96, , , , , , ) = UNI_POOL.slot0();
        (uint256 inventory0, uint256 inventory1, , ) = _getInventory(primary, limit, sqrtPriceX96); // 🔫 exact values for primary.liquidity and limit.liquidity are fetched behind the scenes here, for free. need to either update storage after this (to account for other people minting with this contract as the recipient) or change the behind-the-scenes stuff to use local storage rather than value that's fetched from Uniswap
        (shares, amount0, amount1) = _computeLPShares(
            totalSupply,
            inventory0,
            inventory1,
            amount0Max,
            amount1Max,
            sqrtPriceX96
        );
        require(shares != 0, "Aloe: 0 shares");
        require(amount0 >= amount0Min, "Aloe: amount0 too low");
        require(amount1 >= amount1Min, "Aloe: amount1 too low");

        // Pull in tokens from sender
        TOKEN0.safeTransferFrom(msg.sender, address(this), amount0);
        TOKEN1.safeTransferFrom(msg.sender, address(this), amount1);

        // Mint shares
        _mint(msg.sender, shares);
        emit Deposit(msg.sender, shares, amount0, amount1);
    }

    /// @inheritdoc IAloeBlendActions
    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(shares != 0, "Aloe: 0 shares");
        uint256 _totalSupply = totalSupply + 1;
        uint256 temp0;
        uint256 temp1;

        // Portion from contract
        // NOTE: Must be done FIRST to ensure we don't double count things after exiting Uniswap/silos
        amount0 = FullMath.mulDiv(_balance0(), shares, _totalSupply);
        amount1 = FullMath.mulDiv(_balance1(), shares, _totalSupply);

        // Portion from Uniswap
        (temp0, temp1) = _withdrawFractionFromUniswap(shares, _totalSupply);
        amount0 += temp0;
        amount1 += temp1;

        // Portion from silos
        temp0 = FullMath.mulDiv(silo0.balanceOf(address(this)), shares, _totalSupply);
        temp1 = FullMath.mulDiv(silo1.balanceOf(address(this)), shares, _totalSupply);
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
        uint224 priceX96;
        int24 tick;
        uint24 w;
        uint96 magic;
        uint32 urgency;
    }

    /// @inheritdoc IAloeBlendActions
    function rebalance(uint8 rewardToken) external nonReentrant {
        uint32 gasStart = uint32(gasleft());
        (
            Uniswap.Position memory primary,
            Uniswap.Position memory limit,
            uint64 rebalanceCount,
            uint48 recenterTimestamp
        ) = parsePackedSlot();

        // Populate rebalance cache
        RebalanceCache memory cache;
        (cache.sqrtPriceX96, cache.tick, , , , , ) = UNI_POOL.slot0();
        cache.priceX96 = uint224(FullMath.mulDiv(cache.sqrtPriceX96, cache.sqrtPriceX96, Q96));
        cache.urgency = getRebalanceUrgency();

        // Check inventory
        (
            uint256 inventory0,
            uint256 inventory1,
            uint256 fluid0,
            uint256 fluid1,
            uint128 primaryLiquidity,
            uint128 limitLiquidity
        ) = _getInventory(primary, limit, cache.sqrtPriceX96);

        // Remove the limit order if it exists
        if (limitLiquidity != 0) {
            limit.withdraw(limitLiquidity, 1, 1);
            limit.isActive = false;
        }

        // Compute inventory ratio to determine what happens next
        uint256 ratio = FullMath.mulDiv(
            10_000,
            inventory0,
            inventory0 + FullMath.mulDiv(inventory1, Q96, cache.priceX96)
        );
        if (ratio < 4900) {
            // Attempt to sell token1 for token0. Choose limit order bounds below the market price
            limit.upper = TickMath.floor(cache.tick, TICK_SPACING);
            limit.lower = limit.upper - TICK_SPACING;
            // Choose amount1 such that ratio will be 50/50 once the limit order is pushed through. Division by 2
            // works for small tickSpacing. Also have to constrain to fluid1 since we're not yet withdrawing from
            // primary Uniswap position
            uint256 amount1 = (inventory1 - FullMath.mulDiv(inventory0, cache.priceX96, Q96)) >> 1;
            if (amount1 > fluid1) amount1 = fluid1;
            // Withdraw requisite amount from silo1
            uint256 balance1 = _balance1();
            if (balance1 < amount1) silo1.delegate_withdraw(amount1 - balance1);
            // Place a new limit order and store bounds
            limit.deposit(limit.liquidityForAmount1(amount1));
            limit.isActive = true;
        } else if (ratio > 5100) {
            // Attempt to sell token1 for token0. Choose limit order bounds above the market price
            limit.lower = TickMath.ceil(cache.tick, TICK_SPACING);
            limit.upper = limit.lower + TICK_SPACING;
            // Choose amount0 such that ratio will be 50/50 once the limit order is pushed through. Division by 2
            // works for small tickSpacing. Also have to constrain to fluid0 since we're not yet withdrawing from
            // primary Uniswap position
            uint256 amount0 = (inventory0 - FullMath.mulDiv(inventory1, Q96, cache.priceX96)) >> 1;
            if (amount0 > fluid0) amount0 = fluid0;
            // Withdraw requisite amount from silo0
            uint256 balance0 = _balance0();
            if (balance0 < amount0) silo0.delegate_withdraw(amount0 - balance0);
            // Place a new limit order and store bounds
            limit.deposit(limit.liquidityForAmount0(amount0));
            limit.isActive = true;
        } else {
            recenter(cache, inventory0, inventory1);
        }

        // Poke primary position and withdraw fees so that maintenance budget can grow
        {
            primary.poke(); // TODO this whole thing is stupid if `recenter` already ran
            (uint256 earned0, uint256 earned1) = primary.collect();
            _earmarkSomeForMaintenance(earned0, earned1); // TODO should include silo earnings in maintenance calc as well
        }

        // Reward caller TODO rewards them even if they added/removed limit order in same place unnecessarily
        {
            uint256 rewardPerGas;
            uint256 rebalanceIncentive;

            if (rewardToken == 0) {
                // computations
                rewardPerGas = FullMath.mulDiv(rewardPerGas0Average, cache.urgency, 10_000);
                rebalanceIncentive = rewardPerGas * (21000 + gasStart - gasleft());
                // constraints
                if (rebalanceIncentive > maintenanceBudget0 || rewardPerGas == 0)
                    rebalanceIncentive = maintenanceBudget0;
                // payout
                TOKEN0.safeTransfer(msg.sender, rebalanceIncentive);
                maintenanceBudget0 -= rebalanceIncentive;
                // accounting
                pushRewardPerGas0(rewardPerGas);
                if (maintenanceBudget0 > K * rewardPerGas * block.gaslimit)
                    maintenanceBudget0 = K * rewardPerGas * block.gaslimit;
            } else {
                // computations
                rewardPerGas = FullMath.mulDiv(rewardPerGas1Average, cache.urgency, 10_000);
                rebalanceIncentive = rewardPerGas * (21000 + gasStart - gasleft());
                // constraints
                if (rebalanceIncentive > maintenanceBudget1 || rewardPerGas == 0)
                    rebalanceIncentive = maintenanceBudget1;
                // payout
                TOKEN1.safeTransfer(msg.sender, rebalanceIncentive);
                maintenanceBudget1 -= rebalanceIncentive;
                // accounting
                pushRewardPerGas1(rewardPerGas);
                if (maintenanceBudget1 > K * rewardPerGas * block.gaslimit)
                    maintenanceBudget1 = K * rewardPerGas * block.gaslimit;
            }
        }

        rebalanceCount++;
        emit Rebalance(cache.urgency, ratio, totalSupply, inventory0, inventory1);
    }

    function recenter(
        RebalanceCache memory cache,
        uint256 inventory0,
        uint256 inventory1
    ) private {
        uint256 sigma = volatilityOracle.estimate24H(UNI_POOL, cache.sqrtPriceX96, cache.tick);
        cache.w = _computeNextPositionWidth(sigma);

        // Exit primary Uniswap position
        {
            uint256 earned0;
            uint256 earned1;
            (, , earned0, earned1) = primary.withdraw(1, 1);
            _earmarkSomeForMaintenance(earned0, earned1);
        }

        // Compute amounts that should be placed in new Uniswap position
        uint256 amount0;
        uint256 amount1;
        cache.w = cache.w >> 1;
        (cache.magic, amount0, amount1) = _computeMagicAmounts(inventory0, inventory1, cache.priceX96, cache.w);

        uint256 balance0 = _balance0();
        uint256 balance1 = _balance1();
        bool hasExcessToken0 = balance0 > amount0;
        bool hasExcessToken1 = balance1 > amount1;

        // Because of cToken exchangeRate rounding, we may withdraw too much
        // here. That's okay; dust will just sit in contract till next rebalance
        if (!hasExcessToken0) silo0.delegate_withdraw(amount0 - balance0);
        if (!hasExcessToken1) silo1.delegate_withdraw(amount1 - balance1);

        // Update primary position's ticks
        primary.lower = TickMath.floor(cache.tick - int24(cache.w), TICK_SPACING);
        primary.upper = TickMath.ceil(cache.tick + int24(cache.w), TICK_SPACING);
        if (primary.lower < TickMath.MIN_TICK) primary.lower = TickMath.MIN_TICK;
        if (primary.upper > TickMath.MAX_TICK) primary.upper = TickMath.MAX_TICK;

        // Place some liquidity in Uniswap
        (amount0, amount1) = primary.deposit(primary.liquidityForAmounts(cache.sqrtPriceX96, amount0, amount1));

        // Place excess into silos
        if (hasExcessToken0) silo0.delegate_deposit(balance0 - amount0);
        if (hasExcessToken1) silo1.delegate_deposit(balance1 - amount1);

        recenterTimestamp = block.timestamp;
        emit Recenter(primary.lower, primary.upper, cache.magic);
    }

    /// @dev Withdraws fraction of liquidity from Uniswap, but collects *all* fees from it
    function _withdrawFractionFromUniswap(uint256 numerator, uint256 denominator)
        private
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 earned0;
        uint256 earned1;

        // Primary position
        (primary, amount0, amount1, earned0, earned1) = primary.withdraw(numerator, denominator);
        (earned0, earned1) = _earmarkSomeForMaintenance(earned0, earned1);
        // --> Report the proper share of earned fees
        amount0 += FullMath.mulDiv(earned0, numerator, denominator);
        amount1 += FullMath.mulDiv(earned1, numerator, denominator);

        // Limit order
        Uniswap.Position memory _limit = limit;
        if (_limit.liquidity != 0) {
            // Fees earned by the limit order are negligible. We ignore them to save gas, and
            // reuse earned0 & earned1 variables rather than creating temp0 & temp1
            (limit, earned0, earned1, , ) = _limit.withdraw(numerator, denominator);
            // --> Add to amounts from primary position
            amount0 += earned0;
            amount1 += earned1;
        }
    }

    /// @dev Earmark some earned fees for maintenance, according to `maintenanceFee`. Return what's leftover
    function _earmarkSomeForMaintenance(uint256 earned0, uint256 earned1) private returns (uint256, uint256) {
        uint256 toMaintenance;

        unchecked {
            // Accrue token0
            toMaintenance = earned0 / MAINTENANCE_FEE;
            earned0 -= toMaintenance;
            maintenanceBudget0 += toMaintenance;
            // Accrue token1
            toMaintenance = earned1 / MAINTENANCE_FEE;
            earned1 -= toMaintenance;
            maintenanceBudget1 += toMaintenance;
        }

        return (earned0, earned1);
    }

    function pushRewardPerGas0(uint256 rewardPerGas0) private {
        unchecked {
            uint8 idx = uint8(rebalanceCount % 10);
            rewardPerGas0 /= 10;
            rewardPerGas0Average = rewardPerGas0Average + rewardPerGas0 - rewardPerGas0Array[idx];
            rewardPerGas0Array[idx] = rewardPerGas0;
        }
    }

    function pushRewardPerGas1(uint256 rewardPerGas1) private {
        unchecked {
            uint8 idx = uint8(rebalanceCount % 10);
            rewardPerGas1 /= 10;
            rewardPerGas1Average = rewardPerGas1Average + rewardPerGas1 - rewardPerGas1Array[idx];
            rewardPerGas1Array[idx] = rewardPerGas1;
        }
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    /// @inheritdoc IAloeBlendDerivedState
    function getRebalanceUrgency() public view returns (uint32 urgency) {
        urgency = _computeRebalanceUrgency(packedSlot.recenterTimestamp);
    }

    /// @inheritdoc IAloeBlendDerivedState
    function getInventory() public view returns (uint256 inventory0, uint256 inventory1) {
        (uint160 sqrtPriceX96, , , , , , ) = UNI_POOL.slot0();
        (inventory0, inventory1, , ) = _getInventory(sqrtPriceX96, true);
    }

    /// @dev TODO
    function _getInventory(
        Uniswap.Position memory _primary,
        Uniswap.Position memory _limit,
        uint160 _sqrtPriceX96
    )
        private
        view
        returns (
            uint256 inventory0,
            uint256 inventory1,
            uint256 availableForLimit0,
            uint256 availableForLimit1,
            uint128 primaryLiquidity,
            uint128 limitLiquidity
        )
    {
        (availableForLimit0, availableForLimit1, limitLiquidity) = _limit.collectableAmountsAsOfLastPoke(_sqrtPriceX96);
        // Everything in silos + everything in the contract, except maintenance budget
        availableForLimit0 += silo0.balanceOf(address(this)) + _balance0();
        availableForLimit1 += silo1.balanceOf(address(this)) + _balance1();
        // Everything in primary Uniswap position. Limit order is placed without moving this, so its
        // amounts don't get added to availableForLimit.
        (inventory0, inventory1, primaryLiquidity) = _primary.collectableAmountsAsOfLastPoke(_sqrtPriceX96);
        inventory0 += availableForLimit0;
        inventory1 += availableForLimit1;
    }

    /// @dev TODO
    // ✅
    function parsePackedSlot()
        private
        view
        returns (
            Uniswap.Position memory primary,
            Uniswap.Position memory limit,
            uint64 rebalanceCount,
            uint48 recenterTimestamp
        )
    {
        primary.pool = UNI_POOL;
        limit.pool = UNI_POOL;
        (
            primary.lower,
            primary.upper,
            primary.isActive,
            limit.lower,
            limit.upper,
            limit.isActive,
            rebalanceCount,
            recenterTimestamp
        ) = packedSlot;
    }

    /// @dev TODO
    // ✅
    function _balance0() private view returns (uint256) {
        return TOKEN0.balanceOf(address(this)) - maintenanceBudget0;
    }

    /// @dev TODO
    // ✅
    function _balance1() private view returns (uint256) {
        return TOKEN1.balanceOf(address(this)) - maintenanceBudget1;
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    /// @dev TODO
    function _computeRebalanceUrgency(uint48 _recenterTimestamp) internal pure returns (uint32 urgency) {
        urgency = uint32(FullMath.mulDiv(10_000, block.timestamp - _recenterTimestamp, 24 hours));
    }

    /// @dev Computes position width based on volatility. Doesn't revert
    // ✅
    function _computeNextPositionWidth(uint256 _sigma) internal pure returns (uint24) {
        if (_sigma <= 5.024579e15) return MIN_WIDTH;
        if (_sigma >= 3.000058e17) return MAX_WIDTH;
        _sigma *= B; // scale by a constant factor to increase confidence

        unchecked {
            uint160 ratio = uint160((Q96 * (1e18 + _sigma)) / (1e18 - _sigma));
            return uint24(TickMath.getTickAtSqrtRatio(ratio)) >> 1;
        }
    }

    /// @dev Computes amounts that should be placed in primary Uniswap position to maintain 50/50 inventory ratio.
    /// Doesn't revert as long as MIN_WIDTH <= _halfWidth * 2 <= MAX_WIDTH
    // ✅
    function _computeMagicAmounts(
        uint256 _inventory0,
        uint256 _inventory1,
        uint224 _priceX96,
        uint24 _halfWidth
    )
        internal
        pure
        returns (
            uint96 magic,
            uint256 amount0,
            uint256 amount1
        )
    {
        magic = uint96(Q96 - TickMath.getSqrtRatioAtTick(-int24(_halfWidth)));
        if (FullMath.mulDiv(_inventory0, _priceX96, Q96) > _inventory1) {
            amount1 = FullMath.mulDiv(_inventory1, magic, Q96);
            amount0 = FullMath.mulDiv(amount1, Q96, _priceX96);
        } else {
            amount0 = FullMath.mulDiv(_inventory0, magic, Q96);
            amount1 = FullMath.mulDiv(amount0, _priceX96, Q96);
        }
    }

    /// @dev Computes the largest possible `amount0` and `amount1` such that they match the current inventory ratio,
    /// but are not greater than `_amount0Max` and `_amount1Max` respectively. May revert if the following are true:
    ///     _totalSupply * _amount0Max / _inventory0 > type(uint256).max
    ///     _totalSupply * _amount1Max / _inventory1 > type(uint256).max
    /// This is okay because it only blocks deposit (not withdraw). Can also workaround by depositing smaller amounts
    // ✅
    function _computeLPShares(
        uint256 _totalSupply,
        uint256 _inventory0,
        uint256 _inventory1,
        uint256 _amount0Max,
        uint256 _amount1Max,
        uint160 _sqrtPriceX96
    )
        internal
        pure
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        // If total supply > 0, pool can't be empty
        assert(_totalSupply == 0 || _inventory0 != 0 || _inventory1 != 0);

        if (_totalSupply == 0) {
            // For first deposit, enforce 50/50 ratio manually
            uint224 priceX96 = uint224(FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, Q96));
            amount0 = FullMath.mulDiv(_amount1Max, Q96, priceX96);

            if (amount0 < _amount0Max) {
                amount1 = _amount1Max;
                shares = amount1;
            } else {
                amount0 = _amount0Max;
                amount1 = FullMath.mulDiv(amount0, priceX96, Q96);
                shares = amount0;
            }
        } else if (_inventory0 == 0) {
            amount1 = _amount1Max;
            shares = FullMath.mulDiv(amount1, _totalSupply, _inventory1);
        } else if (_inventory1 == 0) {
            amount0 = _amount0Max;
            shares = FullMath.mulDiv(amount0, _totalSupply, _inventory0);
        } else {
            // The branches of this ternary are logically identical, but must be separate to avoid overflow
            bool cond = _inventory0 < _inventory1
                ? FullMath.mulDiv(_amount1Max, _inventory0, _inventory1) < _amount0Max
                : _amount1Max < FullMath.mulDiv(_amount0Max, _inventory1, _inventory0);

            if (cond) {
                amount1 = _amount1Max;
                amount0 = FullMath.mulDiv(amount1, _inventory0, _inventory1);
                shares = FullMath.mulDiv(amount1, _totalSupply, _inventory1);
            } else {
                amount0 = _amount0Max;
                amount1 = FullMath.mulDiv(amount0, _inventory1, _inventory0);
                shares = FullMath.mulDiv(amount0, _totalSupply, _inventory0);
            }
        }
    }
}
