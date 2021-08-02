const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
const { artifacts } = require("hardhat");

const AloeBlend = artifacts.require("AloeBlendCapped");
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

const UINT256MAX = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

describe("Aloe Blend Contract Test @hardhat", () => {
  const ADDRESS_UNI_POOL = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640";
  const ADDRESS_CTOKEN0 = "0x39AA39c021dfbaE8faC545936693aC917d5E7563";
  const ADDRESS_CTOKEN1 = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
  const WHALE = "0x4F868C1aa37fCf307ab38D215382e88FCA6275E2";

  let accounts;
  let multisig;
  let aloeBlend;
  let token0;
  let token1;

  it("should deploy", async () => {
    accounts = await web3.eth.getAccounts();
    multisig = accounts[0];

    const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);

    aloeBlend = await AloeBlend.new(ADDRESS_UNI_POOL, ADDRESS_CTOKEN0, ADDRESS_CTOKEN1, multisig, {
      from: deployer.address,
    });
    token0 = await ERC20.at(await aloeBlend.TOKEN0());
    token1 = await ERC20.at(await aloeBlend.TOKEN1());
  });

  it("should get inventory (0)", async () => {
    const res = await aloeBlend.getInventory();

    expect(res.inventory0.toString(10)).to.equal("0");
    expect(res.inventory1.toString(10)).to.equal("0");
  });

  it("should impersonate whale", async () => {
    await web3.eth.hardhat.impersonate(WHALE);

    const balance0 = await token0.balanceOf(WHALE);
    const balance1 = await token1.balanceOf(WHALE);

    expect(balance0.gt(2000e6)).to.be.true;
    expect(balance1.gt(1e18)).to.be.true;
  });

  it("should hit deposit cap", async () => {
    const tx0 = await token0.approve(aloeBlend.address, UINT256MAX, {
      from: WHALE,
    });
    const tx1 = await token1.approve(aloeBlend.address, UINT256MAX, {
      from: WHALE,
    });
    expect(tx0.receipt.status).to.be.true;
    expect(tx1.receipt.status).to.be.true;

    const tx2 = aloeBlend.deposit("100000000", "100000000000000000", 0, 0, {
      from: WHALE,
    });
    await expect(tx2).to.eventually.be.rejectedWith(
      Error,
      "VM Exception while processing transaction: reverted with reason string 'Aloe: Vault already full'"
    );
  });

  it("should raise deposit cap", async () => {
    await aloeBlend.setMaxTotalSupply("100000000000000000000", {
      from: multisig,
    });
    const maxTotalSupply = await aloeBlend.maxTotalSupply();
    expect(maxTotalSupply.toString(10)).to.equal("100000000000000000000");
  });

  it("should deposit", async () => {
    const tx0 = await aloeBlend.deposit("100000000", "50000000000000000", 0, 0, {
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
    const tx0 = await aloeBlend.deposit("100000000", "55555555555555555", 0, 0, {
      from: WHALE,
    });
    const deposit = tx0.logs[3];
    expect(deposit.event).to.equal("Deposit");
    expect(deposit.args.sender).to.equal(WHALE);
    expect(deposit.args.shares.toString(10)).to.equal("50000000000000000");
    expect(deposit.args.amount0.toString(10)).to.equal("100000000");
    expect(deposit.args.amount1.toString(10)).to.equal("50000000000000000");
  });

  it("should fetch price statistics", async () => {
    const res = await aloeBlend.fetchPriceStatistics();
    expect(res.mean.toString(10)).to.equal("133603816270619257695673");
    expect(res.sigma.toString(10)).to.equal("128962633278655295030");
  });

  it("should rebalance", async () => {
    const width = (await aloeBlend.getNextPositionWidth()).width.toNumber();
    expect(width).to.equal(1000);

    const tx0 = await aloeBlend.rebalance(2);
    console.log(`Rebalance gas: ${tx0.receipt.gasUsed}`);

    const rebalanceEvent = tx0.logs[tx0.logs.length - 1];
    expect(rebalanceEvent.event).to.equal("Rebalance");

    const lower = rebalanceEvent.args.lower.toNumber();
    const upper = rebalanceEvent.args.upper.toNumber();
    const tickSpacing = (await aloeBlend.TICK_SPACING()).toNumber();
    expect(upper - lower).to.be.greaterThanOrEqual(width);
    expect(upper - lower).to.be.lessThanOrEqual(width + 2 * tickSpacing);

    const magic = rebalanceEvent.args.magic.toString(10);
    expect(magic).to.equal("1956053718673968237170145039");
  });

  it("should go to next block", async () => {
    await web3.eth.hardhat.mine();
  });

  it("should rebalance again", async () => {
    const width = (await aloeBlend.getNextPositionWidth()).width.toNumber();
    expect(width).to.equal(1000);

    const tx0 = await aloeBlend.rebalance(2);
    console.log(`Rebalance gas: ${tx0.receipt.gasUsed}`);

    const rebalanceEvent = tx0.logs[tx0.logs.length - 1];
    expect(rebalanceEvent.event).to.equal("Rebalance");

    const magic = rebalanceEvent.args.magic.toString(10);
    expect(magic).to.equal("1956053718673968237170145039");
  });

  it("should withdraw", async () => {
    const tx0 = await aloeBlend.withdraw("100000000000000000", 0, 0, { from: WHALE });
    const withdraw = tx0.logs[tx0.logs.length - 1];
    expect(withdraw.event).to.equal("Withdraw");
    expect(withdraw.args.shares.toString(10)).to.equal("100000000000000000");
    expect(withdraw.args.amount0.toString(10)).to.equal("199999999");
    expect(withdraw.args.amount1.toString(10)).to.equal("99999999856462065");

    console.log((await token0.balanceOf(aloeBlend.address)).toString(10));
    console.log((await token1.balanceOf(aloeBlend.address)).toString(10));
  });
});
