const hre = require("hardhat");

async function main() {
  // Base Sepolia USDC contract
  const USDC_ADDRESS = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";

  console.log("Deploying ClawSP-500 Settlement Contract...");
  console.log("Network:", hre.network.name);
  console.log("USDC Address:", USDC_ADDRESS);

  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");

  const Settlement = await hre.ethers.getContractFactory("ClawSP500Settlement");
  const settlement = await Settlement.deploy(USDC_ADDRESS);
  await settlement.waitForDeployment();

  const address = await settlement.getAddress();
  console.log("\n========================================");
  console.log("ClawSP-500 Settlement deployed to:", address);
  console.log("========================================\n");

  // Register the deployer as first agent
  console.log("Registering deployer as ExchangeBot...");
  const tx = await settlement.registerAgent("ClawSP500-ExchangeBot");
  await tx.wait();
  console.log("ExchangeBot registered!");

  // Verify contract stats
  const stats = await settlement.getExchangeStats();
  console.log("\nExchange Stats:");
  console.log("  Total Deposited:", stats[0].toString());
  console.log("  Total Settled:", stats[1].toString());
  console.log("  Total Trades:", stats[2].toString());
  console.log("  Agent Count:", stats[4].toString());
  console.log("  Market Open:", stats[5]);

  console.log("\nDone! Contract is live on Base Sepolia.");
  console.log("Explorer: https://sepolia.basescan.org/address/" + address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
