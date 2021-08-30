const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
const { artifacts } = require("hardhat");

const AloeBlend = artifacts.require("AloeBlendCapped");
const FuseFEtherSilo = artifacts.require("FuseFEtherSilo");
const OlympusStakingSilo = artifacts.require("OlympusStakingSilo");
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
    {
      name: "reset",
      call: "hardhat_reset",
      params: 1,
      /*
      {
        forking: {
          jsonRpcUrl: "https://eth-mainnet.alchemyapi.io/v2/<key>",
          blockNumber: 11095000,
        },
      }
      */
    },
  ],
});

const UINT256MAX = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

describe("OHM-WETH 1.00% | sOHM | fETH @hardhat", () => {
  const ADDRESS_UNI_POOL = "0xF1B63cD9d80f922514c04b0fD0a30373316dd75b";
  const ADDRESS_STAKING = "0xFd31c7d00Ca47653c6Ce64Af53c1571f9C36566a";
  const ADDRESS_SOHM = "0x04F2694C8fcee23e8Fd0dfEA1d4f5Bb8c352111F";
  const ADDRESS_FETH = "0xFA1057d02A0C1a4885851e3F4fD496Ee7D38F56e";
  const WHALE = "0xA586605928d6dF1E56DE41c8Cb2dA2F3ba666EB9";

  let accounts;
  let multisig;
  let aloeBlend;
  let token0;
  let token1;

  before(async () => {
    await web3.eth.hardhat.reset({
      forking: {
        jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.PROVIDER_ALCHEMY_KEY}`,
        blockNumber: 13126270,
      },
      accounts: [
        {
          privateKey: "0101010101010101010101010101010101010101010101010101010101010101",
          balance: "2000000000000000000",
        },
        {
          privateKey: process.env.DEPLOYER,
          balance: "2000000000000000000",
        },
      ],
    });
  });

  it("should deploy", async () => {
    accounts = await web3.eth.getAccounts();
    multisig = accounts[0];

    const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);

    silo0 = await OlympusStakingSilo.new(ADDRESS_STAKING, {
      from: deployer.address,
    });
    silo1 = await FuseFEtherSilo.new(ADDRESS_FETH, {
      from: deployer.address,
    });

    console.log(
      await AloeBlend.new.estimateGas(ADDRESS_UNI_POOL, silo0.address, silo1.address, multisig, {
        from: deployer.address,
      })
    );

    aloeBlend = await AloeBlend.new(ADDRESS_UNI_POOL, silo0.address, silo1.address, multisig, {
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

    expect(balance0.gt(20e18)).to.be.true;
    expect(balance1.gt(90e9)).to.be.true;
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
      "VM Exception while processing transaction: reverted with reason string 'Aloe: Vault filled up'"
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
    const tx0 = await aloeBlend.deposit("45000000000", "10000000000000000000", 0, 0, {
      from: WHALE,
    });
    const deposit = tx0.logs[tx0.logs.length - 1];
    expect(deposit.event).to.equal("Deposit");
    expect(deposit.args.sender).to.equal(WHALE);
    expect(deposit.args.shares.toString(10)).to.equal("45000000000");
    expect(deposit.args.amount0.toString(10)).to.equal("45000000000");
    expect(deposit.args.amount1.toString(10)).to.equal("4957486173449489992");
  });

  it("should fetch price statistics", async () => {
    const res = await aloeBlend.fetchPriceStatistics();
    expect(res.mean.toString(10)).to.equal("0");
    expect(res.sigma.toString(10)).to.equal("0");
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

    const sOHM = await ERC20.at(ADDRESS_SOHM);
    const sOHMBalance = await sOHM.balanceOf(aloeBlend.address);
    expect(sOHMBalance.toString(10)).to.equal("43889000899");

    const fETH = await ERC20.at(ADDRESS_FETH);
    const fETHBalance = await fETH.balanceOf(aloeBlend.address);
    expect(fETHBalance.toString(10)).to.equal("4805889536082007474");
  });

  it("should deposit proportionally and atomically place in Uniswap", async () => {
    const tx0 = await aloeBlend.deposit("45000000000", "10000000000000000000", 0, 0, {
      from: WHALE,
    });
    const deposit = tx0.logs[tx0.logs.length - 1];
    expect(deposit.event).to.equal("Deposit");
    expect(deposit.args.sender).to.equal(WHALE);
    expect(deposit.args.shares.toString(10)).to.equal("45000000001");
    expect(deposit.args.amount0.toString(10)).to.equal("45000000000");
    expect(deposit.args.amount1.toString(10)).to.equal("4957486215877010606");
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
    const tx0 = await aloeBlend.withdraw("90000000001", 0, 0, { from: WHALE });
    const withdraw = tx0.logs[tx0.logs.length - 1];
    expect(withdraw.event).to.equal("Withdraw");
    expect(withdraw.args.shares.toString(10)).to.equal("90000000001");
    expect(withdraw.args.amount0.toString(10)).to.equal("89999999997");
    expect(withdraw.args.amount1.toString(10)).to.equal("9914972516168402567");

    console.log((await token0.balanceOf(aloeBlend.address)).toString(10));
    console.log((await token1.balanceOf(aloeBlend.address)).toString(10));
  });
});
