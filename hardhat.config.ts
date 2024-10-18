import {HardhatUserConfig} from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";

const mnemonicOrPrivateKey = "<YOUR_PRIVATE_KEY>"; // dex 1

const apiKey = "<YOUR_API_KEY>"; // polygon

const config: any = {
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
          evmVersion: "london",
        },
      },
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
          evmVersion: "london",
        },
      },
      {
        version: "0.8.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
          evmVersion: "london",
        },
      },
      {
        version: "0.8.26",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
          evmVersion: "london",
        },
      },
    ],
  },
  networks: {
    local: {
      url: "http://localhost:8545",
      gas: "auto",
    },
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    bsctest: {
      url: "https://data-seed-prebsc-1-s2.binance.org:8545",
      chainId: 97,
      accounts: [mnemonicOrPrivateKey],
    },
    amoy: {
      url: "https://rpc-amoy.polygon.technology/",
      gasPrice: 50000000000,
      chainId: 80002,
      accounts: [mnemonicOrPrivateKey],
    },
  },
  typechain: {
    outDir: "types",
    target: "ethers-v6",
  },
  etherscan: {
    apiKey: apiKey,
    customChains: [
      {
        network: "amoy",
        chainId: 80002,
        urls: {
          apiURL: "https://api-amoy.polygonscan.com/api",
          browserURL: "https://amoy.polygonscan.com/",
        },
      },
    ],
  },
  mocha: {
    timeout: 60000,
  },
  gasReporter: {
    currency: "USD",
  },
};

export default config;
