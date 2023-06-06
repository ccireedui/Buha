import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-abi-exporter";
require("dotenv").config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    test: {
      url: "http://127.0.0.1:8545",
    },
    klaytn: {
      chainId: 8217,
      url: "https://klaytn02.fandom.finance",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    klaytnTest: {
      chainId: 1001,
      url: "https://api.baobab.klaytn.net:8651",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    polygonMumbai: {
      chainId: 80001,
      url: "https://matic-mumbai.chainstacklabs.com",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    polygon: {
      chainId: 137,
      url: "https://polygon.llamarpc.com",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    sepoliaTest: {
      chainId: 11155111,
      url: "https://rpc.sepolia.org",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    goerliTest: {
      chainId: 5,
      url: "https://rpc.ankr.com/eth_goerli",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    ethereum: {
      chainId: 1,
      url: "https://eth.llamarpc.com",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    evmosTest: {
      chainId: 9000,
      url: "https://eth.bd.evmos.dev:8545",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    bscTest: {
      chainId: 97,
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    bsc: {
      chainId: 56,
      url: "https://bsc-dataseed1.ninicoin.io",
      accounts: [process.env.PRIVATE_KEY as string],
    },
  },
  etherscan: {
    apiKey: {
      goerli: process.env.ETHERSCAN_KEY as string,
      sepolia: process.env.ETHERSCAN_KEY as string,
      polygon: process.env.POLYGONSCAN_KEY as string,
      polygonMumbai: process.env.POLYGONSCAN_KEY as string,
    },
  },
  abiExporter: {
    path: "./app/abi",
    runOnCompile: true,
    clear: true,
    flat: true,
    spacing: 2,
  },
};

export default config;
