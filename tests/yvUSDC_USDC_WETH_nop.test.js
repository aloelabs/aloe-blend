const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
const { artifacts } = require("hardhat");

const ERC20 = artifacts.require("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20");

const AloeBlend = artifacts.require("AloeBlend");
const Factory = artifacts.require("Factory");
const VolatilityOracle = artifacts.require("VolatilityOracle");

const YearnSilo = artifacts.require("YearnSilo");
const NOPSilo = artifacts.require("NOPSilo");

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

const buildJSON = require("../build_hardhat/contracts/AloeBlend.sol/AloeBlend.json");
// console.log(buildJSON);
const BYTECODE = buildJSON["bytecode"];
const UINT256MAX = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

const ADDRESS_UNI_POOL = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640";
const ADDRESS_YTOKEN0 = "0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE";
const WHALE = "0x4F868C1aa37fCf307ab38D215382e88FCA6275E2";

function prettyPrintRebalance(tx) {
  console.log("⚖️ The vault was rebalanced!");
  for (const log of tx.logs) {
    console.log(`\t${log.event}`);

    if (log.event === "Recenter") {
      const lower = log.args.lower.toNumber();
      const upper = log.args.upper.toNumber();
      const middle = Math.round((lower + upper) / 2);

      console.log(`\t   || ${lower} |======> ${middle} <======| ${upper} ||`);
    } else if (log.event === "Reward") {
      const token = log.args.token;
      const amount = log.args.amount.toString(0);
      const urgency = log.args.urgency.toNumber();

      console.log(`\t   urgency=${urgency / 1e5} ---> ${amount} of ${token.slice(0, 6)}`);
    } else if (log.event === "Rebalance") {
      const ratio = log.args.ratio.toString(0);
      const shares = log.args.shares.toString(0);
      const inventory0 = log.args.inventory0.toString(0);
      const inventory1 = log.args.inventory1.toString(0);

      console.log(`\t   ratio=${ratio}  (${inventory0} / ${inventory1})`);
      console.log(`\t   ${shares} outstanding shares`);
    } else if (log.event === "Transfer") {
      let from = log.args.from;
      let to = log.args.to;
      const amount = log.args.amount.toString(0);

      if (from === ADDRESS_UNI_POOL) from = "Uniswap";
      else if (from === ADDRESS_YTOKEN0) from = "silo0";
      if (to === ADDRESS_UNI_POOL) to = "Uniswap";
      else if (to === ADDRESS_YTOKEN0) to = "silo0";

      console.log(`\t   (${log.address.slice(0, 7)})`);
      console.log(`\t   ${amount} from ${from.slice(0, 7)} to ${to.slice(0, 7)}`);
    }
  }
}

describe("USDC-WETH 0.05% | yUSDC | no-op @hardhat", () => {

  let accounts;

  let aloeBlend;
  let factory;
  let oracle;
  let silo0;
  let silo1;

  let token0;
  let token1;

  before(async () => {
    await web3.eth.hardhat.reset({
      forking: {
        jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.PROVIDER_ALCHEMY_KEY}`,
        blockNumber: 13513457,
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

    oracle = await VolatilityOracle.new();
    factory = await Factory.new(oracle.address, BYTECODE);
    silo0 = await YearnSilo.new(ADDRESS_YTOKEN0, 1, {
      from: deployer.address,
    });
    silo1 = await NOPSilo.new({
      from: deployer.address,
    });

    await factory.createVault(ADDRESS_UNI_POOL, silo0.address, silo1.address, {
      from: deployer.address,
    });
    const vaultAddress = await factory.getVault(ADDRESS_UNI_POOL, silo0.address, silo1.address);
    aloeBlend = await AloeBlend.at(vaultAddress);
    token0 = await ERC20.at(await aloeBlend.TOKEN0());
    token1 = await ERC20.at(await aloeBlend.TOKEN1());
  });

  it("should get inventory (zero)", async () => {
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

  it("should fail to deposit before approving tokens", async () => {
    const tx = aloeBlend.deposit("100000000", "100000000000000000", 0, 0, {
      from: WHALE,
    });
    await expect(tx).to.eventually.be.rejectedWith(
      Error,
      "VM Exception while processing transaction: reverted with reason string 'ERC20: transfer amount exceeds allowance'"
    );
  });

  it("should approve tokens for vault management", async () => {
    const tx0 = await token0.approve(aloeBlend.address, UINT256MAX, {
      from: WHALE,
    });
    const tx1 = await token1.approve(aloeBlend.address, UINT256MAX, {
      from: WHALE,
    });
    expect(tx0.receipt.status).to.be.true;
    expect(tx1.receipt.status).to.be.true;
  });

  it("should deposit", async () => {
    const tx0 = await aloeBlend.deposit("100000000", "50000000000000000", 0, 0, {
      from: WHALE,
    });
    const deposit = tx0.logs[3];
    expect(deposit.event).to.equal("Deposit");
    expect(deposit.args.sender).to.equal(WHALE);
    expect(deposit.args.shares.toString(10)).to.equal("100000000");
    expect(deposit.args.amount0.toString(10)).to.equal("100000000");
    expect(deposit.args.amount1.toString(10)).to.equal("22597414240720952");
  });

  it("should deposit proportionally", async () => {
    const tx0 = await aloeBlend.deposit("100000000", "40000000000000000", 0, 0, {
      from: WHALE,
    });
    const deposit = tx0.logs[3];
    expect(deposit.event).to.equal("Deposit");
    expect(deposit.args.sender).to.equal(WHALE);
    expect(deposit.args.shares.toString(10)).to.equal("100000000");
    expect(deposit.args.amount0.toString(10)).to.equal("100000000");
    expect(deposit.args.amount1.toString(10)).to.equal("22597414240720952");
  });

  it("should rebalance", async () => {
    const tx0 = await aloeBlend.rebalance("0x0000000000000000000000000000000000000000");
    console.log(`Rebalance gas: ${tx0.receipt.gasUsed}`);

    prettyPrintRebalance(tx0);

    const balance0 = (await token0.balanceOf(aloeBlend.address)).toString(0);
    const balance1 = (await token1.balanceOf(aloeBlend.address)).toString(0);
    expect(balance0).to.equal("10000000"); // 5% of inventory0 (contract float)
    expect(balance1).to.equal("22599421923199193"); // 5% of inventory1 (contract float)

    const urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(0); // urgency should go to 0 immediately after rebalance
  });

  it("should go to next block", async () => {
    await web3.eth.hardhat.mine();
  });

  it("should get inventory before rebalance", async () => {
    const res = await aloeBlend.getInventory();

    expect(res.inventory0.toString(10)).to.equal("199990999");
    expect(res.inventory1.toString(10)).to.equal("45194828481441903");
  });

  it("should rebalance again", async () => {
    let urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(1);

    const tx0 = await aloeBlend.rebalance("0x0000000000000000000000000000000000000000");
    console.log(`Rebalance gas: ${tx0.receipt.gasUsed}`);

    prettyPrintRebalance(tx0);

    const balance0 = (await token0.balanceOf(aloeBlend.address)).toString(0);
    const balance1 = (await token1.balanceOf(aloeBlend.address)).toString(0);
    expect(balance0).to.equal("9999549"); // 5% of inventory0 (contract float)
    expect(balance1).to.equal("22600438923981442"); // 5% of inventory1 (contract float)

    urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(0); // urgency should go to 0 immediately after rebalance
  });

  it("should get inventory after rebalance", async () => {
    const res = await aloeBlend.getInventory();

    expect(res.inventory0.toString(10)).to.equal("199990997");
    expect(res.inventory1.toString(10)).to.equal("45194828481441902");
  });

  it("should rebalance a third time", async () => {
    let urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(0);

    const tx0 = await aloeBlend.rebalance("0x0000000000000000000000000000000000000000");
    console.log(`Rebalance gas: ${tx0.receipt.gasUsed}`);

    prettyPrintRebalance(tx0);

    const balance0 = (await token0.balanceOf(aloeBlend.address)).toString(0);
    const balance1 = (await token1.balanceOf(aloeBlend.address)).toString(0);
    expect(balance0).to.equal("9999549"); // 5% of inventory0 (contract float)
    expect(balance1).to.equal("22600439149933627"); // 5% of inventory1 (contract float)

    urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(0); // urgency should go to 0 immediately after rebalance
  });

  it("should get inventory once more", async () => {
    const res = await aloeBlend.getInventory();

    expect(res.inventory0.toString(10)).to.equal("199990996");
    expect(res.inventory1.toString(10)).to.equal("45194828481441901");
  });

  it("should withdraw some", async () => {
    let shares = (await aloeBlend.balanceOf(WHALE)).toNumber();
    expect(shares).to.equal(200000000);

    shares = Math.floor(Math.random() * shares / 2);

    const tx0 = await aloeBlend.withdraw(shares.toString(), 0, 0, { from: WHALE });
    const withdraw = tx0.logs[tx0.logs.length - 1];
    expect(withdraw.event).to.equal("Withdraw");
    expect(withdraw.args.shares.toString(10)).to.equal(shares.toString());
  });

  it("should withdraw more", async () => {
    const tx0 = await aloeBlend.withdraw("100000000", 0, 0, { from: WHALE });
    const withdraw = tx0.logs[tx0.logs.length - 1];
    expect(withdraw.event).to.equal("Withdraw");
    expect(withdraw.args.shares.toString(10)).to.equal("100000000");
    expect(withdraw.args.amount0.gt("99995497")).to.be.true;
    expect(withdraw.args.amount1.gt("22597414240720950")).to.be.true;
  });

  it("should withdraw rest", async () => {
    let shares = (await aloeBlend.balanceOf(WHALE)).toNumber();
    await aloeBlend.withdraw(shares.toString(), 0, 0, { from: WHALE });

    console.log((await token0.balanceOf(aloeBlend.address)).toString(10));
    console.log((await token1.balanceOf(aloeBlend.address)).toString(10));
    console.log((await silo0.balanceOf(aloeBlend.address)).toString(10));
    console.log((await silo1.balanceOf(aloeBlend.address)).toString(10));
  });
});
