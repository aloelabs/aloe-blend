// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./interfaces/IAloeBlend.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/ISilo.sol";
import "./interfaces/IVolatilityOracle.sol";

import "./helpers/BaseSplitCodeFactory.sol";

contract Factory is BaseSplitCodeFactory, IFactory {
    event CreateVault(IAloeBlend indexed vault);

    IVolatilityOracle public immutable volatilityOracle;

    mapping(IUniswapV3Pool => mapping(ISilo => mapping(ISilo => IAloeBlend))) public getVault;

    mapping(IAloeBlend => bool) public didCreateVault;

    constructor(IVolatilityOracle _volatilityOracle, bytes memory _creationCode) BaseSplitCodeFactory(_creationCode) {
        volatilityOracle = _volatilityOracle;
    }

    function createVault(
        IUniswapV3Pool pool,
        ISilo silo0,
        ISilo silo1
    ) external returns (IAloeBlend vault) {
        bytes memory constructorArgs = abi.encode(pool, silo0, silo1);
        bytes32 salt = keccak256(abi.encode(pool, silo0, silo1));
        vault = IAloeBlend(super._create(constructorArgs, salt));

        getVault[pool][silo0][silo1] = vault;
        didCreateVault[vault] = true;

        emit CreateVault(vault);
    }
}
