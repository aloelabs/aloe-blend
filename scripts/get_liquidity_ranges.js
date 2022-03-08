const { artifacts } = require("hardhat");

const AloeBlend = artifacts.require("AloeBlend");
const ISilo = artifacts.require("ISilo.sol");
const ERC20 = artifacts.require("ERC20");

const fs = require('fs');
const Big = require("big.js");
const axios = require('axios');

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
    },
  ],
});

async function forkAt(blockNumber) {
  await web3.eth.hardhat.reset({
    forking: {
      jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.PROVIDER_ALCHEMY_KEY}`,
      blockNumber: blockNumber,
    },
  });
}

const COINMARKETCAP_API_KEY = process.env.COINMARKETCAP_API_KEY; // Free API keys are available. If your needs go beyond what the free tier allows, let us know in Discord!
const BLEND_POOL_ADDRESS = "0x33cB657E7fd57F1f2d5f392FB78D5FA80806d1B4";
const BLEND_POOL_CREATION_BLOCK = 14170521;
const CURRENT_BLOCK = 14432948;
const SECONDS_PER_BLOCK = 15;

async function getAvgOfNearestHourlyOpenClose(blockTimestamp, symbols) {
  const timestampToQuery = (blockTimestamp - 60 * 60) * 1000;

  const params = {
    symbol: symbols.join(','),
    time_period: 'hourly',
    time_start: timestampToQuery.toFixed(0),
    count: 1,
    interval: 'hourly',
    skip_invalid: true,
  };
  const stringified = Object.entries(params).map((entry) => `${entry[0]}=${entry[1]}`).join('&');

  const response = await axios.get(`https://pro-api.coinmarketcap.com/v2/cryptocurrency/ohlcv/historical?${stringified}`, {
    headers: {
      'X-CMC_PRO_API_KEY': COINMARKETCAP_API_KEY,
    },
  });
  const data = response.data['data'];

  return Object.fromEntries(Object.entries(data).map((entry) => {
    const quote = entry[1][0]['quotes'][0]['quote']['USD'];
    const open = quote['open'];
    const close = quote['close'];
    const mean = (open + close) / 2.0;
    
    entry[1] = mean;
    return entry;
  }));
}

async function getLiquidityRanges(vault, silo0, silo1, token0, token1, prices, symbol0, symbol1, decimals0, decimals1) {
  let res = await vault.getInventory();
  const inventory0 = new Big(res.inventory0.toString(10));
  const inventory1 = new Big(res.inventory1.toString(10));
  const silo0Balance = new Big((await silo0.balanceOf(vault.address)).toString(10));
  const silo1Balance = new Big((await silo1.balanceOf(vault.address)).toString(10));
  const contractBalance0 = new Big((await token0.balanceOf(vault.address)).toString(10));
  const contractBalance1 = new Big((await token1.balanceOf(vault.address)).toString(10));
  const maintenanceBudget0 = new Big((await vault.maintenanceBudget0()).toString(10));
  const maintenanceBudget1 = new Big((await vault.maintenanceBudget1()).toString(10));

  const float0 = contractBalance0.minus(maintenanceBudget0);
  const float1 = contractBalance1.minus(maintenanceBudget1);
  const uniswap0 = inventory0.minus(silo0Balance).minus(float0);
  const uniswap1 = inventory1.minus(silo1Balance).minus(float1);

  const float0Percent = float0.div(inventory0).toNumber();
  const float1Percent = float1.div(inventory1).toNumber();
  const uniswap0Percent = uniswap0.div(inventory0).toNumber();
  const uniswap1Percent = uniswap1.div(inventory1).toNumber();
  const silo0Percent = silo0Balance.div(inventory0).toNumber();
  const silo1Percent = silo1Balance.div(inventory1).toNumber();

  const tvl0 = inventory0.mul(prices[symbol0]).div(`1e${decimals0}`);
  const tvl1 = inventory1.mul(prices[symbol1]).div(`1e${decimals1}`);
  
  const percent0 = tvl0.div(tvl0.plus(tvl1)).toNumber();
  const percent1 = 1. - percent0;
  
  res = await vault.packedSlot();
  const primaryLower = res.primaryLower.toNumber();
  const primaryUpper = res.primaryUpper.toNumber();
  const limitLower = res.limitLower.toNumber();
  const limitUpper = res.limitUpper.toNumber();

  return {
    primaryLower,
    primaryUpper,
    limitLower,
    limitUpper,
    percent0,
    percent1,
    float0Percent: float0Percent * percent0,
    float1Percent: float1Percent * percent1,
    uniswap0Percent: uniswap0Percent * percent0,
    uniswap1Percent: uniswap1Percent * percent1,
    silo0Percent: silo0Percent * percent0,
    silo1Percent: silo1Percent * percent1,
  }
}

async function getPricePerShareHistory(blendPoolAddress, blockFromWhichPollingBegins, blockInterval, blockAtWhichPollingEnds) {
  const totalBlocks = blockAtWhichPollingEnds - blockFromWhichPollingBegins;
  let blockNumber = blockFromWhichPollingBegins
  await forkAt(blockNumber);

  const blend = await AloeBlend.at(blendPoolAddress);
  const silo0 = await ISilo.at(await blend.silo0());
  const silo1 = await ISilo.at(await blend.silo1());

  const token0 = await ERC20.at(await blend.TOKEN0());
  const token1 = await ERC20.at(await blend.TOKEN1());
  const symbol0 = await token0.symbol();
  const symbol1 = await token1.symbol();
  const decimals0 = await token0.decimals();
  const decimals1 = await token1.decimals();

  let summaries = [];

  const N = Math.floor(totalBlocks / blockInterval);
  for (let i = 0; i < N; i++) {
    console.log(`Progress: ${i} / ${N}`);

    blockNumber = Math.floor(blockFromWhichPollingBegins + i * blockInterval);
    await forkAt(blockNumber);

    const block = await web3.eth.getBlock(blockNumber);
    const prices = await getAvgOfNearestHourlyOpenClose(block.timestamp, [symbol0, symbol1]);
    const results = await getLiquidityRanges(blend, silo0, silo1, token0, token1, prices, symbol0, symbol1, decimals0, decimals1);

    const summary = {
      'timestamp': block.timestamp,
      'price0': prices[symbol0],
      'price1': prices[symbol1],
      ...results,
    };
    console.log(summary);
    summaries.push(summary);

    // Avoid rate limiting
    await new Promise((resolve) => {
      setTimeout(resolve, 1000);
    });
  }

  return summaries;
}

const maxSecondsAgo = 30 * 24 * 60 * 60;
const maxBlocksAgo = maxSecondsAgo / SECONDS_PER_BLOCK;
const blockFromWhichPollingBegins = Math.max(CURRENT_BLOCK - maxBlocksAgo, BLEND_POOL_CREATION_BLOCK + 1);
const blockAtWhichPollingEnds = CURRENT_BLOCK - 1;
const pollingInterval = 60 * 60 * 8;

getPricePerShareHistory(
  BLEND_POOL_ADDRESS,
  blockFromWhichPollingBegins,
  pollingInterval / SECONDS_PER_BLOCK,
  blockAtWhichPollingEnds
).then((summaries) => {
  fs.writeFileSync('scripts/results/liquidity_ranges.json', JSON.stringify(summaries));
});
