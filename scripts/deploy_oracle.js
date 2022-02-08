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

async function deploy(gasPrice) {
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);
  const nonce = await web3.eth.getTransactionCount(deployer.address);

  const oracle = await VolatilityOracle.new({
    from: deployer.address,
    gasLimit: 2100000,
    gasPrice: gasPrice,
    nonce: nonce,
    type: "0x0",
  });

  console.log(`Volatility Oracle deployed to ${oracle.address}`);
}

// preview();
// deploy(100e9);

