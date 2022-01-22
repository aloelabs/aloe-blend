const hre = require("hardhat");
const { artifacts } = require("hardhat");
const { Address, BN } = require("ethereumjs-util");

const VolatilityOracle = artifacts.require("VolatilityOracle");
const IUniswapV3Pool = artifacts.require("IUniswapV3Pool");

async function preview() {
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);

  const deployerNonce = await web3.eth.getTransactionCount(deployer.address);
  const contractAddress = web3.utils.toChecksumAddress(
    Address.generate(Address.fromString(deployer.address), new BN(deployerNonce)).toString()
  );

  const requiredGas = await VolatilityOracle.new.estimateGas({
    from: deployer.address,
  });

  console.log(`Deploying from ${deployer.address} to ${contractAddress}. Using ${requiredGas} gas`);
}

async function deploy() {
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);

  const oracle = await VolatilityOracle.new({
    from: deployer.address,
  });

  console.log(`Volatility Oracle deployed to ${oracle.address}`);
}

async function increaseOracleCardinality(poolAddress) {
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);

  const pool = await IUniswapV3Pool.at(poolAddress);
  // 1 observation per block, 1 block every ~13 seconds on mainnet. 1 hour = 276
  const cardinality = 300;

  // const requiredGas = await pool.increaseObservationCardinalityNext.estimateGas(cardinality, {
  //   from: deployer.address,
  //   gasPrice: 85e9,
  //   type: "0x0",
  // });
  const requiredGas = 7000000;
  console.log(requiredGas);

  await pool.increaseObservationCardinalityNext(cardinality, {
    from: deployer.address,
    gasLimit: (requiredGas * 1.1).toFixed(0),
    gasPrice: 85e9,
    nonce: 4,
    type: "0x0",
  });
}

// preview();
// deploy();

// const UNI_ETH_030 = "0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801";
// const USDC_ETH_005 = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640";
// const WBTC_ETH_005 = "0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0";
// const FEI_TRIBE_005 = "0x4Eb91340079712550055F648e0984655F3683107";
// const DAI_USDC_001 = "0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168";
// increaseOracleCardinality(DAI_USDC_001);
