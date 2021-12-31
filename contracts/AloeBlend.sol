// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

contract AloeBlend is AloeBlendERC20, UniswapHelper, IAloeBlend {
    using SafeERC20 for IERC20;
    using Uniswap for Uniswap.Position;
    using Silo for ISilo;

    /// TODO
    uint24 public constant RECENTERING_INTERVAL = 24 hours;

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
        int24 limitLower;
        int24 limitUpper;
        uint64 rebalanceCount;
        uint48 recenterTimestamp;
        bool locked;
    }

    /// @inheritdoc IAloeBlendState
    PackedSlot public packedSlot;

    /// @inheritdoc IAloeBlendState
    uint256 public maintenanceBudget0;

    /// @inheritdoc IAloeBlendState
    uint256 public maintenanceBudget1;

    /// TODO
    mapping(address => uint256[10]) public rewardPerGasArrays;

    /// TODO
    mapping(address => uint256) public rewardPerGasAverages;

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
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(amount0Max != 0 || amount1Max != 0, "Aloe: 0 deposit");
        // Reentrancy guard is embedded in `_loadPackedSlot` to save gas
        (Uniswap.Position memory primary, Uniswap.Position memory limit, , ) = _loadPackedSlot();
        packedSlot.locked = true;

        // Poke all assets
        primary.poke();
        limit.poke();
        silo0.delegate_poke();
        silo1.delegate_poke();

        (uint160 sqrtPriceX96, , , , , , ) = UNI_POOL.slot0();
        (uint256 inventory0, uint256 inventory1, ) = _getInventory(primary, limit, sqrtPriceX96);
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
        packedSlot.locked = false;
    }

    /// @inheritdoc IAloeBlendActions
    // TODO add reentranct guard
    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 amount0, uint256 amount1) {
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
    }

    /// @inheritdoc IAloeBlendActions
    function rebalance(address rewardToken) external {
        uint32 gas = uint32(gasleft());
        uint32 urgency = getRebalanceUrgency();
        // Reentrancy guard is embedded in `_loadPackedSlot` to save gas
        (
            Uniswap.Position memory primary,
            Uniswap.Position memory limit,
            uint64 rebalanceCount,
            uint48 recenterTimestamp
        ) = _loadPackedSlot();
        packedSlot.locked = true;

        // Populate rebalance cache
        RebalanceCache memory cache;
        (cache.sqrtPriceX96, cache.tick, , , , , ) = UNI_POOL.slot0();
        cache.priceX96 = uint224(FullMath.mulDiv(cache.sqrtPriceX96, cache.sqrtPriceX96, Q96));

        // Poke silos to ensure reported balances are correct
        silo0.delegate_poke();
        silo1.delegate_poke();

        // Check inventory
        (uint256 inventory0, uint256 inventory1, InventoryDetails memory d) = _getInventory(
            primary,
            limit,
            cache.sqrtPriceX96
        );

        // Remove the limit order if it exists
        if (d.limitLiquidity != 0) limit.withdraw(d.limitLiquidity);

        // Compute inventory ratio to determine what happens next
        uint256 ratio = FullMath.mulDiv(
            10_000,
            inventory0,
            inventory0 + FullMath.mulDiv(inventory1, Q96, cache.priceX96)
        );
        if (ratio < 4900) {
            // Attempt to sell token1 for token0. Choose limit order bounds below the market price. Limit
            // order cannot be removed & replaced in the same spot; it must move.
            limit.upper = TickMath.floor(cache.tick, TICK_SPACING);
            require(d.limitLiquidity == 0 || limit.lower != limit.upper - TICK_SPACING);
            limit.lower = limit.upper - TICK_SPACING;
            // Choose amount1 such that ratio will be 50/50 once the limit order is pushed through (division by 2
            // is a good approximation for small tickSpacing). Also have to constrain to fluid1 since we're not
            // yet withdrawing from primary Uniswap position
            uint256 amount1 = (inventory1 - FullMath.mulDiv(inventory0, cache.priceX96, Q96)) >> 1;
            if (amount1 > d.fluid1) amount1 = d.fluid1;
            // Withdraw requisite amount from silo1
            uint256 balance1 = _balance1();
            if (balance1 < amount1) silo1.delegate_withdraw(amount1 - balance1);
            // Place a new limit order and store bounds
            limit.deposit(limit.liquidityForAmount1(amount1));
        } else if (ratio > 5100) {
            // Attempt to sell token1 for token0. Choose limit order bounds above the market price. Limit
            // order cannot be removed & replaced in the same spot; it must move.
            limit.lower = TickMath.ceil(cache.tick, TICK_SPACING);
            require(d.limitLiquidity == 0 || limit.upper != limit.lower + TICK_SPACING);
            limit.upper = limit.lower + TICK_SPACING;
            // Choose amount0 such that ratio will be 50/50 once the limit order is pushed through (division by 2
            // is a good approximation for small tickSpacing). Also have to constrain to fluid0 since we're not
            // yet withdrawing from primary Uniswap position
            uint256 amount0 = (inventory0 - FullMath.mulDiv(inventory1, Q96, cache.priceX96)) >> 1;
            if (amount0 > d.fluid0) amount0 = d.fluid0;
            // Withdraw requisite amount from silo0
            uint256 balance0 = _balance0();
            if (balance0 < amount0) silo0.delegate_withdraw(amount0 - balance0);
            // Place a new limit order and store bounds
            limit.deposit(limit.liquidityForAmount0(amount0));
        } else {
            // Zero-out the limit struct to indicate that it's inactive
            delete limit;
            // Recenter, but not more than once per hour
            require(block.timestamp - recenterTimestamp > 1 hours);
            primary = _recenter(cache, primary, d.primaryLiquidity);
            recenterTimestamp = uint48(block.timestamp);
        }

        emit Rebalance(ratio, totalSupply, inventory0, inventory1);
        _rewardCaller(rewardToken, rebalanceCount, urgency, gas);
        _unlockAndStorePackedSlot(primary, limit, rebalanceCount + 1, recenterTimestamp);
    }

    function _recenter(
        RebalanceCache memory cache,
        Uniswap.Position memory primary,
        uint128 primaryLiquidity
    ) private returns (Uniswap.Position memory) {
        {
            // Exit primary Uniswap position
            (, , uint256 earned0, uint256 earned1) = primary.withdraw(primaryLiquidity);
            _earmarkSomeForMaintenance(earned0, earned1);
        }

        // Compute amounts that should be placed in new Uniswap position
        uint256 balance0 = _balance0();
        uint256 balance1 = _balance1();
        uint24 w = _computeNextPositionWidth(volatilityOracle.estimate24H(UNI_POOL, cache.sqrtPriceX96, cache.tick));
        w = w >> 1;
        (, uint256 amount0, uint256 amount1) = _computeMagicAmounts(
            silo0.balanceOf(address(this)) + balance0, // inventory0
            silo1.balanceOf(address(this)) + balance1, // inventory1
            cache.priceX96,
            w
        );

        // Withdraw enough to create primary position
        if (balance0 < amount0) silo0.delegate_withdraw(amount0 - balance0);
        if (balance1 < amount1) silo1.delegate_withdraw(amount1 - balance1);

        // Update primary position's ticks
        primary.lower = TickMath.floor(cache.tick - int24(w), TICK_SPACING);
        primary.upper = TickMath.ceil(cache.tick + int24(w), TICK_SPACING);
        if (primary.lower < TickMath.MIN_TICK) primary.lower = TickMath.MIN_TICK;
        if (primary.upper > TickMath.MAX_TICK) primary.upper = TickMath.MAX_TICK;

        // Place some liquidity in Uniswap
        (amount0, amount1) = primary.deposit(primary.liquidityForAmounts(cache.sqrtPriceX96, amount0, amount1));

        // Place excess into silos
        if (balance0 > amount0) silo0.delegate_deposit(balance0 - amount0);
        if (balance1 > amount1) silo1.delegate_deposit(balance1 - amount1);

        emit Recenter(primary.lower, primary.upper);
        return primary;
    }

    function _rewardCaller(
        address _rewardToken,
        uint64 _rebalanceCount,
        uint32 _urgency,
        uint32 _gas
    ) private {
        // Short-circuit if the caller has decided to be benevolent
        if (_rewardToken == address(0)) {
            emit Reward(address(0), 0, _urgency);
            return;
        }

        // Otherwise, do math
        unchecked {
            uint256 rewardPerGas = rewardPerGasAverages[_rewardToken];
            _gas = uint32(21000 + _gas - gasleft());
            uint256 reward = FullMath.mulDiv(rewardPerGas * _gas, _urgency, 100_000);

            if (_rewardToken == address(TOKEN0)) {
                uint256 budget = maintenanceBudget0;
                if (reward > budget || rewardPerGas == 0) reward = budget;
                rewardPerGas = reward / _gas;

                budget -= reward;
                uint256 maxBudget = K * rewardPerGas * block.gaslimit;
                maintenanceBudget0 = budget > maxBudget ? maxBudget : budget;
            } else if (_rewardToken == address(TOKEN1)) {
                uint256 budget = maintenanceBudget1;
                if (reward > budget || rewardPerGas == 0) reward = budget;
                rewardPerGas = reward / _gas;

                budget -= reward;
                uint256 maxBudget = K * rewardPerGas * block.gaslimit;
                maintenanceBudget1 = budget > maxBudget ? maxBudget : budget;
            } else {
                uint256 budget = IERC20(_rewardToken).balanceOf(address(this));
                if (reward > budget || rewardPerGas == 0) reward = budget;
                rewardPerGas = reward / _gas;
            }

            IERC20(_rewardToken).safeTransfer(msg.sender, reward);
            pushRewardPerGas(_rewardToken, rewardPerGas, _rebalanceCount);
            emit Reward(_rewardToken, reward, _urgency);
        }
    }

    /// @dev Withdraws fraction of liquidity from Uniswap, but collects *all* fees
    function _withdrawFractionFromUniswap(uint256 numerator, uint256 denominator)
        private
        returns (uint256 amount0, uint256 amount1)
    {
        assert(numerator < denominator);

        // Read Uniswap positions from storage
        (Uniswap.Position memory primary, Uniswap.Position memory limit, , ) = _loadPackedSlot();

        uint128 liquidity;
        uint256 earned0;
        uint256 earned1;

        // Primary position
        (liquidity, , , , ) = primary.info();
        (amount0, amount1, earned0, earned1) = primary.withdraw(
            uint128(FullMath.mulDiv(liquidity, numerator, denominator))
        );
        (earned0, earned1) = _earmarkSomeForMaintenance(earned0, earned1);
        // --> Report the proper share of earned fees
        amount0 += FullMath.mulDiv(earned0, numerator, denominator);
        amount1 += FullMath.mulDiv(earned1, numerator, denominator);

        // Limit order
        if (limit.lower != limit.upper) {
            (liquidity, , , , ) = limit.info();
            // Fees earned by the limit order are negligible. We ignore them to save gas, and
            // reuse earned0 & earned1 variables rather than creating temp0 & temp1
            (earned0, earned1, , ) = limit.withdraw(uint128(FullMath.mulDiv(liquidity, numerator, denominator)));
            // --> Add to amounts from primary position
            amount0 += earned0;
            amount1 += earned1;
        }
    }

    /// @dev Earmark some earned fees for maintenance, according to `maintenanceFee`. Return what's leftover
    function _earmarkSomeForMaintenance(uint256 _earned0, uint256 _earned1) private returns (uint256, uint256) {
        uint256 toMaintenance;

        unchecked {
            // Accrue token0
            toMaintenance = _earned0 / MAINTENANCE_FEE;
            _earned0 -= toMaintenance;
            maintenanceBudget0 += toMaintenance;
            // Accrue token1
            toMaintenance = _earned1 / MAINTENANCE_FEE;
            _earned1 -= toMaintenance;
            maintenanceBudget1 += toMaintenance;
        }

        return (_earned0, _earned1);
    }

    function pushRewardPerGas(
        address _token,
        uint256 _rewardPerGas,
        uint64 _rebalanceCount
    ) private {
        uint256[10] storage rewardPerGasArray = rewardPerGasArrays[_token];
        unchecked {
            uint8 idx = uint8(_rebalanceCount % 10);
            _rewardPerGas /= 10;
            rewardPerGasAverages[_token] = rewardPerGasAverages[_token] + _rewardPerGas - rewardPerGasArray[idx];
            rewardPerGasArray[idx] = _rewardPerGas;
        }
    }

    function _unlockAndStorePackedSlot(
        Uniswap.Position memory _primary,
        Uniswap.Position memory _limit,
        uint64 _rebalanceCount,
        uint48 _recenterTimestamp
    ) private {
        packedSlot = PackedSlot(
            _primary.lower,
            _primary.upper,
            _limit.lower,
            _limit.upper,
            _rebalanceCount,
            _recenterTimestamp,
            false
        );
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    /// @dev TODO
    // ✅
    function _loadPackedSlot()
        private
        view
        returns (
            Uniswap.Position memory,
            Uniswap.Position memory,
            uint64,
            uint48
        )
    {
        PackedSlot memory _packedSlot = packedSlot;
        require(!_packedSlot.locked);
        return (
            Uniswap.Position(UNI_POOL, _packedSlot.primaryLower, _packedSlot.primaryUpper),
            Uniswap.Position(UNI_POOL, _packedSlot.limitLower, _packedSlot.limitUpper),
            _packedSlot.rebalanceCount,
            _packedSlot.recenterTimestamp
        );
    }

    /// @inheritdoc IAloeBlendDerivedState
    function getRebalanceUrgency() public view returns (uint32 urgency) {
        urgency = _computeRebalanceUrgency(packedSlot.recenterTimestamp);
    }

    /// @dev TODO
    function _computeRebalanceUrgency(uint48 _recenterTimestamp) private view returns (uint32 urgency) {
        urgency = uint32(FullMath.mulDiv(100_000, block.timestamp - _recenterTimestamp, RECENTERING_INTERVAL));
    }

    /// @inheritdoc IAloeBlendDerivedState
    function getInventory() public view returns (uint256 inventory0, uint256 inventory1) {
        (Uniswap.Position memory primary, Uniswap.Position memory limit, , ) = _loadPackedSlot();
        (uint160 sqrtPriceX96, , , , , , ) = UNI_POOL.slot0();
        (inventory0, inventory1, ) = _getInventory(primary, limit, sqrtPriceX96);
    }

    struct InventoryDetails {
        uint256 fluid0;
        uint256 fluid1;
        uint128 primaryLiquidity;
        uint128 limitLiquidity;
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
            InventoryDetails memory d
        )
    {
        (d.fluid0, d.fluid1, d.limitLiquidity) = _limit.collectableAmountsAsOfLastPoke(_sqrtPriceX96);
        // Everything in silos + everything in the contract, except maintenance budget
        d.fluid0 += silo0.balanceOf(address(this)) + _balance0();
        d.fluid1 += silo1.balanceOf(address(this)) + _balance1();
        // Everything in primary Uniswap position. Limit order is placed without moving this, so its
        // amounts don't get added to fluid.
        (inventory0, inventory1, d.primaryLiquidity) = _primary.collectableAmountsAsOfLastPoke(_sqrtPriceX96);
        inventory0 += d.fluid0;
        inventory1 += d.fluid1;
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
