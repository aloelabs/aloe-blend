# Aloe Blend

[![dapptools](https://github.com/aloelabs/aloe-blend/actions/workflows/dapptools.yml/badge.svg?branch=master)](https://github.com/aloelabs/aloe-blend/actions/workflows/dapptools.yml)

This repository contains the core smart contracts for the Aloe Blend Protocol.

## Bug bounty

This repository will soon be part of an Immunefi bug bounty program.

## Disclaimer

This is experimental software and is provided on an "as is" and "as available" basis. We **do not give any warranties** and **will not be liable for any loss incurred** through any use of this codebase.

## Environment

This repository is set up to work with both [Hardhat](https://hardhat.org/) and [dapptools](https://dapp.tools/).
Most tests rely on dapptools, but it's easier to get started with Hardhat:

```bash
yarn install
yarn build-hh
yarn test-hh
```

If you prefer dapptools, follow the instructions [here](https://github.com/dapphub/dapptools#installation) to
install it. Once that's done, you can run the following:

```bash
yarn install
yarn build-dapp
yarn test-dapp
```

If things aren't working, make sure you populate a `.env` file as shown in [.env.template](.env.template)

## Contracts

```
AloeBlend -- "Holds and manages assets for a single Uniswap pair"
Factory -- "Coming soon"
VolatilityOracle -- "Oracle that computes implied volatility for any Uniswap pair"

interfaces
|-- IAloeBlend -- "Describes user-facing functions of the vault"
|-- IFactory -- "Describes user-facing functions of the factory"
|-- ISilo -- "Prescribes functions that every silo must have"
|-- IVolatilityOracle -- "Describes user-facing functions of the volatility oracle"
libraries
|-- FixedPoint96
|-- FixedPoint128
|-- FullMath -- "Allows for full precision uint256 multiplication"
|-- LiquidityAmounts -- "Translates liquidity to amounts or vice versa"
|-- Oracle -- "Helps with low-level queries to Uniswap oracles"
|-- Silo -- "Helps delegatecall to the silos a vault is using"
|-- TickMath -- "Translates ticks to prices or vice versa"
|-- Uniswap -- "Improves readability of Uniswap interactions"
|-- Volatility -- "Computes implied volatility from observed swap fee earnings"
silos
|-- CompoundCEtherSilo -- "A silo for WETH that earns interest from Compound (cETH)"
|-- CompoundCTokenSilo -- "A silo that works with a number of tokens by depositing to Compound (cTokens)"
|-- FuseFEtherSilo -- "A silo for WETH that earns interest from a Fuse pool (fETH)"
|-- FuseFTokenSilo -- "A silo that works with a number of tokens by depositing to a Fuse pool (fTokens)"
```

## Documentation

Code comments and natspec should be considered the primary source of truth regarding this code. That said,
additional documentation is available at [docs.aloe.capital](https://docs.aloe.capital).
