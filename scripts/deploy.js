const hre = require("hardhat");
const { artifacts } = require("hardhat");

const AloeBlend = artifacts.require("AloeBlendCapped");

const ADDRESS_UNI_POOL = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640";
const ADDRESS_CTOKEN0 = "0x39AA39c021dfbaE8faC545936693aC917d5E7563";
const ADDRESS_CTOKEN1 = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
const MULTISIG = process.env.MULTISIG;

async function deploy() {
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);

  requiredGas = await AloeBlend.new.estimateGas(ADDRESS_UNI_POOL, ADDRESS_CTOKEN0, ADDRESS_CTOKEN1, MULTISIG, {
    from: deployer.address,
  });

  console.log(`Deploying from ${deployer.address}. Using ${requiredGas} gas`);
  aloeBlend = await AloeBlend.new(ADDRESS_UNI_POOL, ADDRESS_CTOKEN0, ADDRESS_CTOKEN1, MULTISIG, {
    from: deployer.address,
  });

  console.log(`ALOEBLEND deployed to ${aloeBlend.address}`);
  console.log(`\tparams: ${ADDRESS_UNI_POOL} ${ADDRESS_CTOKEN0} ${ADDRESS_CTOKEN1} ${MULTISIG}`);
}

deploy();
