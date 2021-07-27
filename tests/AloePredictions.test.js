const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
const { artifacts } = require("hardhat");

const { Address, BN } = require("ethereumjs-util");
const Big = require("big.js");

const Factory = artifacts.require("Factory");
const preALOE = artifacts.require("preALOE");
const MerkleDistributor = artifacts.require("MerkleDistributor");
const AloePredictions = artifacts.require("AloePredictions");

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
  ],
});

const generatedMerkleTree = require("../scripts/merkle_result.json");

describe("Predictions Contract Test @hardhat", function () {
  let accounts;
  let multisig;
  let factory;
  let merkle;
  let aloe;
  let predictions;

  const Q32DENOM = 2 ** 32;
  const UINT256MAX =
    "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
  const ADDRESS_UNI_FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
  const ADDRESS_USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const ADDRESS_WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

  it("should deploy protocol", async () => {
    accounts = await web3.eth.getAccounts();
    multisig = accounts[0]; // process.env.MULTISIG

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

    factory = await Factory.new(
      aloeContractAddress,
      ADDRESS_UNI_FACTORY,
      multisig,
      { from: mainDeployer.address }
    );
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

  it("should deploy predictions", async () => {
    const tx = await factory.createMarket(ADDRESS_USDC, ADDRESS_WETH, 3000);
    expect(tx.receipt.status).to.be.true;

    predictions = await AloePredictions.at(
      await factory.getMarket(ADDRESS_USDC, ADDRESS_WETH, 3000)
    );
    // expect(predictions.address).to.equal(
    //   "0xb648C50ABf64938ccD0E65E9F1bF1D5B489f34ca"
    // );
  });

  it("should give multisig 50000 ALOE", async () => {
    const balance = await aloe.balanceOf(multisig);
    expect(balance.toString(10)).to.equal("50000000000000000000000");
  });

  it("should approve contract", async () => {
    const tx = await aloe.approve(predictions.address, UINT256MAX, {
      from: multisig,
    });

    expect(tx.receipt.status).to.be.true;
    expect(tx.logs[0].event).to.equal("Approval");
  });

  it("shouldn't aggregate proposals without stake", async () => {
    await expect(
      predictions.submitProposal(40000 * Q32DENOM, 60000 * Q32DENOM, 0)
    ).to.eventually.be.rejected;
    await expect(
      predictions.submitProposal(30000 * Q32DENOM, 50000 * Q32DENOM, 0)
    ).to.eventually.be.rejected;
    await expect(predictions.computeMean()).to.eventually.be.rejected;
    await expect(predictions.computeSemivariancesAbout(0)).to.eventually.be
      .rejected;
    await expect(predictions.current()).to.eventually.be.rejected;
  });

  it("shouldn't advance without stake", async () => {
    await expect(predictions.advance()).to.eventually.be.rejected;
  });

  it("should aggregate 1 proposal with stake", async () => {
    const tx0 = await predictions.submitProposal(
      50000 * Q32DENOM,
      70000 * Q32DENOM,
      1
    );
    expect(tx0.receipt.status).to.be.true;
    await web3.eth.hardhat.increaseTime(3600);
    await predictions.advance();

    const mean = await predictions.computeMean();
    expect(mean.toString(10)).to.equal("257698037760000");

    const semivariances = await predictions.computeSemivariancesAbout(
      mean.toString(10)
    );
    const lower = semivariances.lower.toString(10);
    const upper = semivariances.upper.toString(10);
    expect(lower).to.equal("307445734561825860266666666");
    expect(upper).to.equal("307445734561825860266666666");
  });

  it("should aggregate 3 proposals with stake", async () => {
    const tx0 = await predictions.submitProposal(
      40000 * Q32DENOM,
      60000 * Q32DENOM,
      1000000000
    );
    const tx1 = await predictions.submitProposal(
      30000 * Q32DENOM,
      50000 * Q32DENOM,
      5000000000
    );
    const tx2 = await predictions.submitProposal(
      50000 * Q32DENOM,
      70000 * Q32DENOM,
      1
    );

    expect(tx0.receipt.status).to.be.true;
    expect(tx1.receipt.status).to.be.true;
    expect(tx2.receipt.status).to.be.true;
    await web3.eth.hardhat.increaseTime(3600);
    await predictions.advance();

    const mean = await predictions.computeMean();
    expect(mean.toString(10)).to.equal("178956970679789");

    let semivariances = await predictions.computeSemivariancesAbout(
      mean.toString(10)
    );
    let lower = semivariances.lower.toString(10);
    let upper = semivariances.upper.toString(10);
    expect(lower).to.equal("407080926571065155048030412");
    expect(upper).to.equal("464015322344766593402738844");
  });

  it("should aggregate 5 proposals with stake", async () => {
    const tx0 = await predictions.submitProposal(
      40000 * Q32DENOM,
      60000 * Q32DENOM,
      1000000000
    );
    const tx1 = await predictions.submitProposal(
      30000 * Q32DENOM,
      50000 * Q32DENOM,
      5000000000
    );
    const tx2 = await predictions.submitProposal(
      50000 * Q32DENOM,
      70000 * Q32DENOM,
      1
    );
    const tx3 = await predictions.submitProposal(
      2300 * Q32DENOM,
      2500 * Q32DENOM,
      1000000000000
    );
    const tx4 = await predictions.submitProposal(
      2800 * Q32DENOM,
      2900 * Q32DENOM,
      50000000000000
    );
    await web3.eth.hardhat.increaseTime(3600);
    await predictions.advance();

    expect(tx0.receipt.status).to.be.true;
    expect(tx1.receipt.status).to.be.true;
    expect(tx2.receipt.status).to.be.true;
    expect(tx3.receipt.status).to.be.true;
    expect(tx4.receipt.status).to.be.true;

    const mean = await predictions.computeMean();
    expect(mean.toString(10)).to.equal("15928515931373");

    let semivariances = await predictions.computeSemivariancesAbout(
      mean.toString(10)
    );
    let lower = semivariances.lower.toString(10);
    let upper = semivariances.upper.toString(10);
    expect(lower).to.equal("13986635468427976390142812");
    expect(upper).to.equal("619158796489719736008446879");

    semivariances = await predictions.computeSemivariancesAbout(2000);
    lower = semivariances.lower.toString(10);
    upper = semivariances.upper.toString(10);
    expect(lower).to.equal("0");
    expect(upper).to.equal("886863051670503170384662437");
  });

  it("should advance", async () => {
    const tx0 = await predictions.submitProposal(
      "117281240296106672259072",
      "175921860444160000000000",
      1000000000
    );
    await web3.eth.hardhat.increaseTime(3600);
    const tx1 = await predictions.advance();

    expect(tx0.receipt.status).to.be.true;
    expect(tx1.receipt.status).to.be.true;

    console.log(`Gas required to advance: ${tx0.receipt.gasUsed}`);

    const current = await predictions.current();
    const mean = current["1"];
    const sigmaL = current["2"];
    const sigmaU = current["3"];
    expect(current["0"]).to.be.false;

    expect(mean.toString(10)).to.equal("146601550370133336129536");
    expect(sigmaL.toString(10)).to.equal("14657223934668117970578");
    expect(sigmaU.toString(10)).to.equal("14657223934668117970578");
  });

  it("should update proposals", async () => {
    const tx0 = await predictions.submitProposal(2500, 75000, 1);
    const idx = tx0.logs[0].args.key.toNumber();

    const balance0 = await aloe.balanceOf(accounts[0]);
    const tx1 = await predictions.updateProposal(idx, 2500, 75000);
    const balance1 = await aloe.balanceOf(accounts[0]);
    const tx2 = await predictions.updateProposal(idx, 2500, 60000);
    const balance2 = await aloe.balanceOf(accounts[0]);

    console.log(`Gas required to update proposal: ${tx1.receipt.gasUsed}`);

    expect(tx0.receipt.status).to.be.true;
    expect(tx1.receipt.status).to.be.true;
    expect(tx2.receipt.status).to.be.true;

    // expect(balance1.addn(9).eq(balance0)).to.be.true;
    // expect(balance2.subn(5).eq(balance1)).to.be.true;
  });

  it("should submit proposals large enough to exceed uint256 accumulators", async () => {
    const tx0 = await predictions.submitProposal(
      "0xE0000000000000000000000000000000000000000000",
      "0xF0000000000000000000000000000000000000000000",
      "0xA604B9A42DF9CA00000"
    );
    expect(tx0.receipt.status).to.be.true;
  });

  it("should claim reward", async () => {
    await web3.eth.hardhat.increaseTime(3600);
    // Advance again to lock in the ground truth
    const tx0 = await predictions.advance();
    expect(tx0.receipt.status).to.be.true;

    console.log(`Gas required to advance: ${tx0.receipt.gasUsed}`);

    for (let i = 0; i < 5; i += 1) {
      const txi = await predictions.claimReward(i, []);
      expect(txi.receipt.status).to.be.true;

      console.log(`Gas required to claim reward: ${txi.receipt.gasUsed}`);
      console.log(`ALOE earned: ${txi.logs[0].args.amount.toString(10)}\n`);
    }
  });

  it("should claim reward again", async () => {
    await web3.eth.hardhat.increaseTime(3600);

    const tx0 = await predictions.submitProposal(0, 1, 1);
    expect(tx0.receipt.status).to.be.true;
    // Advance again to lock in the ground truth
    const tx1 = await predictions.advance();
    expect(tx1.receipt.status).to.be.true;

    for (let i = 5; i < 8; i += 1) {
      const txi = await predictions.claimReward(i, []);
      expect(txi.receipt.status).to.be.true;

      console.log(`Gas required to claim reward: ${txi.receipt.gasUsed}`);
      console.log(`ALOE earned: ${txi.logs[0].args.amount.toString(10)}\n`);
    }
  });

  it("should add many proposals", async () => {
    await web3.eth.hardhat.increaseTime(3600);

    let gasUsedFirst100 = [];
    let gasUsedAfter100 = [];

    for (let i = 0; i < 255; i++) {
      const tx0 = await predictions.submitProposal(
        10000000000,
        500000000000,
        Math.floor(100000 * Math.random())
      );

      if (i < 100) gasUsedFirst100.push(tx0.receipt.gasUsed);
      else gasUsedAfter100.push(tx0.receipt.gasUsed);
    }

    console.log(
      gasUsedFirst100.reduce((a, b) => a + b, 0) / gasUsedFirst100.length
    );
    console.log(
      gasUsedAfter100.reduce((a, b) => a + b, 0) / gasUsedAfter100.length
    );

    const tx1 = await predictions.advance();

    console.log(tx1.receipt.gasUsed);
  });

  it("should claim single proposal", async () => {
    await web3.eth.hardhat.increaseTime(3600);
    const tx0 = await predictions.submitProposal(
      10000000000,
      500000000000,
      Math.floor(100000 * Math.random())
    );
    const tx1 = await predictions.advance();
    await web3.eth.hardhat.increaseTime(3600);
    const tx2 = await predictions.submitProposal(
      10000000000,
      500000000000,
      Math.floor(100000 * Math.random())
    );
    const tx3 = await predictions.advance();
    const tx4 = await predictions.claimReward(tx0.logs[0].args.key, []);
  });

  it("should claim one big one tiny proposal", async () => {
    await web3.eth.hardhat.increaseTime(3600);
    const tx0 = await predictions.submitProposal(10000000000, 500000000000, 1);
    const tx1 = await predictions.submitProposal(
      10000000000,
      500000000000,
      "0x4B9A42DF9CA00000"
    );
    const tx2 = await predictions.advance();
    await web3.eth.hardhat.increaseTime(3600);
    const tx3 = await predictions.submitProposal(10000000000, 500000000000, 1);
    const tx4 = await predictions.advance();
    const tx5 = await predictions.claimReward(tx0.logs[0].args.key, []);
    const tx6 = await predictions.claimReward(tx1.logs[0].args.key, []);
  });

  it("should claim incentives", async () => {
    const tx0 = await factory.setStakingIncentive(
      predictions.address,
      aloe.address,
      "10000000000000000000",
      { from: multisig }
    );
    const tx1 = await factory.setAdvanceIncentive(
      predictions.address,
      aloe.address,
      "500000000000000000",
      { from: multisig }
    );

    await web3.eth.hardhat.increaseTime(3600);
    const tx2 = await predictions.submitProposal(10000000000, 500000000000, 10);

    const balance0 = await aloe.balanceOf(multisig);
    const tx3 = await predictions.advance();
    const balance1 = await aloe.balanceOf(multisig);

    await web3.eth.hardhat.increaseTime(3600);
    await predictions.submitProposal(10000000000, 500000000000, 10);
    await predictions.advance();

    const balance2 = await aloe.balanceOf(multisig);
    const tx4 = await predictions.claimReward(tx2.logs[0].args.key, [
      aloe.address,
    ]);
    const balance3 = await aloe.balanceOf(multisig);

    expect(balance1.sub(balance0).toString(10)).to.equal("500000000000000000");
    expect(balance3.sub(balance2).toString(10)).to.equal(
      "10000000000000000010"
    );
  });
});
