const { artifacts } = require("hardhat");

const AloeBlend = artifacts.require("AloeBlend");
const IUniswapV3Pool = artifacts.require("IUniswapV3Pool");
const ERC20 = artifacts.require("ERC20");

const fs = require('fs');
const Big = require("big.js");
const axios = require('axios');

const IUniswapV2Pool = [{"inputs":[],"payable":false,"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Burn","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"}],"name":"Mint","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount0Out","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1Out","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Swap","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint112","name":"reserve0","type":"uint112"},{"indexed":false,"internalType":"uint112","name":"reserve1","type":"uint112"}],"name":"Sync","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"constant":true,"inputs":[],"name":"DOMAIN_SEPARATOR","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"MINIMUM_LIQUIDITY","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"PERMIT_TYPEHASH","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"burn","outputs":[{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"factory","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getReserves","outputs":[{"internalType":"uint112","name":"_reserve0","type":"uint112"},{"internalType":"uint112","name":"_reserve1","type":"uint112"},{"internalType":"uint32","name":"_blockTimestampLast","type":"uint32"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"_token0","type":"address"},{"internalType":"address","name":"_token1","type":"address"}],"name":"initialize","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"kLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mint","outputs":[{"internalType":"uint256","name":"liquidity","type":"uint256"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"nonces","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"permit","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"price0CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"price1CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"skim","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"uint256","name":"amount0Out","type":"uint256"},{"internalType":"uint256","name":"amount1Out","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"swap","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[],"name":"sync","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"token0","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"token1","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"}];
const ICharmish = [{"inputs":[{"internalType":"address","name":"_pool","type":"address"},{"internalType":"uint256","name":"_protocolFee","type":"uint256"},{"internalType":"uint256","name":"_maxTotalSupply","type":"uint256"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"feesToVault0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"feesToVault1","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"feesToProtocol0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"feesToProtocol1","type":"uint256"}],"name":"CollectFees","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"shares","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"}],"name":"Deposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"int24","name":"tick","type":"int24"},{"indexed":false,"internalType":"uint256","name":"totalAmount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"totalAmount1","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"totalSupply","type":"uint256"}],"name":"Snapshot","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"shares","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"}],"name":"Withdraw","type":"event"},{"inputs":[],"name":"acceptGovernance","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"accruedProtocolFees0","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"accruedProtocolFees1","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"baseLower","outputs":[{"internalType":"int24","name":"","type":"int24"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"baseUpper","outputs":[{"internalType":"int24","name":"","type":"int24"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"},{"internalType":"address","name":"to","type":"address"}],"name":"collectProtocol","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"subtractedValue","type":"uint256"}],"name":"decreaseAllowance","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amount0Desired","type":"uint256"},{"internalType":"uint256","name":"amount1Desired","type":"uint256"},{"internalType":"uint256","name":"amount0Min","type":"uint256"},{"internalType":"uint256","name":"amount1Min","type":"uint256"},{"internalType":"address","name":"to","type":"address"}],"name":"deposit","outputs":[{"internalType":"uint256","name":"shares","type":"uint256"},{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"int24","name":"tickLower","type":"int24"},{"internalType":"int24","name":"tickUpper","type":"int24"},{"internalType":"uint128","name":"liquidity","type":"uint128"}],"name":"emergencyBurn","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getBalance0","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getBalance1","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"int24","name":"tickLower","type":"int24"},{"internalType":"int24","name":"tickUpper","type":"int24"}],"name":"getPositionAmounts","outputs":[{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getTotalAmounts","outputs":[{"internalType":"uint256","name":"total0","type":"uint256"},{"internalType":"uint256","name":"total1","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"governance","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"addedValue","type":"uint256"}],"name":"increaseAllowance","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"limitLower","outputs":[{"internalType":"int24","name":"","type":"int24"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"limitUpper","outputs":[{"internalType":"int24","name":"","type":"int24"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"maxTotalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"pendingGovernance","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"pool","outputs":[{"internalType":"contract IUniswapV3Pool","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"protocolFee","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"int256","name":"swapAmount","type":"int256"},{"internalType":"uint160","name":"sqrtPriceLimitX96","type":"uint160"},{"internalType":"int24","name":"_baseLower","type":"int24"},{"internalType":"int24","name":"_baseUpper","type":"int24"},{"internalType":"int24","name":"_bidLower","type":"int24"},{"internalType":"int24","name":"_bidUpper","type":"int24"},{"internalType":"int24","name":"_askLower","type":"int24"},{"internalType":"int24","name":"_askUpper","type":"int24"}],"name":"rebalance","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_governance","type":"address"}],"name":"setGovernance","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_maxTotalSupply","type":"uint256"}],"name":"setMaxTotalSupply","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_protocolFee","type":"uint256"}],"name":"setProtocolFee","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_strategy","type":"address"}],"name":"setStrategy","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"strategy","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"contract IERC20","name":"token","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"address","name":"to","type":"address"}],"name":"sweep","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"tickSpacing","outputs":[{"internalType":"int24","name":"","type":"int24"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"token0","outputs":[{"internalType":"contract IERC20","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"token1","outputs":[{"internalType":"contract IERC20","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"recipient","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"sender","type":"address"},{"internalType":"address","name":"recipient","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"uniswapV3MintCallback","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"int256","name":"amount0Delta","type":"int256"},{"internalType":"int256","name":"amount1Delta","type":"int256"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"uniswapV3SwapCallback","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"shares","type":"uint256"},{"internalType":"uint256","name":"amount0Min","type":"uint256"},{"internalType":"uint256","name":"amount1Min","type":"uint256"},{"internalType":"address","name":"to","type":"address"}],"name":"withdraw","outputs":[{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"}],"stateMutability":"nonpayable","type":"function"}];


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

/**
 * USDC/ETH
 * 0x33cB657E7fd57F1f2d5f392FB78D5FA80806d1B4
 * 0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc
 * 0x9bF7B46C7aD5ab62034e9349Ab912C0345164322
 * 0x716bd8A7f8A44B010969A1825ae5658e7a18630D
 * 14170521
 */

/**
 * BTC/ETH
 * 0xE801c4175A0341e65dFef8F3B79e1889047AfEbb
 * 0xbb2b8038a1640196fbe3e38816f3e67cba72d940
 * null
 * 0x97491b65c9c8e8754b5c55ed208ff490b2ee6190
 * 14170521
 */

const COINMARKETCAP_API_KEY = process.env.COINMARKETCAP_API_KEY; // Free API keys are available. If your needs go beyond what the free tier allows, let us know in Discord!
const BLEND_POOL_ADDRESS = "0x33cB657E7fd57F1f2d5f392FB78D5FA80806d1B4";
const BLEND_POOL_CREATION_BLOCK = 14170521;
const CURRENT_BLOCK = 14918352;
const SECONDS_PER_BLOCK = 13;

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

async function getPricePerShare(blend, prices, symbol0, symbol1, decimals0, decimals1) {
  let res = await blend.getInventory();
  const inventory0 = new Big(res.inventory0.toString(10));
  const inventory1 = new Big(res.inventory1.toString(10));
  const totalSupply = new Big((await blend.totalSupply()).toString(10));

  if (totalSupply.eq(0)) return false;

  const tvl0 = inventory0.mul(prices[symbol0]).div(`1e${decimals0}`);
  const tvl1 = inventory1.mul(prices[symbol1]).div(`1e${decimals1}`);
  return tvl0.plus(tvl1).div(totalSupply.div('1e18'));
}

async function getAPRHistory(blendPoolAddress, blockFromWhichPollingBegins, blockInterval, blockAtWhichPollingEnds) {
  const totalBlocks = blockAtWhichPollingEnds - blockFromWhichPollingBegins;
  let blockNumber = blockAtWhichPollingEnds
  await forkAt(blockNumber);

  const blend = await AloeBlend.at(blendPoolAddress);

  const token0 = await ERC20.at(await blend.TOKEN0());
  const token1 = await ERC20.at(await blend.TOKEN1());
  const symbol0 = await token0.symbol();
  const symbol1 = await token1.symbol();
  const decimals0 = await token0.decimals();
  const decimals1 = await token1.decimals();

  const block = await web3.eth.getBlock(blockNumber);
  const prices = await getAvgOfNearestHourlyOpenClose(block.timestamp, [symbol0, symbol1]);

  let summaries = [];

  const N = Math.floor(totalBlocks / blockInterval);
  for (let i = 0; i < N; i++) {
    console.log(`Progress: ${i} / ${N}`);

    blockNumber = Math.floor(blockFromWhichPollingBegins + i * blockInterval);
    await forkAt(blockNumber);
    const block = await web3.eth.getBlock(blockNumber);
    
    // Aloe Blend data
    const pricePerShare = await getPricePerShare(blend, prices, symbol0, symbol1, decimals0, decimals1);
    if (!pricePerShare) continue;

    const summary = {
      'timestamp': block.timestamp,
      'price0': prices[symbol0],
      'price1': prices[symbol1],
      'pricePerShareBlend': pricePerShare.toFixed(8),
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

const blockFromWhichPollingBegins = BLEND_POOL_CREATION_BLOCK + 1;
const blockAtWhichPollingEnds = CURRENT_BLOCK - 1;
const pollingInterval = 60 * 60 * 48;

getAPRHistory(
  BLEND_POOL_ADDRESS,
  blockFromWhichPollingBegins,
  pollingInterval / SECONDS_PER_BLOCK,
  blockAtWhichPollingEnds
).then((summaries) => {
  fs.writeFileSync('scripts/results/performance.json', JSON.stringify(summaries));
});
