const { artifacts } = require("hardhat");

const AloeBlend = artifacts.require("AloeBlendCapped");
const ERC20 = artifacts.require("ERC20");

const Big = require("big.js");

const visorABI = require("./hypervisor_abi.json");

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

const ADDRESS_BLEND_USDC_WETH = "0x1cF3e6f18223a1f2A445f2cD60538Af380e98074";
const USDC_WETH_DECIMAL_DIFF = 12;

const ADDRESS_BLEND_TARGET = "0x8Bc7C34009965ccb8c0C2eB3d4db5a231eCc856C";
const TARGET_DECIMAL_DIFF = 9;

const UINT256MAX = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

async function forkAt(blockNumber) {
  await web3.eth.hardhat.reset({
    forking: {
      jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.PROVIDER_ALCHEMY_KEY}`,
      blockNumber: blockNumber,
    },
  });
}

async function getPricePerShare() {
  // BLEND -------------------------------------------------------------------------
  const aloeBlend = await AloeBlend.at(ADDRESS_BLEND_TARGET);

  let res = await aloeBlend.getInventory();
  const inventory0 = new Big(res.inventory0.toString(10));
  const inventory1 = new Big(res.inventory1.toString(10));
  const totalSupply = await aloeBlend.totalSupply();

  res = await aloeBlend.fetchPriceStatistics();
  const ethPerToken0 = 1.0001 ** res.tickTWAP.toNumber() / 10 ** TARGET_DECIMAL_DIFF;

  const aloeBlendUSDCWETH = await AloeBlend.at(ADDRESS_BLEND_USDC_WETH);
  res = await aloeBlendUSDCWETH.fetchPriceStatistics();
  const usdcPerEth = 10 ** USDC_WETH_DECIMAL_DIFF / 1.0001 ** res.tickTWAP.toNumber();

  const usdcPerToken0 = usdcPerEth * ethPerToken0;

  const value0 = inventory0.mul(usdcPerToken0).div(1e9);
  const value1 = inventory1.mul(usdcPerEth).div(1e18);
  const totalValue = value0.plus(value1);

  const pricePerShare = totalValue.mul(1e18).div(totalSupply.toString(10));

  // Visor ----------------------------------------------------------------------------
  const visor = new web3.eth.Contract(visorABI, "0x65Bc5c6A2630a87C2B494f36148E338dD76C054F");
  res = await visor.methods.getTotalAmounts().call();
  const inventory0Visor = new Big(res.total0.toString(10));
  const inventory1Visor = new Big(res.total1.toString(10));
  const totalValueVisor = inventory0Visor.mul(usdcPerToken0).div(1e9).plus(inventory1Visor.mul(usdcPerEth).div(1e18));
  const totalSupplyVisor = await visor.methods.totalSupply().call();
  const pricePerShareVisor = totalValueVisor.mul(1e18).div(totalSupplyVisor.toString(10));

  // V2 (feeless) ------------------------------------------------------------------------
  const v2Measure = usdcPerToken0 * Math.sqrt(1 / ethPerToken0);

  console.log(
    `${usdcPerToken0.toFixed(2)},${usdcPerEth.toFixed(2)},${value0.toFixed(2)},${value1.toFixed(
      2
    )},${pricePerShare.toFixed(2)},${pricePerShareVisor.toFixed(2)},${v2Measure.toFixed(3)}`
  );
}

async function getPlotData(blocks) {
  console.log('Price OHM [$],Price ETH [$],Blend token0 Inventory [$],Blend token1 Inventory [$],Blend Price/Share [$],Visor Price/Share [$],V2 Perf');

  for (const block of blocks) {
    await forkAt(block);
    try {
      await getPricePerShare();
    } catch {
      console.log(`failed for ${block}`);
    }
  }
}

const avg_block_time = 13.1; // seconds
const interval = 6 * 60 * 60; // seconds
const blocks_per_interval = interval / avg_block_time;
const lookback = 14 * 24 * 60 * 60; // seconds

const blocks = [13220156];
for (let i = 0; i < Math.floor(lookback / interval); i++) {
  blocks.push(Math.floor(blocks[i] - blocks_per_interval));
}
blocks.reverse();

console.log(blocks);

getPlotData(blocks);