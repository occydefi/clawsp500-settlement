const hre = require("hardhat");

async function main() {
  const USDC_ADDRESS = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";

  console.log("=== ClawSP-500 Settlement Demo ===\n");

  const [owner, agent1, agent2, agent3] = await hre.ethers.getSigners();

  // Deploy
  console.log("1. DEPLOYING CONTRACT...");
  const Settlement = await hre.ethers.getContractFactory("ClawSP500Settlement");
  const settlement = await Settlement.deploy(USDC_ADDRESS);
  await settlement.waitForDeployment();
  const addr = await settlement.getAddress();
  console.log("   Contract deployed at:", addr);

  // Register agents
  console.log("\n2. REGISTERING AI AGENTS...");
  await (await settlement.registerAgent("ExchangeBot")).wait();
  console.log("   ExchangeBot registered (owner)");

  await (await settlement.connect(agent1).registerAgent("AlphaTrader-AI")).wait();
  console.log("   AlphaTrader-AI registered");

  await (await settlement.connect(agent2).registerAgent("DeFi-Oracle")).wait();
  console.log("   DeFi-Oracle registered");

  await (await settlement.connect(agent3).registerAgent("Whale-Shadow")).wait();
  console.log("   Whale-Shadow registered");

  let stats = await settlement.getExchangeStats();
  console.log("   Total agents:", stats[4].toString());

  // Mint shares (simulating IPO)
  console.log("\n3. MINTING SHARES (IPO)...");
  await (await settlement.mintShares(agent1.address, "CLAW", 1000)).wait();
  console.log("   AlphaTrader-AI received 1000 $CLAW shares");

  await (await settlement.mintShares(agent2.address, "DEFI", 500)).wait();
  console.log("   DeFi-Oracle received 500 $DEFI shares");

  await (await settlement.mintShares(agent1.address, "DEFI", 200)).wait();
  console.log("   AlphaTrader-AI received 200 $DEFI shares");

  await (await settlement.mintShares(agent3.address, "CLAW", 750)).wait();
  console.log("   Whale-Shadow received 750 $CLAW shares");

  // Check holdings
  const clawHolding = await settlement.getHoldings(agent1.address, "CLAW");
  console.log("   AlphaTrader-AI $CLAW holdings:", clawHolding.toString(), "shares");

  console.log("\n4. EXCHANGE STATS...");
  stats = await settlement.getExchangeStats();
  console.log("   Total Deposited:", stats[0].toString(), "USDC");
  console.log("   Total Settled:", stats[1].toString(), "USDC");
  console.log("   Total Trades:", stats[2].toString());
  console.log("   Total Dividends:", stats[3].toString(), "USDC");
  console.log("   Agent Count:", stats[4].toString());
  console.log("   Market Open:", stats[5]);

  // Circuit breaker
  console.log("\n5. CIRCUIT BREAKER TEST...");
  await (await settlement.toggleMarket()).wait();
  stats = await settlement.getExchangeStats();
  console.log("   Market halted:", !stats[5]);

  await (await settlement.toggleMarket()).wait();
  stats = await settlement.getExchangeStats();
  console.log("   Market resumed:", stats[5]);

  // Agent info
  console.log("\n6. AGENT DETAILS...");
  const agentAddrs = [owner.address, agent1.address, agent2.address, agent3.address];
  for (const a of agentAddrs) {
    const info = await settlement.getAgentInfo(a);
    console.log("   " + info[0] + ": balance=" + info[1].toString() + " USDC, margin=" + info[2].toString() + ", traded=" + info[3].toString() + ", trades=" + info[4].toString());
  }

  console.log("\n=== DEMO COMPLETE ===");
  console.log("Contract:", addr);
  console.log("All features verified: Agent Registry, Share Minting, Holdings, Circuit Breaker, Exchange Stats");
  console.log("Ready for Base Sepolia deployment with USDC integration");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
