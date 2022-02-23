const hre = require("hardhat");
const { artifacts } = require("hardhat");
const { Address, BN } = require("ethereumjs-util");

const inquirer = require('inquirer')

const Factory = artifacts.require("Factory");
const VolatilityOracle = artifacts.require("VolatilityOracle");
const IUniswapV3Pool = artifacts.require("IUniswapV3Pool");

const availableSilos = [
  {
    name: 'cETH (0x0a230CCa01f7107933D5355913E9a65082F37c52)',
    short: 'cETH',
    value: '0x0a230CCa01f7107933D5355913E9a65082F37c52',
  },
  {
    name: 'cUSDC (0x723bFE564661536FDFfa3E9e060135928d3bf18F)',
    short: 'cUSDC',
    value: '0x723bFE564661536FDFfa3E9e060135928d3bf18F',
  },
  {
    name: 'fETH 8 (0xbA9aD27Ed23b5E002e831514E69554815a5820b3)',
    short: 'fETH 8',
    value: '0xbA9aD27Ed23b5E002e831514E69554815a5820b3',
  },
  {
    name: 'fDAI 8 (0x1F8095A26586abB27874Dd53a12a3AF25226DcB0)',
    short: 'fDAI 8',
    value: '0x1F8095A26586abB27874Dd53a12a3AF25226DcB0',
  },
  {
    name: 'fFEI 8 (0x0770D239e56d96bC1E049B94949B0a0199B77cf6)',
    short: 'fFEI 8',
    value: '0x0770D239e56d96bC1E049B94949B0a0199B77cf6',
  },
  {
    name: 'fTRIBE 8 (0x2A9855dc8AFa59E6067287B8aa15cd009938d137)',
    short: 'fTRIBE 8',
    value: '0x2A9855dc8AFa59E6067287B8aa15cd009938d137',
  },
  {
    name: 'fRAI 9 (0xf70FC6b694D911b1F665b754f77EC5e83D340594)',
    short: 'fRAI 9',
    value: '0xf70FC6b694D911b1F665b754f77EC5e83D340594',
  },
  {
    name: 'yvWBTC (0xdA2D30c659cFEb176053B22Be11fc351e077FDc0)',
    short: 'yvWBTC',
    value: '0xdA2D30c659cFEb176053B22Be11fc351e077FDc0',
  },
  {
    name: 'yvWETH (0x8f43969d04ba8aAeC7C69813a07A276189c574D2)',
    short: 'yvWETH',
    value: '0x8f43969d04ba8aAeC7C69813a07A276189c574D2',
  },
];


const validateAddress = (address) => {
  return (String(address).startsWith('0x') && String(address).length === 42) ? true : 'Oops! Are you sure that\'s an address?';
};

const questions = [
  {
    type: 'input',
    name: 'factory_address',
    message: 'What\'s the Aloe Blend factory address? (press enter for mainnet default)',
    default: '0x000000000008b34b9C428ddC00f54d49105dA313',
    validate: validateAddress,
  },
  {
    type: 'input',
    name: 'pair_address',
    message: 'What\'s the address of the Uniswap V3 pool you want the new Blend vault to be associated with?',
    validate: validateAddress,
  },
  {
    type: 'list',
    name: 'silo0_address',
    message: 'Pick a silo for token0. If you don\'t see the one you want, manually add it to the list in scripts/deploy_pair.js.',
    choices: availableSilos,
    loop: false,
  },
  {
    type: 'list',
    name: 'silo1_address',
    message: 'Pick a silo for token1. If you don\'t see the one you want, manually add it to the list in scripts/deploy_pair.js.',
    choices: availableSilos,
    loop: false,
  },
];

const App = () => {
  console.log('\n');

  inquirer.prompt(questions).then(async (answers) => {
    console.info('\nGot it! The script will perform a few sanity checks and then ask you to confirm everything before deploying.\n');

    const factory = await Factory.at(answers['factory_address']);
    const pool = await IUniswapV3Pool.at(answers['pair_address']);

    const token0 = await pool.token0({gasPrice: 0});
    const token1 = await pool.token1({gasPrice: 0});
    const silo0 = answers['silo0_address'];
    const silo1 = answers['silo1_address'];

    // VERIFY THAT VAULT DOESN'T ALREADY EXIST
    const existingVault = await factory.getVault(pool.address, silo0, silo1, {gasPrice: 0});
    if (existingVault !== '0x0000000000000000000000000000000000000000') {
      console.error(`\nA Blend Vault already exists for your chosen combination of {Uniswap pair, silo0, silo1}. It's deployed to ${existingVault}`);
      process.exit();
    }

    // VERIFY THAT POOL METADATA HAS BEEN CACHED IN VOLATILITY ORACLE
    const volatilityOracle = await VolatilityOracle.at(await factory.volatilityOracle({gasPrice: 0}));
    const cachedPoolMetadata = await volatilityOracle.cachedPoolMetadata(pool.address, {gasPrice: 0});
    if (cachedPoolMetadata.tickSpacing.eq(web3.utils.toBN(0))) {
      console.error(`\nUniswap pool metadata hasn't yet been cached in the Volatility Oracle (${volatilityOracle.address}).\nThis should be done before deploying the Blend vault.\nPlease do that and then run this script again.`);
      process.exit();
    }

    // VERIFY THAT UNISWAP ORACLE IS SUFFICIENTLY INITIALIZED
    const maxSecondsAgo = cachedPoolMetadata.maxSecondsAgo.toNumber();
    if (maxSecondsAgo < 1 * 60 * 60) {
      console.warn(`WARNING: You should increase observation cardinality on the Uniswap pool (${pool.address}) so that *at least* 1 hour of data is available. 24 hours is ideal.\n`);
    }

    // VERIFY THAT ESTIMATE24 HAS BEEN CALLED AT LEAST ONCE ON VOLATILITY ORACLE
    const impliedVolEstimates = await volatilityOracle.lens(pool.address, {gasPrice: 0});
    let didCallEstimate24H = false;
    for (let impliedVolEstimate of impliedVolEstimates) {
      if (impliedVolEstimate.eq(impliedVolEstimates[0])) continue;
      didCallEstimate24H = true;
      break;
    }
    if (!didCallEstimate24H) {
      console.error(`\nUniswap pool metadata has been cached in the Volatility Oracle (${volatilityOracle.address}), but no IV observations have been taken.\nIt's recommended that you do this before deploying the Blend vault.\nPlease run this script again after 'estimate24H' has been called at least once.`);
      process.exit();
    }

    const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);
    const nonce = await web3.eth.getTransactionCount(deployer.address);

    const requiredGas = 1.05 * (await factory.createVault.estimateGas(pool.address, silo0, silo1, {
      from: deployer.address,
      gasLimit: 6000000,
      gasPrice: 0,
      nonce: nonce,
      type: "0x0",
    }));

    inquirer.prompt([
      {
        type: 'number',
        name: 'gas_price',
        message: `Deploying will take approximately ${requiredGas.toFixed(0)} gas. What gas price would you like to use (in gwei)?`,
      },
    ]).then(extraAnswers => {
      const gwei = extraAnswers['gas_price'];
      const confirmation = `\nYou are about to deploy an Aloe Blend vault to manage liquidity in Uniswap V3 pair ${pool.address}\n\ttoken0: ${token0}\n\ttoken1: ${token1}\n\tsilo0: ${silo0}\n\tsilo1: ${silo1}\n\tUniswap oracle: ~${Math.round(maxSecondsAgo / (60 * 60))} hour sliding window of price data (24 hours is recommended!)\n\tGas: ${requiredGas.toFixed(0)} at ${gwei} gwei (${requiredGas * gwei / 1e9} ETH)\n`;

      console.info(confirmation);

      inquirer.prompt([{type: 'confirm', name: 'final_confirmation', message: 'Is this all correct?'}]).then(async (finalAnswers) => {
        if (!finalAnswers['final_confirmation']) process.exit();

        const vault = await factory.createVault(pool.address, silo0, silo1, {
          from: deployer.address,
          gasLimit: requiredGas.toFixed(0),
          gasPrice: gwei * 1e9,
          nonce: nonce,
          type: "0x0",
        });
        const vaultAddress = vault.logs[0].args.vault;

        console.info(`\nSuccessfully deployed vault!! Address: ${vaultAddress}`);
        console.info(`Please verify the contract on Etherscan with the following dapptools command:`);
        console.info(`\tdapp verify-contract contracts/AloeBlend.sol:AloeBlend ${vaultAddress} ${pool.address} ${silo0} ${silo1}\n`);

        process.exit();
      });
    });
  });
}

console.info('Initializing...');
setTimeout(App, 2000);
