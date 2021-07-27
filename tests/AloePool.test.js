const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
const { artifacts } = require("hardhat");

const { Address, BN } = require("ethereumjs-util");
const Big = require("big.js");

const AloePool = artifacts.require("AloePoolCapped");
const AloePredictions = artifacts.require("AloePredictions");
const ERC20 = artifacts.require("ERC20");

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

describe("Pool Contract Test @hardhat", function () {
  let accounts;
  let multisig;
  let pool;
  let token0;
  let token1;

  const Q32DENOM = 2 ** 32;
  const UINT256MAX =
    "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
  const ADDRESS_PREDICTIONS = "0x263C5BDFe39c48aDdE8362DC0Ec2BbD770A09c3a";
  const WHALE = "0x4F868C1aa37fCf307ab38D215382e88FCA6275E2";
  const ALOE_HOLDER = "0x29C3059F2F160A3f23D3e30c8dCc81aFEeD8509F";

  it("should deploy pool", async () => {
    accounts = await web3.eth.getAccounts();
    multisig = accounts[0]; // process.env.MULTISIG

    const mainDeployer = web3.eth.accounts.privateKeyToAccount(
      process.env.OTHER_DEPLOYER
    );

    pool = await AloePool.new(ADDRESS_PREDICTIONS, multisig, {
      from: mainDeployer.address
    });
    token0 = await ERC20.at(await pool.TOKEN0());
    token1 = await ERC20.at(await pool.TOKEN1());
  });

  it("should get reserves (0)", async () => {
    const reserves = await pool.getReserves();

    expect(reserves.reserve0.toString(10)).to.equal("0");
    expect(reserves.reserve1.toString(10)).to.equal("0");
  });

  // it("should not rebalance without assets", async () => {
  //   const tx = await pool.rebalance();
  //   console.log(tx.receipt);
  //   // await expect(txn).to.eventually.be.rejectedWith(
  //   //   Error,
  //   //   "VM Exception while processing transaction: revert Transfer blocked"
  //   // );
  // });

  it("should impersonate whale", async () => {
    await web3.eth.hardhat.impersonate(WHALE);

    const balance0 = await token0.balanceOf(WHALE);
    const balance1 = await token1.balanceOf(WHALE);

    expect(balance0.gt(2000e6)).to.be.true;
    expect(balance1.gt(1e18)).to.be.true;
  });

  it("should hit deposit cap", async () => {
    const tx0 = await token0.approve(pool.address, UINT256MAX, { from: WHALE });
    const tx1 = await token1.approve(pool.address, UINT256MAX, { from: WHALE });
    expect(tx0.receipt.status).to.be.true;
    expect(tx1.receipt.status).to.be.true;

    const tx2 = pool.deposit("100000000", "100000000000000000", 0, 0, {
      from: WHALE,
    });
    await expect(tx2).to.eventually.be.rejectedWith(
      Error,
      "VM Exception while processing transaction: revert Aloe: Pool already full"
    );
  });

  it("should raise deposit cap", async () => {
    const tx0 = await pool.setMaxTotalSupply("100000000000000000000", {
      from: multisig,
    });
    expect(tx0.receipt.status).to.be.true;
  });

  it("should deposit", async () => {
    const tx0 = await pool.deposit("100000000", "50000000000000000", 0, 0, {
      from: WHALE,
    });
    const deposit = tx0.logs[3];
    expect(deposit.event).to.equal("Deposit");
    expect(deposit.args.sender).to.equal(WHALE);
    expect(deposit.args.shares.toString(10)).to.equal("50000000000000000");
    expect(deposit.args.amount0.toString(10)).to.equal("100000000");
    expect(deposit.args.amount1.toString(10)).to.equal("50000000000000000");
  });

  it("should deposit proportionally", async () => {
    const tx0 = await pool.deposit("100000000", "55555555555555555", 0, 0, {
      from: WHALE,
    });
    const deposit = tx0.logs[3];
    expect(deposit.event).to.equal("Deposit");
    expect(deposit.args.sender).to.equal(WHALE);
    expect(deposit.args.shares.toString(10)).to.equal("50000000000000000");
    expect(deposit.args.amount0.toString(10)).to.equal("100000000");
    expect(deposit.args.amount1.toString(10)).to.equal("50000000000000000");
  });

  it("should rebalance", async () => {
    const tx0 = await pool.rebalance();
    console.log(`Rebalance gas: ${tx0.receipt.gasUsed}`);
  });

  it("should get next target bounds", async () => {
    const ticks = await pool.getNextElasticTicks();

    expect(ticks.lower.toString(10)).to.equal("199742");
    expect(ticks.upper.toString(10)).to.equal("199839");
  });

  it("should adjust target position", async () => {
    await web3.eth.hardhat.impersonate(ALOE_HOLDER);

    const predictions = await AloePredictions.at(ADDRESS_PREDICTIONS);
    const aloe = await ERC20.at(await predictions.ALOE());
    await aloe.approve(predictions.address, UINT256MAX, {
      from: ALOE_HOLDER,
    });

    const gt = await predictions.fetchGroundTruth();
    await predictions.submitProposal(
      Big(gt.bounds.lower).div(2).toFixed(0),
      Big(gt.bounds.upper).mul(2).toFixed(0),
      (1e18).toString(10),
      { from: ALOE_HOLDER }
    );
    await web3.eth.hardhat.increaseTime(3600);
    await predictions.advance();

    const ticks = await pool.getNextElasticTicks();

    expect(ticks.lower.toString(10)).to.equal("199742");
    expect(ticks.upper.toString(10)).to.equal("199839");
  });

  it("should rebalance", async () => {
    const tx0 = await pool.rebalance();
    console.log(`Rebalance gas: ${tx0.receipt.gasUsed}`);

    const token0Transfer = tx0.logs[4];
    const token1Transfer = tx0.logs[5];
    expect(token0Transfer.event).to.equal("Transfer");
    expect(token1Transfer.event).to.equal("Transfer");
    expect(token0Transfer.address).to.not.equal(token1Transfer.address);

    console.log(
      `Deposited ${token0Transfer.args.value.toString(10)} of ${
        token0Transfer.address
      } to main position`
    );
    console.log(
      `Deposited ${token1Transfer.args.value.toString(10)} of ${
        token1Transfer.address
      } to main position`
    );
  });

  it("should snipe", async () => {
    const tx0 = await pool.snipe();
    expect(tx0.receipt.status).to.be.true;
  });

  it("should withdraw", async () => {
    const tx0 = await pool.withdraw("100000000000000000", 0, 0, { from: WHALE });
    const withdraw = tx0.logs[5];
    expect(withdraw.event).to.equal('Withdraw');
    expect(withdraw.args.shares.toString(10)).to.equal("100000000000000000");
    expect(withdraw.args.amount0.toString(10)).to.equal("199999996");
    expect(withdraw.args.amount1.toString(10)).to.equal("99999999999978213");
    console.log(`Gas used for snipe: ${tx0.receipt.gasUsed}`);
  })
});
