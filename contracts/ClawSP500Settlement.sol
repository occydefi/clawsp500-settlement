// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ClawSP-500 Settlement Contract
 * @notice On-chain settlement layer for the ClawSP-500 AI Agent Stock Exchange
 * @dev Handles USDC deposits, trade settlement, dividend distribution, and margin for futures
 *
 * Architecture:
 * - Agents deposit USDC to get exchange credits
 * - Trades between agents are settled atomically on-chain
 * - Dividends from profitable stocks are distributed pro-rata
 * - Futures positions require margin locked in the contract
 * - Circuit breaker for emergency market halts
 */

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract ClawSP500Settlement {
    // ============ STATE ============

    IERC20 public immutable usdc;
    address public owner;
    bool public marketOpen;
    uint256 public totalDeposited;
    uint256 public totalSettled;
    uint256 public totalTrades;
    uint256 public totalDividendsPaid;
    uint256 public tradeCounter;

    // Agent registry
    struct Agent {
        string name;
        uint256 balance;          // Available USDC balance (6 decimals)
        uint256 lockedMargin;     // Margin locked for futures
        uint256 totalTraded;      // Total volume traded
        uint256 totalPnl;         // Cumulative P&L
        uint256 tradeCount;
        uint256 registeredAt;
        bool active;
    }

    // Trade record
    struct Trade {
        uint256 id;
        address buyer;
        address seller;
        string ticker;
        uint256 quantity;
        uint256 pricePerShare;    // Price in USDC (6 decimals)
        uint256 totalAmount;
        uint256 timestamp;
        TradeType tradeType;
    }

    // Dividend record
    struct Dividend {
        string ticker;
        uint256 totalAmount;
        uint256 perShareAmount;
        uint256 timestamp;
        uint256 recipients;
    }

    // Futures position
    struct FuturesPosition {
        address agent;
        string contractId;
        bool isLong;
        uint256 size;             // Position size in USDC
        uint256 entryPrice;
        uint256 margin;           // Locked margin
        uint256 leverage;
        uint256 openedAt;
        bool active;
    }

    enum TradeType { SPOT, FUTURES_OPEN, FUTURES_CLOSE, DIVIDEND }

    mapping(address => Agent) public agents;
    address[] public agentList;
    Trade[] public trades;
    Dividend[] public dividends;
    FuturesPosition[] public futuresPositions;
    mapping(address => uint256[]) public agentFutures;  // agent -> position indices

    // Stock holdings: agent -> ticker -> shares
    mapping(address => mapping(string => uint256)) public holdings;

    // ============ EVENTS ============

    event AgentRegistered(address indexed agent, string name, uint256 timestamp);
    event Deposited(address indexed agent, uint256 amount);
    event Withdrawn(address indexed agent, uint256 amount);
    event TradeSettled(uint256 indexed tradeId, address buyer, address seller, string ticker, uint256 quantity, uint256 price);
    event DividendPaid(string ticker, uint256 totalAmount, uint256 recipients);
    event FuturesOpened(address indexed agent, uint256 positionId, string contractId, bool isLong, uint256 size, uint256 leverage);
    event FuturesClosed(address indexed agent, uint256 positionId, int256 pnl);
    event MarginLocked(address indexed agent, uint256 amount);
    event MarginReleased(address indexed agent, uint256 amount);
    event CircuitBreaker(bool marketOpen, uint256 timestamp);

    // ============ MODIFIERS ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyRegistered() {
        require(agents[msg.sender].active, "Not registered");
        _;
    }

    modifier whenMarketOpen() {
        require(marketOpen, "Market closed");
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
        owner = msg.sender;
        marketOpen = true;
    }

    // ============ AGENT MANAGEMENT ============

    function registerAgent(string calldata name) external {
        require(!agents[msg.sender].active, "Already registered");
        agents[msg.sender] = Agent({
            name: name,
            balance: 0,
            lockedMargin: 0,
            totalTraded: 0,
            totalPnl: 0,
            tradeCount: 0,
            registeredAt: block.timestamp,
            active: true
        });
        agentList.push(msg.sender);
        emit AgentRegistered(msg.sender, name, block.timestamp);
    }

    // ============ DEPOSIT / WITHDRAW ============

    function deposit(uint256 amount) external onlyRegistered {
        require(amount > 0, "Zero amount");
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        agents[msg.sender].balance += amount;
        totalDeposited += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external onlyRegistered {
        require(amount > 0, "Zero amount");
        require(agents[msg.sender].balance >= amount, "Insufficient balance");
        agents[msg.sender].balance -= amount;
        require(usdc.transfer(msg.sender, amount), "Transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    // ============ TRADE SETTLEMENT ============

    /// @notice Settle a spot trade between buyer and seller
    /// @dev Called by the exchange backend after matching orders
    function settleTrade(
        address buyer,
        address seller,
        string calldata ticker,
        uint256 quantity,
        uint256 pricePerShare
    ) external onlyOwner whenMarketOpen {
        require(agents[buyer].active && agents[seller].active, "Agents not registered");
        uint256 totalAmount = quantity * pricePerShare / 1e6; // Adjust for 6 decimal USDC
        require(agents[buyer].balance >= totalAmount, "Buyer insufficient balance");
        require(holdings[seller][ticker] >= quantity, "Seller insufficient shares");

        // Atomic settlement
        agents[buyer].balance -= totalAmount;
        agents[seller].balance += totalAmount;
        holdings[buyer][ticker] += quantity;
        holdings[seller][ticker] -= quantity;

        // Record trade
        uint256 tradeId = tradeCounter++;
        trades.push(Trade({
            id: tradeId,
            buyer: buyer,
            seller: seller,
            ticker: ticker,
            quantity: quantity,
            pricePerShare: pricePerShare,
            totalAmount: totalAmount,
            timestamp: block.timestamp,
            tradeType: TradeType.SPOT
        }));

        // Update stats
        agents[buyer].totalTraded += totalAmount;
        agents[seller].totalTraded += totalAmount;
        agents[buyer].tradeCount++;
        agents[seller].tradeCount++;
        totalSettled += totalAmount;
        totalTrades++;

        emit TradeSettled(tradeId, buyer, seller, ticker, quantity, pricePerShare);
    }

    /// @notice Mint shares to an agent (for IPO, stock splits, etc.)
    function mintShares(address agent, string calldata ticker, uint256 quantity) external onlyOwner {
        require(agents[agent].active, "Agent not registered");
        holdings[agent][ticker] += quantity;
    }

    // ============ DIVIDEND DISTRIBUTION ============

    /// @notice Distribute dividends to all holders of a stock
    function distributeDividend(
        string calldata ticker,
        uint256 totalAmount,
        address[] calldata holders,
        uint256[] calldata shares,
        uint256 totalShares
    ) external onlyOwner {
        require(holders.length == shares.length, "Array mismatch");
        require(totalShares > 0, "No shares");

        uint256 distributed = 0;
        for (uint256 i = 0; i < holders.length; i++) {
            if (agents[holders[i]].active && shares[i] > 0) {
                uint256 payout = totalAmount * shares[i] / totalShares;
                agents[holders[i]].balance += payout;
                distributed += payout;
            }
        }

        dividends.push(Dividend({
            ticker: ticker,
            totalAmount: distributed,
            perShareAmount: totalAmount / totalShares,
            timestamp: block.timestamp,
            recipients: holders.length
        }));

        totalDividendsPaid += distributed;
        emit DividendPaid(ticker, distributed, holders.length);
    }

    // ============ FUTURES ============

    /// @notice Open a leveraged futures position
    function openFutures(
        string calldata contractId,
        bool isLong,
        uint256 size,
        uint256 entryPrice,
        uint256 leverage
    ) external onlyRegistered whenMarketOpen {
        require(leverage >= 1 && leverage <= 10, "Leverage 1-10x");
        uint256 margin = size / leverage;
        require(agents[msg.sender].balance >= margin, "Insufficient margin");

        agents[msg.sender].balance -= margin;
        agents[msg.sender].lockedMargin += margin;

        uint256 posId = futuresPositions.length;
        futuresPositions.push(FuturesPosition({
            agent: msg.sender,
            contractId: contractId,
            isLong: isLong,
            size: size,
            entryPrice: entryPrice,
            margin: margin,
            leverage: leverage,
            openedAt: block.timestamp,
            active: true
        }));

        agentFutures[msg.sender].push(posId);

        emit FuturesOpened(msg.sender, posId, contractId, isLong, size, leverage);
        emit MarginLocked(msg.sender, margin);
    }

    /// @notice Close a futures position and realize P&L
    function closeFutures(uint256 positionId, uint256 exitPrice) external onlyOwner {
        FuturesPosition storage pos = futuresPositions[positionId];
        require(pos.active, "Position not active");

        int256 pnl;
        if (pos.isLong) {
            pnl = int256(exitPrice) - int256(pos.entryPrice);
        } else {
            pnl = int256(pos.entryPrice) - int256(exitPrice);
        }
        pnl = pnl * int256(pos.size) / int256(pos.entryPrice);

        pos.active = false;
        agents[pos.agent].lockedMargin -= pos.margin;

        if (pnl >= 0) {
            agents[pos.agent].balance += pos.margin + uint256(pnl);
            agents[pos.agent].totalPnl += uint256(pnl);
        } else {
            uint256 loss = uint256(-pnl);
            if (loss >= pos.margin) {
                // Liquidated - lose entire margin
                agents[pos.agent].balance += 0;
            } else {
                agents[pos.agent].balance += pos.margin - loss;
            }
        }

        emit FuturesClosed(pos.agent, positionId, pnl);
        emit MarginReleased(pos.agent, pos.margin);
    }

    // ============ CIRCUIT BREAKER ============

    function toggleMarket() external onlyOwner {
        marketOpen = !marketOpen;
        emit CircuitBreaker(marketOpen, block.timestamp);
    }

    // ============ VIEW FUNCTIONS ============

    function getAgentInfo(address agent) external view returns (
        string memory name, uint256 balance, uint256 lockedMargin,
        uint256 totalTraded, uint256 tradeCount, bool active
    ) {
        Agent storage a = agents[agent];
        return (a.name, a.balance, a.lockedMargin, a.totalTraded, a.tradeCount, a.active);
    }

    function getHoldings(address agent, string calldata ticker) external view returns (uint256) {
        return holdings[agent][ticker];
    }

    function getTradeCount() external view returns (uint256) {
        return trades.length;
    }

    function getTrade(uint256 id) external view returns (Trade memory) {
        return trades[id];
    }

    function getDividendCount() external view returns (uint256) {
        return dividends.length;
    }

    function getAgentCount() external view returns (uint256) {
        return agentList.length;
    }

    function getFuturesCount() external view returns (uint256) {
        return futuresPositions.length;
    }

    function getExchangeStats() external view returns (
        uint256 _totalDeposited, uint256 _totalSettled, uint256 _totalTrades,
        uint256 _totalDividendsPaid, uint256 _agentCount, bool _marketOpen
    ) {
        return (totalDeposited, totalSettled, totalTrades, totalDividendsPaid, agentList.length, marketOpen);
    }
}
