const { Address, BN } = require("ethereumjs-util");

const hre = require("hardhat");
const { artifacts } = require("hardhat");

const Factory = artifacts.require("Factory");
const preALOE = artifacts.require("preALOE");
const MerkleDistributor = artifacts.require("MerkleDistributor");
const AloePredictions = artifacts.require("AloePredictions");
const AloePool = artifacts.require("AloePoolCapped");

const generatedMerkleTree = require("./merkle_result.json");

const ADDRESS_UNI_FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
const ADDRESS_USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const ADDRESS_WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const MULTISIG = process.env.MULTISIG;

async function deployProtocol() {
  const mainDeployer = web3.eth.accounts.privateKeyToAccount(
    process.env.OTHER_DEPLOYER
  );
  const aloeDeployer = web3.eth.accounts.privateKeyToAccount(
    process.env.ALOE_DEPLOYER
  );
  const aloeDeployerNonce = await web3.eth.getTransactionCount(
    aloeDeployer.address
  );
  const aloeContractAddress = web3.utils.toChecksumAddress(
    Address.generate(
      Address.fromString(aloeDeployer.address),
      new BN(aloeDeployerNonce)
    ).toString()
  );

  const factory = await Factory.new(
    aloeContractAddress,
    ADDRESS_UNI_FACTORY,
    MULTISIG,
    { from: mainDeployer.address }
  );
  console.log(`FACTORY deployed to ${factory.address}`);
  console.log(
    `\tparams: ${aloeContractAddress} ${ADDRESS_UNI_FACTORY} ${MULTISIG}`
  );

  const merkle = await MerkleDistributor.new(
    aloeContractAddress,
    generatedMerkleTree.merkleRoot,
    { from: mainDeployer.address }
  );
  console.log(`MERKLEDISTRIBUTOR deployed to ${merkle.address}`);
  console.log(
    `\tparams: ${aloeContractAddress} ${generatedMerkleTree.merkleRoot}`
  );

  const aloe = await preALOE.new(factory.address, MULTISIG, merkle.address, {
    from: aloeDeployer.address,
  });
  console.log(`ALOE deployed to ${aloe.address}`);
  console.log(`\tparams: ${factory.address} ${MULTISIG} ${merkle.address}`);

  if (aloeContractAddress !== aloe.address) {
    console.error("ALOE didn't deploy to the expected address");
    process.exit();
  }

  return factory;
}

async function createUSDCETHMarket(factoryAddress, feeTier = 3000) {
  const factory = await Factory.at(factoryAddress);
  await factory.createMarket(ADDRESS_USDC, ADDRESS_WETH, feeTier);
  const predictions = await AloePredictions.at(
    await factory.getMarket(ADDRESS_USDC, ADDRESS_WETH, feeTier)
  );

  console.log(`USDC/ETH Predictions Market located at ${predictions.address}`);
}

async function createUSDCETHPool(predictionsMarketAddress) {
  const pool = await AloePool.new(predictionsMarketAddress, MULTISIG);

  console.log(`USDC/ETH Pool located at ${pool.address}`);
  console.log(`\tparams: ${predictionsMarketAddress} ${MULTISIG}`);
}

async function deployPredictionsFactory(aloeAddress) {
  const mainDeployer = web3.eth.accounts.privateKeyToAccount(
    process.env.OTHER_DEPLOYER
  );
  const factory = await Factory.new(
    aloeAddress,
    ADDRESS_UNI_FACTORY,
    MULTISIG,
    { from: mainDeployer.address }
  );
  console.log(`FACTORY deployed to ${factory.address}`);
  console.log(`\tparams: ${aloeAddress} ${ADDRESS_UNI_FACTORY} ${MULTISIG}`);
}

// deployProtocol().then((factory) => createUSDCETHMarket(factory.address));
// createUSDCETHPool();

// deployPredictionsFactory("0xa10Ee8A7bFA188E762a7bc7169512222a621Fab4");
// createUSDCETHMarket("0xec0c69449dBc79CB3483FC3e3A4285C8A2D3dD45", 500);
// createUSDCETHPool("0x263C5BDFe39c48aDdE8362DC0Ec2BbD770A09c3a");
