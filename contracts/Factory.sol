// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./AloePredictions.sol";
import "./IncentiveVault.sol";

contract Factory is IncentiveVault {
    /// @dev The ALOE token used for staking
    address public immutable ALOE;

    /// @dev The Uniswap factory
    IUniswapV3Factory public immutable UNI_FACTORY;

    /// @dev A mapping from [token A][token B][fee tier] to Aloe predictions market. Note
    /// that order of token A/B doesn't matter
    mapping(address => mapping(address => mapping(uint24 => address))) public getMarket;

    /// @dev A mapping that indicates which addresses are Aloe predictions markets
    mapping(address => bool) public doesMarketExist;

    constructor(
        address _ALOE,
        IUniswapV3Factory _UNI_FACTORY,
        address _multisig
    ) IncentiveVault(_multisig) {
        ALOE = _ALOE;
        UNI_FACTORY = _UNI_FACTORY;
    }

    function createMarket(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address market) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        market = deploy(token0, token1, fee);

        doesMarketExist[market] = true;
        // Populate mapping such that token order doesn't matter
        getMarket[token0][token1][fee] = market;
        getMarket[token1][token0][fee] = market;
    }

    function deploy(
        address token0,
        address token1,
        uint24 fee
    ) private returns (address market) {
        IUniswapV3Pool pool = IUniswapV3Pool(UNI_FACTORY.getPool(token0, token1, fee));
        require(address(pool) != address(0), "Uni pool missing");

        market = address(
            new AloePredictions{salt: keccak256(abi.encode(token0, token1, fee))}(
                IERC20(ALOE),
                pool,
                IncentiveVault(address(this))
            )
        );
    }
}
