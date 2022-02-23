const hre = require("hardhat");
const { artifacts } = require("hardhat");
const { Address, BN } = require("ethereumjs-util");

const CompoundCEtherSilo = artifacts.require("CompoundCEtherSilo");
const CompoundCTokenSilo = artifacts.require("CompoundCTokenSilo");
const FuseFEtherSilo = artifacts.require("FuseFEtherSilo");
const FuseFTokenSilo = artifacts.require("FuseFTokenSilo");
const FuseIncentivizedSilo = artifacts.require("FuseIncentivizedSilo");
const YearnSilo = artifacts.require("YearnSilo");

async function deployCEtherSilo(cEtherAddress, p) {
  const silo = await CompoundCEtherSilo.new(cEtherAddress, p);
  console.log(`CEther Silo deployed to ${silo.address}`);
}

async function deployCTokenSilo(cTokenAddress, p) {
  const silo = await CompoundCTokenSilo.new(cTokenAddress, p);
  console.log(`CToken Silo deployed to ${silo.address}`);
}

async function deployFuseFEtherSilo(fEtherAddress, p) {
  const silo = await FuseFEtherSilo.new(fEtherAddress, p);
  console.log(`FEther Silo deployed to ${silo.address}`);
}

async function deployFuseFTokenSilo(fTokenAddress, p) {
  const silo = await FuseFTokenSilo.new(fTokenAddress, p);
  console.log(`FToken Silo deployed to ${silo.address}`);
}

async function deployFuseIncentivizedSilo(fTokenAddress, p) {
  const silo = await FuseIncentivizedSilo.new(fTokenAddress, p);
  console.log(`Fuse Incentivized Silo deployed to ${silo.address}`);
}

async function deployYearnSilo(yvTokenAddress, p) {
  const silo = await YearnSilo.new(yvTokenAddress, 1, p);
  console.log(`Yearn Silo deployed to ${silo.address}`);
}

const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);
params = {
  from: deployer.address,
  gasLimit: (1200000).toFixed(0),
  gasPrice: 80e9,
  type: "0x0",
};

// const CETH = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
// deployCEtherSilo(CETH, params);

// const CUSDC = "0x39AA39c021dfbaE8faC545936693aC917d5E7563";
// deployCTokenSilo(CUSDC, params);

// const FETH8 = "0xbB025D470162CC5eA24daF7d4566064EE7f5F111" // Fuse Pool 8 (comptroller: 0xc54172e34046c1653d1920d40333Dd358c7a1aF4)
// deployFuseFEtherSilo(FETH8, params);

// const FDAI8 = "0x7e9cE3CAa9910cc048590801e64174957Ed41d43"; // Fuse Pool 8 (comptroller: 0xc54172e34046c1653d1920d40333Dd358c7a1aF4)
// deployFuseFTokenSilo(FDAI8, params)

// const FFEI8 = "0xd8553552f8868C1Ef160eEdf031cF0BCf9686945"; // Fuse Pool 8 (comptroller: 0xc54172e34046c1653d1920d40333Dd358c7a1aF4)
// deployFuseFTokenSilo(FFEI8, params);

// const FTRIBE8 = "0xFd3300A9a74b3250F1b2AbC12B47611171910b07"; // Fuse Pool 8 (comptroller: 0xc54172e34046c1653d1920d40333Dd358c7a1aF4)
// deployFuseIncentivizedSilo(FTRIBE8, params);

// const yvWBTC = "0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E";
// deployYearnSilo(yvWBTC, params);

// const yvWETH = "0xa258C4606Ca8206D8aA700cE2143D7db854D168c";
// deployYearnSilo(yvWETH, params);