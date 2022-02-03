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
const FEI_TRIBE_005 = "0x4Eb91340079712550055F648e0984655F3683107";
const WBTC_ETH_005 = "0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0";

// createVault(
//   FEI_TRIBE_005,
//   "0x0770D239e56d96bC1E049B94949B0a0199B77cf6",
//   "0x2A9855dc8AFa59E6067287B8aa15cd009938d137",
//   80e9
// );
// createVault(
//   WBTC_ETH_005,
//   "0xdA2D30c659cFEb176053B22Be11fc351e077FDc0",
//   "0x8f43969d04ba8aAeC7C69813a07A276189c574D2",
//   80e9
// );
