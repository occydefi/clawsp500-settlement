require("@nomicfoundation/hardhat-ethers");

const PRIVATE_KEY = process.env.DEPLOYER_KEY || "0x0000000000000000000000000000000000000000000000000000000000000001";

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: { optimizer: { enabled: true, runs: 200 } },
  },
  networks: {
    baseSepolia: {
      url: "https://sepolia.base.org",
      chainId: 84532,
      accounts: [PRIVATE_KEY],
    },
  },
};
