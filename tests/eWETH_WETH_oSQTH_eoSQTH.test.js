const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
const { artifacts, web3 } = require("hardhat");
const fs = require('fs')

const ERC20 = artifacts.require("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20");

const AloeBlend = artifacts.require("AloeBlend");
const Factory = artifacts.require("Factory");
const VolatilityOracle = artifacts.require("VolatilityOracle");

const ERC4626Silo = artifacts.require("ERC4626Silo");

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
      name: "setNextBlockTimestamp",
      call: "evm_setNextBlockTimestamp",
      params: 1,
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
      name: "setAutomine",
      call: "evm_setAutomine",
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

if (!fs.existsSync("build_dapp/dapp.sol.json")) {
  console.log("WARNING: it looks like the dapp artifact is missing. Please run 'dapp --use solc:0.8.13 build' to generate.");
}

const dapptoolsJSON = require("../build_dapp/dapp.sol.json");
const ee4626FactoryContractBuildData = dapptoolsJSON["contracts"]["lib/yield-daddy/src//euler/EulerERC4626Factory.sol"]["EulerERC4626Factory"];
const ee4626FactoryBYTECODE = `0x${ee4626FactoryContractBuildData["evm"]["bytecode"]["object"]}`;
const ee4626FactoryAbi =  ee4626FactoryContractBuildData["abi"];

const ee4626Abi = dapptoolsJSON["contracts"]["lib/yield-daddy/src//euler/EulerERC4626.sol"]["EulerERC4626"]["abi"];

const hardhatJSON = require("../build_hardhat/contracts/AloeBlend.sol/AloeBlend.json");
const BYTECODE = hardhatJSON["bytecode"];
const UINT256MAX = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

const ADDRESS_UNI_POOL = "0x82c427adfdf2d245ec51d8046b41c4ee87f0d29c";
// eWETH
const ADDRESS_ETOKEN0 = "0x1b808F49ADD4b8C6b5117d9681cF7312Fcf0dC1D";
// eoSQTH
const ADDRESS_ETOKEN1 = "0xe2322F73fDF8EE688B1464A19E539B599d43d1B7";

const WHALE = "0x56178a0d5F301bAf6CF3e1Cd53d9863437345Bf9";

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
      const amount = log.args.amount.toNumber();
      const urgency = log.args.urgency.toNumber();

      console.log(`\t   urgency=${urgency / 1e5} ---> ${amount / 1e9} of ${token.slice(0, 6)}`);
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
      else if (from === ADDRESS_ETOKEN0) from = "silo0";
      else if (from === ADDRESS_ETOKEN1) from = "silo1";
      if (to === ADDRESS_UNI_POOL) to = "Uniswap";
      else if (to === ADDRESS_ETOKEN0) to = "silo0";
      else if (to === ADDRESS_ETOKEN1) to = "silo1";

      console.log(`\t   (${log.address.slice(0, 7)})`);
      console.log(`\t   ${amount} from ${from.slice(0, 7)} to ${to.slice(0, 7)}`);
    }
  }
}


describe.only("WETH-oSQTH 0.3% | eWETH | eoSQTH @hardhat", () => {

  let accounts;
  let multisig;

  let aloeBlend;
  let blendFactory;
  let euler4626Factory;
  let oracle;
  let silo0;
  let silo1;

  let token0;
  let token1;

  before(async () => {
    await web3.eth.hardhat.reset({
      forking: {
        jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.PROVIDER_ALCHEMY_KEY}`,
        blockNumber: 15448137,
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
    blendFactory = await Factory.new(oracle.address, BYTECODE);

    // TODO: initialize yield-daddy factory, deploy 4626 for eWETH and eoSQTH before deploying silos.
    
    euler4626Factory = new web3.eth.Contract(ee4626FactoryAbi);
    euler4626Factory = await euler4626Factory.deploy({
      data: ee4626FactoryBYTECODE,
      arguments: ["0x27182842E098f60e3D576794A5bFFb0777E025d3", "0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3"],
    }).send({ from: deployer.address });

    // Deploy e4626eWETH
    await euler4626Factory.methods.createERC4626("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2").send({ from: deployer.address });
    const ee4626eWETHAddress = await euler4626Factory.methods.computeERC4626Address("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2").call();
    // const ee4626eWETH = new web3.eth.Contract(ee4626Abi, ee4626eWETHAddress);

    // Deploy e4626eoSQTH
    await euler4626Factory.methods.createERC4626("0xf1B99e3E573A1a9C5E6B2Ce818b617F0E664E86B").send({ from: deployer.address });
    const ee4626eoSQTHAddress = await euler4626Factory.methods.computeERC4626Address("0xf1B99e3E573A1a9C5E6B2Ce818b617F0E664E86B").call();
    // const ee4626eoSQTH = new web3.eth.Contract(ee4626Abi, ee4626eoSQTHAddress);

    silo0 = await ERC4626Silo.new(ee4626eWETHAddress, {
      from: deployer.address,
    });
    silo1 = await ERC4626Silo.new(ee4626eoSQTHAddress, {
      from: deployer.address,
    });

    await blendFactory.createVault(ADDRESS_UNI_POOL, silo0.address, silo1.address, {
      from: deployer.address,
    });
    const vaultAddress = await blendFactory.getVault(ADDRESS_UNI_POOL, silo0.address, silo1.address);
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

    expect(balance0.gt(10e18)).to.be.true;
    expect(balance1.gt(130e18)).to.be.true;
  });

  it("should fail to deposit before approving tokens", async () => {
    const tx = aloeBlend.deposit("10000000000000000000", "1300000000000000000000", 0, 0, {
      from: WHALE,
    });
    await expect(tx).to.eventually.be.rejectedWith(
      Error,
      "VM Exception while processing transaction: reverted with reason string 'SafeERC20: low-level call failed'"
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
    const tx0 = await aloeBlend.deposit("5000000000000000000", "65000000000000000000", 0, 0, {
      from: WHALE,
    });
    const deposit = tx0.logs[4];
    expect(deposit.event).to.equal("Deposit");
    expect(deposit.args.sender).to.equal(WHALE);
    expect(deposit.args.shares.toString(10)).to.equal("5000000000000000000");
    expect(deposit.args.amount0.toString(10)).to.equal("5000000000000000000");
    expect(deposit.args.amount1.toString(10)).to.equal("63925943583536538932");
  });

  it("should deposit proportionally", async () => {
    // Modify Blend pool asset ratio
    await token0.transfer(aloeBlend.address, "5000", { from: WHALE });
    
    const tx0 = await aloeBlend.deposit("4000000000000000000", UINT256MAX, 0, 0, {
      from: WHALE,
    });


    const deposit = tx0.logs[4];
    expect(deposit.event).to.equal("Deposit");
    expect(deposit.args.sender).to.equal(WHALE);
    expect(deposit.args.shares.toString(10)).to.equal("3999999999999996000");
    // Because of modification, we should expect shares issued < token0 amount
    expect(deposit.args.shares.lt(deposit.args.amount0)).to.be.true;
    // Difference should be <5000 (amount by which ratio was modified)
    expect(deposit.args.amount0.sub(deposit.args.shares).toNumber()).to.be.lt(5000);
    expect(deposit.args.amount0.toString(10)).to.equal("4000000000000000000");
    expect(deposit.args.amount1.toString(10)).to.equal("51140754866829180004");
  });

  it("should rebalance", async () => {
    const tx0 = await aloeBlend.rebalance("0x0000000000000000000000000000000000000000");
    console.log(`Rebalance gas: ${tx0.receipt.gasUsed}`);

    prettyPrintRebalance(tx0);

    const balance0 = await token0.balanceOf(aloeBlend.address);
    const balance1 = await token1.balanceOf(aloeBlend.address);
    expect(balance0.toString(10)).to.equal("450000000000000250"); // 5% of inventory0 (contract float)
    expect(balance1.toString(10)).to.equal("5753334922518285946"); // 5% of inventory1 (contract float)

    const urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(0); // urgency should go to 0 immediately after rebalance
  });

  // it("should get inventory after rebalance", async () => {
  //   const res = await aloeBlend.getInventory();

  //   console.log(`Post-rebalance, pre block ratio: ${res.inventory1.mul(web3.utils.toBN("10000000000")).div(res.inventory0).toString(10)}`);
  // });

  it("should go to next block", async () => {
    await web3.eth.hardhat.mine();
  });

  it("should get inventory before rebalance in new block", async () => {
    const res = await aloeBlend.getInventory();

    expect(res.inventory0.toString(10)).to.equal("9000000001544963572");
    expect(res.inventory1.toString(10)).to.equal("115066698476350501919");
    // console.log(`Post-rebalance, post block ratio: ${res.inventory1.mul(web3.utils.toBN("10000000000")).div(res.inventory0).toString(10)}`);
  });

  it("should rebalance again", async () => {
    let urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(1);

    const tx0 = await aloeBlend.rebalance("0x0000000000000000000000000000000000000000");
    console.log(`Rebalance gas: ${tx0.receipt.gasUsed}`);

    prettyPrintRebalance(tx0);

    const balance0 = await token0.balanceOf(aloeBlend.address);
    const balance1 = await token1.balanceOf(aloeBlend.address);
    expect(balance0.toString(10)).to.equal("456345090810226012"); // 5% of inventory0 (contract float)
    expect(balance1.toString(10)).to.equal("5753334930891160470"); // 5% of inventory1 (contract float)

    urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(0); // urgency should go to 0 immediately after rebalance
  });

  it("should get inventory after rebalance", async () => {
    const res = await aloeBlend.getInventory();

    expect(res.inventory0.toString(10)).to.equal("9000000003089922140");
    expect(res.inventory1.toString(10)).to.equal("115066698502335284948");
  });

  it("should rebalance a third time", async () => {
    let urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(0);

    const tx0 = await aloeBlend.rebalance("0x0000000000000000000000000000000000000000");
    console.log(`Rebalance gas: ${tx0.receipt.gasUsed}`);

    prettyPrintRebalance(tx0);

    const balance0 = await token0.balanceOf(aloeBlend.address);
    const balance1 = await token1.balanceOf(aloeBlend.address);
    expect(balance0.toString(10)).to.equal("456345090815239715"); // 5% of inventory0 (contract float)
    expect(balance1.toString(10)).to.equal("5753334935077597755"); // 5% of inventory1 (contract float)

    urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(0); // urgency should go to 0 immediately after rebalance
  });

  it("should get inventory once more", async () => {
    const res = await aloeBlend.getInventory();

    expect(res.inventory0.toString(10)).to.equal("9000000004632464294");
    expect(res.inventory1.toString(10)).to.equal("115066698528320068095");
  });

  it("should exploit rebalance growth", async () => {
    await web3.eth.hardhat.setAutomine(false);

    for (let i = 0; i < 30; i++) {
      aloeBlend.rebalance("0x0000000000000000000000000000000000000000");
    }

    // mine multiple times to make sure all pending txns get processed (block gas limit)
    await web3.eth.hardhat.mine();
    await web3.eth.hardhat.mine();
    await web3.eth.hardhat.setAutomine(true);

    console.log(`Finished rebalance spamming`);

    const res = await aloeBlend.getInventory();

    expect(res.inventory0.toString(10)).to.equal("9000000053993813919"); // old: 9000000004632464294
    expect(res.inventory1.toString(10)).to.equal("115066699359833176837"); // old: 115066698528320068095

    // Check whale's balance diff after withdrawing
    const whaleStartingBalance0 = await token0.balanceOf(WHALE);
    console.log(`Whale starting balance 0: ${whaleStartingBalance0}`);
    const whaleStartingBalance1 = await token1.balanceOf(WHALE);
    console.log(`Whale starting balance 1: ${whaleStartingBalance1}`);
    const whaleShares = await aloeBlend.balanceOf(WHALE);
    console.log(`Whale shares: ${whaleShares}`);
    await aloeBlend.withdraw(whaleShares, 0, 0, { from: WHALE });
    const whaleEndingBalance0 = await token0.balanceOf(WHALE);
    console.log(`Whale ending balance 0: ${whaleEndingBalance0}`);
    const whaleEndingBalance1 = await token1.balanceOf(WHALE);
    console.log(`Whale ending balance 1: ${whaleEndingBalance1}`);

    expect(whaleEndingBalance0.sub(whaleStartingBalance0).toString(10)).to.equal("9000000055536356119");
    expect(whaleEndingBalance1.sub(whaleStartingBalance1).toString(10)).to.equal("115066699385817962997");

    const balance0 = await token0.balanceOf(aloeBlend.address);
    const balance1 = await token1.balanceOf(aloeBlend.address);
    expect(balance0.toString(10)).to.equal("6170705665"); // dust left after withdrawing
    expect(balance1.toString(10)).to.equal("103939138214"); // dust left after withdrawing

    urgency = (await aloeBlend.getRebalanceUrgency()).toNumber();
    expect(urgency).to.equal(1); // urgency should go to 0 immediately after rebalance
  });


  // it("should withdraw", async () => {
  //   const shares = (await aloeBlend.balanceOf(WHALE));
  //   expect(shares.toString(10)).to.equal("8999999999999996000");

  //   const tx0 = await aloeBlend.withdraw("8999999999999996000", 0, 0, { from: WHALE });

  //   // console.log(tx0.logs);

  //   const withdraw = tx0.logs[tx0.logs.length - 1];
  //   expect(withdraw.event).to.equal("Withdraw");
  //   expect(withdraw.args.shares.toString(10)).to.equal("8999999999999996000");
  //   expect(withdraw.args.amount0.toString(10)).to.equal("9000000055536356119");
  //   expect(withdraw.args.amount1.toString(10)).to.equal("115066699385817962997");

  //   console.log((await token0.balanceOf(aloeBlend.address)).toString(10));
  //   console.log((await token1.balanceOf(aloeBlend.address)).toString(10));
  // });
});
