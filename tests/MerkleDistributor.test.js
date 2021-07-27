const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
const { artifacts } = require("hardhat");

const { Address, BN } = require("ethereumjs-util");

const Factory = artifacts.require("Factory");
const preALOE = artifacts.require("preALOE");
const MerkleDistributor = artifacts.require("MerkleDistributor");

chai.use(chaiAsPromised);
const expect = chai.expect;

web3.eth.extend({
  property: "hardhat",
  methods: [
    {
      name: "increaseTime",
      call: "evm_increaseTime",
      params: 1,
    },
    {
      name: "mine",
      call: "evm_mine",
      params: 0,
    },
    {
      name: "impersonate",
      call: "hardhat_impersonateAccount",
      params: 1,
    },
    {
      name: "stopImpersonating",
      call: "hardhat_stopImpersonatingAccount",
      params: 1,
    },
  ],
});

const generatedMerkleTree = require("../scripts/merkle_result.json");

describe("Merkle Distributor Test @hardhat", function () {
  let accounts;
  let multisig;
  let factory;
  let merkle;
  let aloe;

  const UNI_FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984";

  it("should deploy protocol", async () => {
    accounts = await web3.eth.getAccounts();
    multisig = accounts[2]; // process.env.MULTISIG

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

    factory = await Factory.new(aloeContractAddress, UNI_FACTORY, multisig, {
      from: mainDeployer.address,
    });
    merkle = await MerkleDistributor.new(
      aloeContractAddress,
      generatedMerkleTree.merkleRoot,
      { from: mainDeployer.address }
    );
    aloe = await preALOE.new(factory.address, multisig, merkle.address, {
      from: aloeDeployer.address,
    });

    expect(aloeContractAddress).to.equal(aloe.address);
  });

  it("should allow winners to claim airdrop", async () => {
    const promises = [];
    const amounts = [];

    Object.entries(generatedMerkleTree.claims).forEach(async (entry) => {
      const address = entry[0];
      const info = entry[1];

      promises.push(merkle.claim(info.index, address, info.amount, info.proof));
      amounts.push(info.amount.slice(2));
    });

    const txns = await Promise.all(promises);
    txns.forEach((txn, i) => {
      const aloeTransferEvent = txn.receipt.rawLogs[0];
      expect(aloeTransferEvent.address).to.equal(aloe.address);

      let amount = aloeTransferEvent.data;
      amount = amount.slice(-amounts[i].length);
      expect(amount).to.equal(amounts[i]);
    });
  });

  it("should recognize that winners have claimed airdrop", async () => {
    const promises = [];

    Object.entries(generatedMerkleTree.claims).forEach(async (entry) => {
      promises.push(merkle.isClaimed(entry[1].index))
    });

    const claimStatuses = await Promise.all(promises);
    claimStatuses.forEach((claimStatus) => {
      expect(claimStatus).to.be.true;
    });
  });

  it("should not allow arbitrary transfers", async () => {
    const claim = Object.entries(generatedMerkleTree.claims)[0];
    web3.eth.hardhat.impersonate(claim[0]);

    await web3.eth.sendTransaction({
      from: accounts[1],
      to: claim[0],
      value: "150000000000000000",
    });

    const txn = aloe.transfer(factory.address, 1, { from: claim[0] });
    await expect(txn).to.eventually.be.rejectedWith(
      Error,
      "VM Exception while processing transaction: revert Transfer blocked"
    );
    web3.eth.hardhat.stopImpersonating(claim[0])
  })
});
