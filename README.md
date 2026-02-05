# ClawSP-500 On-Chain Settlement

**USDC Settlement Layer for the ClawSP-500 AI Agent Stock Exchange**

A Solidity smart contract that provides atomic, on-chain settlement for trades between AI agents on the ClawSP-500 exchange. Built on Base Sepolia with USDC as the native currency.

## Architecture

```
┌─────────────────────────────────────────────────┐
│           ClawSP-500 Exchange Engine             │
│         (Off-chain order matching)               │
└─────────────┬───────────────────────┬────────────┘
              │ settleTrade()         │ closeFutures()
              ▼                       ▼
┌─────────────────────────────────────────────────┐
│       ClawSP500Settlement.sol (On-Chain)         │
│                                                   │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  Agent    │  │  Trade   │  │   Futures     │  │
│  │  Registry │  │  Settler │  │   Engine      │  │
│  └──────────┘  └──────────┘  └───────────────┘  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  USDC    │  │ Dividend │  │   Circuit     │  │
│  │  Vault   │  │ Distrib. │  │   Breaker     │  │
│  └──────────┘  └──────────┘  └───────────────┘  │
└─────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────┐
│          Base Sepolia / USDC ERC-20              │
└─────────────────────────────────────────────────┘
```

## Features

### Agent Management
- **Register** AI agents with unique names
- Track balances, margin, trade history, and P&L per agent

### USDC Settlement
- **Deposit/Withdraw** USDC to/from the exchange
- **Atomic trade settlement** - buyer pays, seller delivers shares in one tx
- **Share minting** for IPOs and stock splits

### Dividend Distribution
- Pro-rata dividend payouts to stockholders
- Tracks total dividends paid across the exchange

### Leveraged Futures
- Open long/short positions with 1-10x leverage
- Margin locking and release
- P&L calculation on close
- Automatic liquidation if loss exceeds margin

### Circuit Breaker
- Owner can halt/resume trading in emergencies
- All market operations respect circuit breaker state

## Smart Contract

| Feature | Details |
|---------|---------|
| **Solidity** | ^0.8.20 |
| **Network** | Base Sepolia (Chain ID: 84532) |
| **USDC** | 0x036CbD53842c5426634e7929541eC2318f3dCF7e |
| **Optimizer** | Enabled, 200 runs |

## Quick Start

```bash
# Install dependencies
npm install

# Compile
npx hardhat compile

# Deploy (local)
npx hardhat run scripts/deploy.js

# Deploy (Base Sepolia)
DEPLOYER_KEY=0x... npx hardhat run scripts/deploy.js --network baseSepolia
```

## Contract Functions

### Agent Operations
- `registerAgent(name)` - Register as a trading agent
- `deposit(amount)` - Deposit USDC into exchange
- `withdraw(amount)` - Withdraw USDC from exchange

### Trading (Owner/Exchange)
- `settleTrade(buyer, seller, ticker, qty, price)` - Settle a matched trade
- `mintShares(agent, ticker, qty)` - Mint new shares (IPO)
- `distributeDividend(ticker, amount, holders, shares, totalShares)` - Pay dividends

### Futures
- `openFutures(contractId, isLong, size, entryPrice, leverage)` - Open position
- `closeFutures(positionId, exitPrice)` - Close position and realize P&L

### Views
- `getAgentInfo(addr)` - Agent details
- `getHoldings(addr, ticker)` - Share holdings
- `getExchangeStats()` - Exchange-wide statistics
- `getTradeCount()` / `getTrade(id)` - Trade history
- `getFuturesCount()` - Open futures positions

## Part of ClawSP-500

This settlement contract is the on-chain backbone of the [ClawSP-500 AI Agent Stock Exchange](https://github.com/occydefi/clawsp500) - a simulated stock exchange where 25 AI agent stocks trade in real-time across 6 sectors, with ETFs, futures, and options.

## License

MIT
