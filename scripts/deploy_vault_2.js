const hre = require("hardhat");
const { artifacts } = require("hardhat");

const AloeBlend = artifacts.require("AloeBlendCapped");
const FuseFEtherSilo = artifacts.require("FuseFEtherSilo");
const OlympusStakingSilo = artifacts.require("OlympusStakingSilo");
const IUniswapV3Pool = artifacts.require("IUniswapV3Pool");

const ADDRESS_UNI_POOL = "0xF1B63cD9d80f922514c04b0fD0a30373316dd75b";
const ADDRESS_STAKING = "0xFd31c7d00Ca47653c6Ce64Af53c1571f9C36566a";
const ADDRESS_FETH = "0xFA1057d02A0C1a4885851e3F4fD496Ee7D38F56e";
const MULTISIG = process.env.MULTISIG;

async function deploy() {
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);

  silo0 = await OlympusStakingSilo.new(ADDRESS_STAKING, {
    from: deployer.address,
  });
  silo1 = await FuseFEtherSilo.new(ADDRESS_FETH, {
    from: deployer.address,
  });

  aloeBlend = await AloeBlend.new(
    ADDRESS_UNI_POOL,
    silo0.address,
    silo1.address,
    MULTISIG,
    {
      from: deployer.address,
    }
  );

  console.log(`Aloe Blend deployed to ${aloeBlend.address}`);
  console.log(`\tparams: ${ADDRESS_UNI_POOL} ${silo0.address} ${silo1.address} ${MULTISIG}`);
}

async function increaseOracleCardinality() {
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);

  const pool = await IUniswapV3Pool.at(ADDRESS_UNI_POOL);
  const cardinality = 36;

  requiredGas = await pool.increaseObservationCardinalityNext.estimateGas(cardinality, { from: deployer.address });
  console.log(requiredGas);

  await pool.increaseObservationCardinalityNext(cardinality, {
    from: deployer.address,
    gasLimit: (requiredGas * 1.1).toFixed(0),
    gasPrice: 60000000000,
    type: "0x0",
  });
}

deploy();
// increaseOracleCardinality();