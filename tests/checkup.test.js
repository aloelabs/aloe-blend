const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
const { artifacts } = require("hardhat");

const ERC20 = artifacts.require("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20");

const AloeBlend = artifacts.require("AloeBlend");

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

async function test_invariants(block, vaults, tickSpacings, whales, amounts) {
  await web3.eth.hardhat.reset({
    forking: {
      jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.PROVIDER_ALCHEMY_KEY}`,
      blockNumber: block,
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

  let i = 0;
  for (const vault of vaults) {
    const blend = await AloeBlend.at(vault);
    const token0 = await ERC20.at(await blend.TOKEN0());
    const token1 = await ERC20.at(await blend.TOKEN1());

    // FETCHING BASIC DATA --------------------------------------------------
    const MIN_WIDTH = await blend.MIN_WIDTH();
    const MAX_WIDTH = await blend.MAX_WIDTH();
    const FLOAT_PERCENTAGE = await blend.FLOAT_PERCENTAGE();
    let res = await blend.getInventory();
    let inventory0 = res.inventory0;
    let inventory1 = res.inventory1;
    let balance0 = await token0.balanceOf(blend.address);
    let balance1 = await token1.balanceOf(blend.address);
    const maintenanceBudget0 = await blend.maintenanceBudget0();
    const maintenanceBudget1 = await blend.maintenanceBudget1();
    const packedSlot = await blend.packedSlot();
    const primaryLower = packedSlot.primaryLower;
    const primaryUpper = packedSlot.primaryUpper;

    // Invariant: primary position width is between MIN_WIDTH and MAX_WIDTH
    expect(primaryUpper.sub(primaryLower).toNumber()).greaterThanOrEqual(MIN_WIDTH.toNumber() - 2 * tickSpacings[i]);
    expect(primaryUpper.sub(primaryLower).toNumber()).lessThanOrEqual(MAX_WIDTH.toNumber() + 2 * tickSpacings[i]);
    console.log('--> position width looks good')

    // Invariant: between function calls, vault is not locked
    expect(packedSlot.locked).to.be.false;
    console.log('--> locking looks good')

    // Invariant: balance > maintenanceBudget
    expect(balance0.gt(maintenanceBudget0)).to.be.true;
    expect(balance1.gt(maintenanceBudget1)).to.be.true;
    console.log('--> budget looks good')

    // SIMULATING DEPOSIT/WITHDRAW ------------------------------------------
    await web3.eth.hardhat.impersonate(whales[i]);
    await token0.approve(blend.address, UINT256MAX, { from: whales[i] });
    await token1.approve(blend.address, UINT256MAX, { from: whales[i] });
    const deposit_tx = await blend.deposit(amounts[i][0], amounts[i][1], 0, 0, { from: whales[i] });
    const deposit_data = deposit_tx.logs[3];
    const shares = deposit_data.args.shares;
    const amount0_in = deposit_data.args.amount0;
    const amount1_in = deposit_data.args.amount1;

    res = await blend.getInventory();
    inventory0 = res.inventory0;
    inventory1 = res.inventory1;
    let totalSupply = await blend.totalSupply();

    const withdraw_tx = await blend.withdraw(shares, 0, 0, { from: whales[i] });
    const withdraw_data = withdraw_tx.logs[withdraw_tx.logs.length - 1];
    const amount0_out = withdraw_data.args.amount0;
    const amount1_out = withdraw_data.args.amount1;

    const amount0_expected = inventory0.mul(shares).div(totalSupply);
    const amount1_expected = inventory1.mul(shares).div(totalSupply);
    const error0 = amount0_expected.sub(amount0_out).abs();
    const error1 = amount1_expected.sub(amount1_out).abs();

    const BN = web3.utils.toBN;
    const tenk = BN(10000);
    const billion = BN(100000000000000)

    expect(error0.toNumber() / amount0_expected.div(tenk).toNumber()).lessThanOrEqual(1);
    expect(error1.toNumber() / amount1_expected.div(tenk).toNumber()).lessThanOrEqual(1);

    expect(amount0_in.mul(billion).div(amount0_out).toNumber()).greaterThanOrEqual(99999999999);
    expect(amount1_in.mul(billion).div(amount1_out).toNumber()).greaterThanOrEqual(99999999999);

    const rebalance_tx = await blend.rebalance("0x0000000000000000000000000000000000000000");
    const rebalance_data = rebalance_tx.logs[rebalance_tx.logs.length - 1];
    inventory0 = rebalance_data.args.inventory0;
    inventory1 = rebalance_data.args.inventory1;
    balance0 = await token0.balanceOf(blend.address);
    balance1 = await token1.balanceOf(blend.address);

    // Invariant (after a rebalance): balance - maintenanceBudget >= inventory * float / 10_000
    expect(balance0.sub(maintenanceBudget0).gt(inventory0.mul(FLOAT_PERCENTAGE.sub(BN(1))).div(tenk))).to.be.true;
    expect(balance1.sub(maintenanceBudget1).gt(inventory1.mul(FLOAT_PERCENTAGE.sub(BN(1))).div(tenk))).to.be.true;
    console.log('--> float looks good')

    i += 1;
  }
}

describe("checkup @hardhat", () => {
  const VAULTS = ["0x3D8a84FD7D5D43B20eB171bdba00e4F425dB6eb0", "0x90E0ebBb1B77B1BBC31887219F089404355dD43F"];
  const TICK_SPACINGS = [10, 1];
  const WHALES = ["0x4F868C1aa37fCf307ab38D215382e88FCA6275E2", "0x075e72a5edf65f0a5f44699c7654c1a76941ddc8"];
  const AMOUNTS = [
    ["100000000", "50000000000000000"],
    ["1000000000000000000", "1000000"],
  ]

  const BLOCK_START = 14080207;
  const BLOCK_END = 14124778;
  const BLOCK_INTERVAL = 9000;

  it("should maintain invariants across time", async () => {
    for (let i = BLOCK_START; i <= BLOCK_END; i += BLOCK_INTERVAL) {
      await test_invariants(i, VAULTS, TICK_SPACINGS, WHALES, AMOUNTS);
      console.log(`Finished block ${i}`);
    }
  });
});
