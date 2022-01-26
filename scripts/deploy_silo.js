const hre = require("hardhat");
const { artifacts } = require("hardhat");
const { Address, BN } = require("ethereumjs-util");

const CompoundCEtherSilo = artifacts.require("CompoundCEtherSilo");
const CompoundCTokenSilo = artifacts.require("CompoundCTokenSilo");
const FuseFEtherSilo = artifacts.require("FuseFEtherSilo");
const FuseFTokenSilo = artifacts.require("FuseFTokenSilo");

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

const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);
params = {
  from: deployer.address,
  gasLimit: (2000000).toFixed(0),
  gasPrice: 85e9,
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
