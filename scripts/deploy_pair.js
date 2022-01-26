const hre = require("hardhat");
const { artifacts } = require("hardhat");
const { Address, BN } = require("ethereumjs-util");

const Factory = artifacts.require("Factory");

FACTORY_ADDRESS = "0x80444b8de99bf73Fae91D6e39bc7c79e9d41bFfA";

async function createVault(pairAddress, silo0Address, silo1Address, gasPrice) {
  const factory = await Factory.at(FACTORY_ADDRESS);

  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);
  const nonce = await web3.eth.getTransactionCount(deployer.address);

  await factory.createVault(pairAddress, silo0Address, silo1Address, {
    from: deployer.address,
    gasLimit: 6000000,
    gasPrice: gasPrice,
    nonce: nonce,
    type: "0x0",
  });
}

const USDC_ETH_005 = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640";
const DAI_USDC_001 = "0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168";

const ethSilo = "0xbA9aD27Ed23b5E002e831514E69554815a5820b3";
const usdcSilo = "0x723bFE564661536FDFfa3E9e060135928d3bf18F";
const daiSilo = "0x1F8095A26586abB27874Dd53a12a3AF25226DcB0";

// createVault(USDC_ETH_005, usdcSilo, ethSilo, 85e9);
// createVault(DAI_USDC_001, daiSilo, usdcSilo, 85e9);
