require("dotenv-safe").config({ example: ".env.template" });

require("@nomiclabs/hardhat-truffle5");

require("@nomiclabs/hardhat-etherscan");

const mochaConfig = {
  timeout: 180000,
  grep: "@hardhat",
};

const compilerSettings = {
  optimizer: {
    enabled: true,
    runs: 800,
  },
  metadata: { bytecodeHash: "none" },
};

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.PROVIDER_ALCHEMY_KEY}`,
        blockNumber: 12802299,
      },
      accounts: [
        {
          privateKey:
            "0101010101010101010101010101010101010101010101010101010101010101",
          balance: "20000000000000000000",
        },
        {
          privateKey: process.env.DEPLOYER,
          balance: "20000000000000000000",
        },
      ],
    },
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.PROVIDER_ALCHEMY_KEY}`,
      timeout: 720000,
      accounts: [process.env.DEPLOYER],
      gasPrice: 85e9,
      gasMultiplier: 1.15,
    },
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${process.env.PROVIDER_ALCHEMY_KEY}`,
      timeout: 720000,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.10",
        settings: compilerSettings,
      },
    ],
  },
  paths: {
    sources: "./contracts",
    tests: "./tests",
    artifacts: "./build_hardhat",
  },
  mocha: mochaConfig,
};
