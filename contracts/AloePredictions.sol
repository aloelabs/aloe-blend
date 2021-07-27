// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./libraries/Equations.sol";
import "./libraries/FullMath.sol";
import "./libraries/Math.sol";
import "./libraries/TickMath.sol";
import "./libraries/UINT512.sol";

import "./interfaces/IAloePredictions.sol";

import "./AloePredictionsState.sol";
import "./IncentiveVault.sol";

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

uint256 constant TWO_144 = 2**144;
uint256 constant TWO_80 = 2**80;
uint256 constant SQRT_6 = 2449;

/// @title Aloe predictions market
/// @author Aloe Capital LLC
contract AloePredictions is AloePredictionsState, IAloePredictions {
    using SafeERC20 for IERC20;
    using UINT512Math for UINT512;

    /// @dev The number of standard deviations to +/- from the mean when computing ground truth bounds
    uint256 public constant GROUND_TRUTH_STDDEV_SCALE = 2;

    /// @dev The minimum length of an epoch, in seconds. Epochs may be longer if no one calls `advance`
    uint32 public constant EPOCH_LENGTH_SECONDS = 3600;

    /// @dev The ALOE token used for staking
    IERC20 public immutable ALOE;

    /// @dev The Uniswap pair for which predictions should be made
    IUniswapV3Pool public immutable UNI_POOL;

    /// @dev The incentive vault to use for staking extras and `advance()` reward
    IncentiveVault public immutable INCENTIVE_VAULT;

    /// @dev For reentrancy check
    bool private locked;

    modifier lock() {
        require(!locked, "Aloe: Locked");
        locked = true;
        _;
        locked = false;
    }

    constructor(
        IERC20 _ALOE,
        IUniswapV3Pool _UNI_POOL,
        IncentiveVault _INCENTIVE_VAULT
    ) AloePredictionsState() {
        ALOE = _ALOE;
        UNI_POOL = _UNI_POOL;
        INCENTIVE_VAULT = _INCENTIVE_VAULT;

        // Ensure we have an hour of data, assuming Uniswap interaction every 10 seconds
        _UNI_POOL.increaseObservationCardinalityNext(360);
    }

    /// @inheritdoc IAloePredictionsDerivedState
    function current()
        external
        view
        override
        returns (
            bool,
            uint176,
            uint128,
            uint128
        )
    {
        require(epoch != 0, "Aloe: No data yet");

        uint176 mean = computeMean();
        (uint256 lower, uint256 upper) = computeSemivariancesAbout(mean);
        return (
            didInvertPrices,
            mean,
            // Each proposal is a uniform distribution aiming to be `GROUND_TRUTH_STDDEV_SCALE` sigma wide.
            // So we have to apply a scaling factor (sqrt(6)) to make results more gaussian.
            uint128((Math.sqrt(lower) * SQRT_6) / (1000 * GROUND_TRUTH_STDDEV_SCALE)),
            uint128((Math.sqrt(upper) * SQRT_6) / (1000 * GROUND_TRUTH_STDDEV_SCALE))
        );
    }

    /// @inheritdoc IAloePredictionsDerivedState
    function epochExpectedEndTime() public view override returns (uint32) {
        unchecked {return epochStartTime + EPOCH_LENGTH_SECONDS;}
    }

    /// @inheritdoc IAloePredictionsActions
    function advance() external override lock {
        require(summaries[epoch].accumulators.stakeTotal != 0, "Aloe: No proposals with stake");
        require(uint32(block.timestamp) > epochExpectedEndTime(), "Aloe: Too early");
        epochStartTime = uint32(block.timestamp);

        if (epoch != 0) {
            (Bounds memory groundTruth, bool shouldInvertPricesNext) = fetchGroundTruth();
            emit FetchedGroundTruth(groundTruth.lower, groundTruth.upper, didInvertPrices);

            summaries[epoch - 1].groundTruth = groundTruth;
            didInvertPrices = shouldInvertPrices;
            shouldInvertPrices = shouldInvertPricesNext;

            _consolidateAccumulators(epoch - 1);
        }

        epoch++;
        INCENTIVE_VAULT.claimAdvanceIncentive(address(ALOE), msg.sender);
        emit Advanced(epoch, uint32(block.timestamp));
    }

    /// @inheritdoc IAloePredictionsActions
    function submitProposal(
        uint176 lower,
        uint176 upper,
        uint80 stake
    ) external override lock returns (uint40 key) {
        require(ALOE.transferFrom(msg.sender, address(this), stake), "Aloe: Provide ALOE");

        key = _submitProposal(stake, lower, upper);
        _organizeProposals(key, stake);

        emit ProposalSubmitted(msg.sender, epoch, key, lower, upper, stake);
    }

    /// @inheritdoc IAloePredictionsActions
    function updateProposal(
        uint40 key,
        uint176 lower,
        uint176 upper
    ) external override {
        _updateProposal(key, lower, upper);
        emit ProposalUpdated(msg.sender, epoch, key, lower, upper);
    }

    /// @inheritdoc IAloePredictionsActions
    function claimReward(uint40 key, address[] calldata extras) external override lock {
        Proposal storage proposal = proposals[key];
        require(proposal.upper != 0, "Aloe: Nothing to claim");

        EpochSummary storage summary = summaries[proposal.epoch];
        require(summary.groundTruth.upper != 0, "Aloe: Need ground truth");

        uint256 lowerError =
            proposal.lower > summary.groundTruth.lower
                ? proposal.lower - summary.groundTruth.lower
                : summary.groundTruth.lower - proposal.lower;
        uint256 upperError =
            proposal.upper > summary.groundTruth.upper
                ? proposal.upper - summary.groundTruth.upper
                : summary.groundTruth.upper - proposal.upper;
        uint256 stakeTotal = summary.accumulators.stakeTotal;

        UINT512 memory temp;

        // Compute reward numerator
        // --> Start with sum of all squared errors
        UINT512 memory numer = summary.accumulators.sumOfSquaredBounds;
        // --> Subtract current proposal's squared error
        (temp.LS, temp.MS) = FullMath.square512(lowerError);
        (numer.LS, numer.MS) = numer.sub(temp.LS, temp.MS);
        (temp.LS, temp.MS) = FullMath.square512(upperError);
        (numer.LS, numer.MS) = numer.sub(temp.LS, temp.MS);
        // --> Weight entire numerator by proposal's stake
        (numer.LS, numer.MS) = numer.muls(proposal.stake);

        UINT512 memory denom = summary.accumulators.sumOfSquaredBoundsWeighted;

        // Now our 4 key numbers are available: numerLS, numerMS, denomLS, denomMS
        uint256 reward;
        if (denom.MS == 0 && denom.LS == 0) {
            // In this case, only 1 proposal was submitted
            reward = proposal.stake;
        } else if (denom.MS == 0) {
            // If denominator MS is 0, then numerator MS is 0 as well.
            // This keeps things simple:
            reward = FullMath.mulDiv(stakeTotal, numer.LS, denom.LS);
        } else {
            if (numer.LS != 0) {
                reward = 257 + FullMath.log2floor(denom.MS) - FullMath.log2floor(numer.LS);
                reward = reward < 80 ? stakeTotal / (2**reward) : 0;
            }
            if (numer.MS != 0) {
                reward += FullMath.mulDiv(
                    stakeTotal,
                    TWO_80 * numer.MS,
                    TWO_80 * denom.MS + FullMath.mulDiv(TWO_80, denom.LS, type(uint256).max)
                );
            }
        }

        require(ALOE.transfer(proposal.source, reward), "Aloe: failed to reward");
        if (extras.length != 0)
            INCENTIVE_VAULT.claimStakingIncentives(key, extras, proposal.source, uint80(reward), uint80(stakeTotal));
        emit ClaimedReward(proposal.source, proposal.epoch, key, uint80(reward));
        delete proposals[key];
    }

    /// @inheritdoc IAloePredictionsDerivedState
    function computeMean() public view override returns (uint176 mean) {
        Accumulators memory accumulators = summaries[epoch - 1].accumulators;

        uint256 denominator = accumulators.stake0thMomentRaw;
        // It's more gas efficient to read from memory copy
        uint40[NUM_PROPOSALS_TO_AGGREGATE] memory keysToAggregate = highestStakeKeys[(epoch - 1) % 2];

        unchecked {
            for (uint40 i = 0; i < NUM_PROPOSALS_TO_AGGREGATE && i < accumulators.proposalCount; i++) {
                Proposal storage proposal = proposals[keysToAggregate[i]];

                // These fit in uint176, using uint256 to avoid phantom overflow later on
                uint256 proposalCenter = (uint256(proposal.lower) + uint256(proposal.upper)) >> 1;
                uint256 proposalSpread = proposal.upper - proposal.lower;

                mean += uint176(FullMath.mulDiv(uint256(proposal.stake) * proposalSpread, proposalCenter, denominator));
            }
        }
    }

    /// @inheritdoc IAloePredictionsDerivedState
    function computeSemivariancesAbout(uint176 center) public view override returns (uint256 lower, uint256 upper) {
        Accumulators memory accumulators = summaries[epoch - 1].accumulators;

        uint256 denominator = 3 * accumulators.stake0thMomentRaw;
        uint256 x;
        uint256 y;
        // It's more gas efficient to read from memory copy
        uint40[NUM_PROPOSALS_TO_AGGREGATE] memory keysToAggregate = highestStakeKeys[(epoch - 1) % 2];

        unchecked {
            for (uint40 i = 0; i < NUM_PROPOSALS_TO_AGGREGATE && i < accumulators.proposalCount; i++) {
                Proposal storage proposal = proposals[keysToAggregate[i]];

                if (proposal.upper < center) {
                    // Proposal is entirely below the center
                    x = center - proposal.upper;
                    y = center - proposal.lower;
                    if (x > type(uint128).max) x = type(uint128).max;
                    if (y > type(uint128).max) y = type(uint128).max;

                    lower += uint176(
                        FullMath.mulDiv(
                            uint256(proposal.stake) * uint256(proposal.upper - proposal.lower),
                            x**2 + x * y + y**2,
                            denominator
                        )
                    );
                } else if (proposal.lower < center) {
                    // Proposal includes the center
                    x = proposal.upper - center;
                    y = center - proposal.lower;
                    if (x > type(uint128).max) x = type(uint128).max;
                    if (y > type(uint128).max) y = type(uint128).max;

                    lower += uint176(FullMath.mulDiv(uint256(proposal.stake) * y, y**2, denominator));
                    upper += uint176(FullMath.mulDiv(uint256(proposal.stake) * x, x**2, denominator));
                } else {
                    // Proposal is entirely above the center
                    x = proposal.upper - center;
                    y = proposal.lower - center;
                    if (x > type(uint128).max) x = type(uint128).max;
                    if (y > type(uint128).max) y = type(uint128).max;

                    upper += uint176(
                        FullMath.mulDiv(
                            uint256(proposal.stake) * uint256(proposal.upper - proposal.lower),
                            x**2 + x * y + y**2,
                            denominator
                        )
                    );
                }
            }
        }
    }

    /// @inheritdoc IAloePredictionsDerivedState
    function fetchGroundTruth() public view override returns (Bounds memory bounds, bool shouldInvertPricesNext) {
        (int56[] memory tickCumulatives, ) = UNI_POOL.observe(selectedOracleTimetable());
        uint176 mean = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[9] - tickCumulatives[0]) / 3240));
        shouldInvertPricesNext = mean < TWO_80;

        // After accounting for possible inversion, compute mean price over the entire 54 minute period
        if (didInvertPrices) mean = type(uint160).max / mean;
        mean = uint176(FullMath.mulDiv(mean, mean, TWO_144));

        // stat will take on a few different statistical values
        // Here it's MAD (Mean Absolute Deviation), except not yet divided by number of samples
        uint184 stat;
        uint176 sample;

        for (uint8 i = 0; i < 9; i++) {
            sample = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[i + 1] - tickCumulatives[i]) / 360));

            // After accounting for possible inversion, compute mean price over a 6 minute period
            if (didInvertPrices) sample = type(uint160).max / sample;
            sample = uint176(FullMath.mulDiv(sample, sample, TWO_144));

            // Accumulate
            stat += sample > mean ? sample - mean : mean - sample;
        }

        // MAD = stat / n, here n = 10
        // STDDEV = MAD * sqrt(2/pi) for a normal distribution
        // We want bounds to be +/- G*stddev, so we have an additional factor of G here
        stat = uint176((uint256(stat) * GROUND_TRUTH_STDDEV_SCALE * 79788) / 1000000);
        // Compute mean +/- stat, but be careful not to overflow
        bounds.lower = mean > stat ? uint176(mean - stat) : 0;
        bounds.upper = uint184(mean) + stat > type(uint176).max ? type(uint176).max : uint176(mean + stat);
    }

    /// @inheritdoc IAloePredictionsDerivedState
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
}
