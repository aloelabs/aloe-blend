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

    /// @inheritdoc IAloeBlendImmutables
    uint24 public constant RECENTERING_INTERVAL = 24 hours; // aim to recenter once per day

    /// @inheritdoc IAloeBlendImmutables
    uint24 public constant MIN_WIDTH = 402; // 1% of inventory in primary Uniswap position

    /// @inheritdoc IAloeBlendImmutables
    uint24 public constant MAX_WIDTH = 27728; // 50% of inventory in primary Uniswap position

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
        // The primary position's lower tick bound
        int24 primaryLower;
        // The primary position's upper tick bound
        int24 primaryUpper;
        // The limit order's lower tick bound
        int24 limitLower;
        // The limit order's upper tick bound
        int24 limitUpper;
        // The `block.timestamp` from the last time the primary position moved
        uint48 recenterTimestamp;
        // Whether `maintenanceBudget0` or `maintenanceBudget1` is filled up
        bool maintenanceIsSustainable;
        // Whether the vault is currently locked to reentrancy
        bool locked;
    }

    /// @inheritdoc IAloeBlendState
    PackedSlot public packedSlot;

    /// @inheritdoc IAloeBlendState
    uint256 public silo0Basis;

    /// @inheritdoc IAloeBlendState
    uint256 public silo1Basis;

    /// @inheritdoc IAloeBlendState
    uint256 public maintenanceBudget0;

    /// @inheritdoc IAloeBlendState
    uint256 public maintenanceBudget1;

    /// @inheritdoc IAloeBlendState
    mapping(address => uint256) public gasPrices;

    /// @dev Stores 14 samples of the gas price for each token, scaled by 1e4 and divided by 14. The sum over each
    /// array is equal to the value reported by `gasPrices`
    mapping(address => uint256[14]) private gasPriceArrays;

    /// @dev The index of `gasPriceArrays[address]` in which the next gas price measurement will be stored
    mapping(address => uint8) private gasPriceIdxs;

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
    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 amount0, uint256 amount1) {
        require(shares != 0, "Aloe: 0 shares");
        // Reentrancy guard is embedded in `_loadPackedSlot` to save gas
        (Uniswap.Position memory primary, Uniswap.Position memory limit, , ) = _loadPackedSlot();
        packedSlot.locked = true;

        // Poke silos to ensure reported balances are correct
        silo0.delegate_poke();
        silo1.delegate_poke();

        uint256 _totalSupply = totalSupply;
        uint256 a;
        uint256 b;
        uint256 c;
        uint256 d;

        // Compute user's portion of token0 from contract + silo0
        c = _balance0();
        a = silo0Basis;
        b = silo0.balanceOf(address(this));
        a = b > a ? (b - a) / MAINTENANCE_FEE : 0; // interest / MAINTENANCE_FEE
        amount0 = FullMath.mulDiv(c + b - a, shares, _totalSupply);
        // Withdraw from silo0 if contract balance can't cover what user is owed
        if (amount0 > c) {
            c = a + amount0 - c;
            silo0.delegate_withdraw(c);
            maintenanceBudget0 += a;
            silo0Basis = b - c;
        }

        // Compute user's portion of token1 from contract + silo1
        c = _balance1();
        a = silo1Basis;
        b = silo1.balanceOf(address(this));
        a = b > a ? (b - a) / MAINTENANCE_FEE : 0; // interest / MAINTENANCE_FEE
        amount1 = FullMath.mulDiv(c + b - a, shares, _totalSupply);
        // Withdraw from silo1 if contract balance can't cover what user is owed
        if (amount1 > c) {
            c = a + amount1 - c;
            silo1.delegate_withdraw(c);
            maintenanceBudget1 += a;
            silo1Basis = b - c;
        }

        // Withdraw user's portion of the primary position
        {
            (uint128 liquidity, , , , ) = primary.info();
            (a, b, c, d) = primary.withdraw(uint128(FullMath.mulDiv(liquidity, shares, _totalSupply)));
            amount0 += a;
            amount1 += b;
            a = c / MAINTENANCE_FEE;
            b = d / MAINTENANCE_FEE;
            amount0 += FullMath.mulDiv(c - a, shares, _totalSupply);
            amount1 += FullMath.mulDiv(d - b, shares, _totalSupply);
            maintenanceBudget0 += a;
            maintenanceBudget1 += b;
        }

        // Withdraw user's portion of the limit order
        if (limit.lower != limit.upper) {
            (uint128 liquidity, , , , ) = limit.info();
            (a, b, c, d) = limit.withdraw(uint128(FullMath.mulDiv(liquidity, shares, _totalSupply)));
            amount0 += a + FullMath.mulDiv(c, shares, _totalSupply);
            amount1 += b + FullMath.mulDiv(d, shares, _totalSupply);
        }

        // Check constraints
        require(amount0 >= amount0Min, "Aloe: amount0 too low");
        require(amount1 >= amount1Min, "Aloe: amount1 too low");

        // Transfer tokens
        TOKEN0.safeTransfer(msg.sender, amount0);
        TOKEN1.safeTransfer(msg.sender, amount1);

        // Burn shares
        _burn(msg.sender, shares);
        emit Withdraw(msg.sender, shares, amount0, amount1);
        packedSlot.locked = false;
    }

    struct RebalanceCache {
        uint160 sqrtPriceX96;
        uint96 magic;
        int24 tick;
        uint24 w;
        uint32 urgency;
        uint224 priceX96;
    }

    /// @inheritdoc IAloeBlendActions
    function rebalance(address rewardToken) external {
        uint32 gasStart = uint32(gasleft());
        // Reentrancy guard is embedded in `_loadPackedSlot` to save gas
        (
            Uniswap.Position memory primary,
            Uniswap.Position memory limit,
            uint48 recenterTimestamp,
            bool maintenanceIsSustainable
        ) = _loadPackedSlot();
        packedSlot.locked = true;

        RebalanceCache memory cache;
        (cache.sqrtPriceX96, cache.tick, , , , , ) = UNI_POOL.slot0();
        cache.priceX96 = uint224(FullMath.mulDiv(cache.sqrtPriceX96, cache.sqrtPriceX96, Q96));
        // Get rebalance urgency (based on time elapsed since previous rebalance)
        cache.urgency = _getRebalanceUrgency(recenterTimestamp);

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
            // Attempt to sell token1 for token0. Place a limit order below the active range
            limit.upper = TickMath.floor(cache.tick, TICK_SPACING);
            limit.lower = limit.upper - TICK_SPACING;
            // Choose amount1 such that ratio will be 50/50 once the limit order is pushed through. Division by 2
            // works for small tickSpacing. Also have to constrain to fluid1 since we're not yet withdrawing from
            // primary Uniswap position.
            uint256 amount1 = (inventory1 - FullMath.mulDiv(inventory0, cache.priceX96, Q96)) >> 1;
            if (amount1 > d.fluid1) amount1 = d.fluid1;
            // Withdraw requisite amount from silo
            uint256 balance1 = _balance1();
            if (balance1 < amount1) silo1.delegate_withdraw(amount1 - balance1);
            // Deposit to new limit order and store bounds
            limit.deposit(limit.liquidityForAmount1(amount1));
        } else if (ratio > 5100) {
            // Attempt to sell token0 for token1. Place a limit order above the active range
            limit.lower = TickMath.ceil(cache.tick, TICK_SPACING);
            limit.upper = limit.lower + TICK_SPACING;
            // Choose amount0 such that ratio will be 50/50 once the limit order is pushed through. Division by 2
            // works for small tickSpacing. Also have to constrain to fluid0 since we're not yet withdrawing from
            // primary Uniswap position.
            uint256 amount0 = (inventory0 - FullMath.mulDiv(inventory1, Q96, cache.priceX96)) >> 1;
            if (amount0 > d.fluid0) amount0 = d.fluid0;
            // Withdraw requisite amount from silo
            uint256 balance0 = _balance0();
            if (balance0 < amount0) silo0.delegate_withdraw(amount0 - balance0);
            // Deposit to new limit order and store bounds
            limit.deposit(limit.liquidityForAmount0(amount0));
        } else {
            recenter(cache, primary, inventory0, inventory1);
            recenterTimestamp = uint48(block.timestamp);
        }

        // Poke primary position and withdraw fees so that maintenance budget can grow
        {
            (, , uint256 earned0, uint256 earned1) = primary.withdraw(0);
            _earmarkSomeForMaintenance(earned0, earned1);
        }

        _rewardCaller(rewardToken, cache.urgency, gasStart);

        emit Rebalance(cache.urgency, ratio, totalSupply, inventory0, inventory1);
        _unlockAndStorePackedSlot(primary, limit, recenterTimestamp, maintenanceIsSustainable);
    }

    function recenter(
        RebalanceCache memory _cache,
        Uniswap.Position memory _primary,
        uint256 _inventory0,
        uint256 _inventory1
    ) private returns (Uniswap.Position memory) {
        uint256 sigma = volatilityOracle.estimate24H(UNI_POOL, _cache.sqrtPriceX96, _cache.tick);
        _cache.w = _computeNextPositionWidth(sigma);

        // Exit primary Uniswap position
        {
            (uint128 liquidity, , , , ) = _primary.info();
            (, , uint256 earned0, uint256 earned1) = _primary.withdraw(liquidity);
            _earmarkSomeForMaintenance(earned0, earned1);
        }

        // Compute amounts that should be placed in new Uniswap position
        uint256 amount0;
        uint256 amount1;
        _cache.w = _cache.w >> 1;
        (_cache.magic, amount0, amount1) = _computeMagicAmounts(_inventory0, _inventory1, _cache.priceX96, _cache.w);

        uint256 balance0 = _balance0();
        uint256 balance1 = _balance1();
        bool hasExcessToken0 = balance0 > amount0;
        bool hasExcessToken1 = balance1 > amount1;

        // Because of cToken exchangeRate rounding, we may withdraw too much
        // here. That's okay; dust will just sit in contract till next rebalance
        if (!hasExcessToken0) silo0.delegate_withdraw(amount0 - balance0);
        if (!hasExcessToken1) silo1.delegate_withdraw(amount1 - balance1);

        // Update primary position's ticks
        _primary.lower = TickMath.floor(_cache.tick - int24(_cache.w), TICK_SPACING);
        _primary.upper = TickMath.ceil(_cache.tick + int24(_cache.w), TICK_SPACING);
        if (_primary.lower < TickMath.MIN_TICK) _primary.lower = TickMath.MIN_TICK;
        if (_primary.upper > TickMath.MAX_TICK) _primary.upper = TickMath.MAX_TICK;

        // Place some liquidity in Uniswap
        (amount0, amount1) = _primary.deposit(_primary.liquidityForAmounts(_cache.sqrtPriceX96, amount0, amount1));

        // Place excess into silos
        if (hasExcessToken0) silo0.delegate_deposit(balance0 - amount0);
        if (hasExcessToken1) silo1.delegate_deposit(balance1 - amount1);

        emit Recenter(_primary.lower, _primary.upper, _cache.magic);
        return _primary;
    }

    function _rewardCaller(
        address _rewardToken,
        uint32 _urgency,
        uint32 _gas
    ) private returns (bool maintenanceIsSustainable) {
        // Short-circuit if the caller doesn't want to be rewarded
        if (_rewardToken == address(0)) {
            emit Reward(address(0), 0, _urgency);
            return false;
        }

        // Otherwise, do math
        uint256 rewardPerGas = gasPrices[_rewardToken]; // extra factor of 1e4
        _gas = uint32(21000 + _gas - gasleft());
        uint256 reward = FullMath.mulDiv(rewardPerGas * _gas, _urgency, 1e9);

        if (_rewardToken == address(TOKEN0)) {
            uint256 budget = maintenanceBudget0;
            if (reward > budget || rewardPerGas == 0) reward = budget;
            budget -= reward;

            uint256 maxBudget = FullMath.mulDiv(rewardPerGas * K, block.gaslimit, 1e4);
            maintenanceIsSustainable = budget > maxBudget;
            maintenanceBudget0 = maintenanceIsSustainable ? maxBudget : budget;
        } else if (_rewardToken == address(TOKEN1)) {
            uint256 budget = maintenanceBudget1;
            if (reward > budget || rewardPerGas == 0) reward = budget;
            budget -= reward;

            uint256 maxBudget = FullMath.mulDiv(rewardPerGas * K, block.gaslimit, 1e4);
            maintenanceIsSustainable = budget > maxBudget;
            maintenanceBudget1 = maintenanceIsSustainable ? maxBudget : budget;
        } else {
            uint256 budget = IERC20(_rewardToken).balanceOf(address(this));
            if (reward > budget || rewardPerGas == 0) reward = budget;

            require(silo0.shouldAllowRemovalOf(_rewardToken) && silo1.shouldAllowRemovalOf(_rewardToken));
        }

        IERC20(_rewardToken).safeTransfer(msg.sender, reward);
        _pushGasPrice(_rewardToken, FullMath.mulDiv(1e4, reward, _gas));
        emit Reward(_rewardToken, reward, _urgency);
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

    function _silo0Withdraw(uint256 _amount) private returns (uint256) {
        unchecked {
            uint256 a = silo0Basis;
            uint256 b = silo0.balanceOf(address(this));
            a = b > a ? (b - a) / MAINTENANCE_FEE : 0; // interest / MAINTENANCE_FEE

            if (_amount > b - a) _amount = b - a;

            silo0.delegate_withdraw(a + _amount);
            maintenanceBudget0 += a;
            silo0Basis = b - a - _amount;

            return _amount;
        }
    }

    function _silo1Withdraw(uint256 _amount) private returns (uint256) {
        unchecked {
            uint256 a = silo1Basis;
            uint256 b = silo1.balanceOf(address(this));
            a = b > a ? (b - a) / MAINTENANCE_FEE : 0; // interest / MAINTENANCE_FEE

            if (_amount > b - a) _amount = b - a;

            silo1.delegate_withdraw(a + _amount);
            maintenanceBudget1 += a;
            silo1Basis = b - a - _amount;

            return _amount;
        }
    }

    /**
     * @dev Assumes that `_gasPrice` represents the fair value of 1e4 units of gas, denominated in `_token`.
     * Updates the contract's gas price oracle accordingly, including incrementing the array index.
     * @param _token The ERC20 token for which average gas price should be updated
     * @param _gasPrice The amount of `_token` necessary to incentivize expenditure of 1e4 units of gas
     */
    function _pushGasPrice(address _token, uint256 _gasPrice) private {
        uint256[14] storage array = gasPriceArrays[_token];
        uint8 idx = gasPriceIdxs[_token];
        unchecked {
            _gasPrice /= 14;
            gasPrices[_token] = gasPrices[_token] + _gasPrice - array[idx];
            array[idx] = _gasPrice;
            gasPriceIdxs[_token] = (idx + 1) % 14;
        }
    }

    function _unlockAndStorePackedSlot(
        Uniswap.Position memory _primary,
        Uniswap.Position memory _limit,
        uint48 _recenterTimestamp,
        bool _maintenanceIsSustainable
    ) private {
        packedSlot = PackedSlot(
            _primary.lower,
            _primary.upper,
            _limit.lower,
            _limit.upper,
            _recenterTimestamp,
            _maintenanceIsSustainable,
            false
        );
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    /// @dev TODO
    function _loadPackedSlot()
        private
        view
        returns (
            Uniswap.Position memory,
            Uniswap.Position memory,
            uint48,
            bool
        )
    {
        PackedSlot memory _packedSlot = packedSlot;
        require(!_packedSlot.locked);
        return (
            Uniswap.Position(UNI_POOL, _packedSlot.primaryLower, _packedSlot.primaryUpper),
            Uniswap.Position(UNI_POOL, _packedSlot.limitLower, _packedSlot.limitUpper),
            _packedSlot.recenterTimestamp,
            _packedSlot.maintenanceIsSustainable
        );
    }

    /// @inheritdoc IAloeBlendDerivedState
    function getRebalanceUrgency() public view returns (uint32 urgency) {
        urgency = _getRebalanceUrgency(packedSlot.recenterTimestamp);
    }

    /**
     * @notice Reports how badly the vault wants its `rebalance()` function to be called. Proportional to time
     * elapsed since the primary position last moved.
     * @dev Since `RECENTERING_INTERVAL` is 86400 seconds, urgency is guaranteed to be nonzero unless the primary
     * position is moved more than once in a single block.
     * @param _recenterTimestamp The `block.timestamp` from the last time the primary position moved
     * @return urgency How badly the vault wants its `rebalance()` function to be called
     */
    function _getRebalanceUrgency(uint48 _recenterTimestamp) private view returns (uint32 urgency) {
        urgency = uint32(FullMath.mulDiv(100_000, block.timestamp - _recenterTimestamp, RECENTERING_INTERVAL));
    }

    /// @inheritdoc IAloeBlendDerivedState
    function getInventory() public view returns (uint256 inventory0, uint256 inventory1) {
        (Uniswap.Position memory primary, Uniswap.Position memory limit, , ) = _loadPackedSlot();
        (uint160 sqrtPriceX96, , , , , , ) = UNI_POOL.slot0();
        (inventory0, inventory1, ) = _getInventory(primary, limit, sqrtPriceX96);
    }

    struct InventoryDetails {
        // The amount of token0 available to limit order, i.e. everything *not* in the primary position
        uint256 fluid0;
        // The amount of token1 available to limit order, i.e. everything *not* in the primary position
        uint256 fluid1;
        // The liquidity present in the primary position. Note that this may be higher than what the
        // vault deposited since someone may designate this contract as a `mint()` recipient
        uint128 primaryLiquidity;
        // The liquidity present in the limit order. Note that this may be higher than what the
        // vault deposited since someone may designate this contract as a `mint()` recipient
        uint128 limitLiquidity;
    }

    /**
     * @notice Estimate's the vault's liabilities to users -- in other words, how much would be paid out if all
     * holders redeemed their LP tokens at once.
     * @dev Underestimates the true payout unless both silos and Uniswap positions have just been poked. Also
     * assumes that the maximum amount will accrue to the maintenance budget during the next `rebalance()`. If
     * it takes less than that for the budget to reach capacity, then the values reported here may increase after
     * calling `rebalance()`.
     * @param _primary The primary position
     * @param _limit The limit order; if inactive, `_limit.lower` should equal `_limit.upper`
     * @param _sqrtPriceX96 The current sqrt(price) of the Uniswap pair from `slot0()`
     * @return inventory0 The amount of token0 underlying all LP tokens
     * @return inventory1 The amount of token1 underlying all LP tokens
     * @return d A struct containing details that may be relevant to other functions. We return it here to avoid
     * reloading things from external storage (saves gas).
     */
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
        uint256 a;
        uint256 b;

        // Limit order
        if (_limit.lower != _limit.upper) {
            (d.limitLiquidity, , , a, b) = _limit.info();
            (d.fluid0, d.fluid1) = _limit.amountsForLiquidity(_sqrtPriceX96, d.limitLiquidity);
            // Earnings from limit order don't get added to maintenance budget
            d.fluid0 += a;
            d.fluid1 += b;
        }

        // token0 from contract + silo0
        a = silo0Basis;
        b = silo0.balanceOf(address(this));
        a = b > a ? (b - a) / MAINTENANCE_FEE : 0; // interest / MAINTENANCE_FEE
        d.fluid0 += _balance0() + b - a;

        // token1 from contract + silo1
        a = silo1Basis;
        b = silo1.balanceOf(address(this));
        a = b > a ? (b - a) / MAINTENANCE_FEE : 0; // interest / MAINTENANCE_FEE
        d.fluid1 += _balance1() + b - a;

        // Primary position; limit order is placed without touching this, so its amounts aren't included in `fluid`
        if (_primary.lower != _primary.upper) {
            (d.primaryLiquidity, , , a, b) = _primary.info();
            (inventory0, inventory1) = _primary.amountsForLiquidity(_sqrtPriceX96, d.primaryLiquidity);

            inventory0 += d.fluid0 + a - a / MAINTENANCE_FEE;
            inventory1 += d.fluid1 + b - b / MAINTENANCE_FEE;
        } else {
            inventory0 = d.fluid0;
            inventory1 = d.fluid1;
        }
    }

    /// @dev The amount of token0 in the contract that's not in maintenanceBudget0
    function _balance0() private view returns (uint256) {
        return TOKEN0.balanceOf(address(this)) - maintenanceBudget0;
    }

    /// @dev The amount of token1 in the contract that's not in maintenanceBudget1
    function _balance1() private view returns (uint256) {
        return TOKEN1.balanceOf(address(this)) - maintenanceBudget1;
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    /// @dev Computes position width based on volatility. Doesn't revert
    // ✅
    function _computeNextPositionWidth(uint256 _sigma) internal pure returns (uint24) {
        if (_sigma <= 1.00481445e16) return MIN_WIDTH;
        if (_sigma >= 4.41180492e17) return MAX_WIDTH;
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
