const hre = require("hardhat");
const { artifacts } = require("hardhat");
const { Address, BN } = require("ethereumjs-util");

const VolatilityOracle = artifacts.require("VolatilityOracle");
const IUniswapV3Pool = artifacts.require("IUniswapV3Pool");

ORACLE_ADDRESS = "0x0000000000f0021d219C5AE2Fd5b261966012Dd7";

async function pokeOracle(poolAddresses, gasPrice) {
  const oracle = await VolatilityOracle.at(ORACLE_ADDRESS);
  
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);
  let nonce = await web3.eth.getTransactionCount(deployer.address);

  let promises = [];

  for (let poolAddress of poolAddresses) {
    promises.push(
      oracle.estimate24H(poolAddress, {
        from: deployer.address,
        gasLimit: 400000,
        gasPrice: gasPrice,
        nonce: nonce,
        type: "0x0",
      })
    );
    nonce += 1;
  }

  await Promise.all(promises);
}

async function increaseOracleCardinality(poolAddress, gasPrice) {
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);
  const nonce = await web3.eth.getTransactionCount(deployer.address);

  const pool = await IUniswapV3Pool.at(poolAddress);
  // 1 observation per block, 1 block every ~13 seconds on mainnet. 1 hour = 276
  const cardinality = 300;

  const receipt = await pool.increaseObservationCardinalityNext(cardinality, {
    from: deployer.address,
    gasLimit: 7000000,
    gasPrice: gasPrice,
    nonce: nonce,
    type: "0x0",
  });
  console.log(receipt);
}

const UNI_ETH_030 = "0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801";
const USDC_ETH_030 = "0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8";
const USDC_ETH_005 = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640";
const WBTC_ETH_005 = "0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0";
const FEI_TRIBE_005 = "0x4Eb91340079712550055F648e0984655F3683107";
const DAI_USDC_001 = "0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168";
const WETH_LOOKS_030 = "0x4b5Ab61593A2401B1075b90c04cBCDD3F87CE011";
const X2Y2_WETH_030 = "0x52cfA6bF6659175FcE27a23AbdEe798897Fe4c04";
const RAI_WETH_030 = "0x14DE8287AdC90f0f95Bf567C0707670de52e3813";

// increaseOracleCardinality(RAI_WETH_030, 42e9);
// pokeOracle([
//   UNI_ETH_030,
//   USDC_ETH_030,
//   USDC_ETH_005,
//   WBTC_ETH_005,
//   FEI_TRIBE_005,
//   DAI_USDC_001
// ], 80e9);
