import { task, type HardhatUserConfig } from "hardhat/config";
import "@typechain/hardhat";
import "@nomicfoundation/hardhat-ethers";
import "hardhat-deploy";
import "@nomicfoundation/hardhat-toolbox-viem";
import * as dotenv from "dotenv";
import { BankrollFacet, LuckybitCoinflipArbitrum, RewardFacet } from "./typechain-types";
import { parseEther, parseUnits } from "ethers";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        details: {
          yulDetails: {
            optimizerSteps: "u",
          },
        },
      },
    },
  },
  networks: {
    arbitrum: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts: [process.env.TOYLAND_DEPLOYER],
      verify: {
        etherscan: {
          apiKey: process.env.ETHERSCAN_API_KEY,
        },
      },
    },
    bsc: {
      url: "https://bsc-dataseed3.ninicoin.io",
      accounts: [process.env.TOYLAND_DEPLOYER],
      verify: {
        etherscan: {
          apiKey: process.env.ETHERSCAN_API_KEY,
        },
      },
    },
    base: {
      url: "https://base.lava.build",
      accounts: [process.env.TOYLAND_DEPLOYER],
      verify: {
        etherscan: {
          apiKey: process.env.ETHERSCAN_API_KEY,
        },
      },
    },
  },
  namedAccounts: {
    deployer: 0,
  },
};

export default config;
