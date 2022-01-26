const hre = require("hardhat");
const { artifacts } = require("hardhat");
const { Address, BN } = require("ethereumjs-util");

const Factory = artifacts.require("Factory");

const dapptoolsJSON = require("../build_dapp/dapp.sol.json");
const aloeBlendContractBuildData = dapptoolsJSON["contracts"]["contracts/AloeBlend.sol"]["AloeBlend"];
const bytecode = aloeBlendContractBuildData["evm"]["bytecode"]["object"];

async function preview(volatilityOracleAddress) {
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);

  const nonce = await web3.eth.getTransactionCount(deployer.address);
  const contractAddress = web3.utils.toChecksumAddress(
    Address.generate(Address.fromString(deployer.address), new BN(nonce)).toString()
  );

  const requiredGas = await Factory.new.estimateGas(volatilityOracleAddress, `0x${bytecode}`, {
    from: deployer.address,
  });

  console.log(`Deploying from ${deployer.address} to ${contractAddress}. Using ${requiredGas} gas`);
}

async function deploy(volatilityOracleAddress) {
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);

  const factory = await Factory.new(volatilityOracleAddress, `0x${bytecode}`, {
    from: deployer.address,
    gasLimit: 7000000,
    gasPrice: 90e9,
    type: "0x0",
  });

  console.log(`Factory deployed to ${factory.address}`);
}

// preview("0x00000000007476b17d4ae5919ce21f34eE456261");
deploy("0x00000000007476b17d4ae5919ce21f34eE456261");

// const UNI_ETH_030 = "0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801";
// const USDC_ETH_005 = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640";
// const WBTC_ETH_005 = "0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0";
// const FEI_TRIBE_005 = "0x4Eb91340079712550055F648e0984655F3683107";
// const DAI_USDC_001 = "0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168";
