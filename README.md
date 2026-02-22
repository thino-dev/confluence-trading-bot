# Confluence Trading System — MT5 Expert Advisor

A 4-layer Smart Money Concepts (SMC) confluence scoring EA for MetaTrader 5. Scans 12 forex pairs, scores setups on a 0–12 scale, and executes market orders when price reaches Order Block zones.

## Architecture

```
Experts/
  ConfluenceTradingSystem.mq5   — Main EA (OnInit, OnTick, OnTimer, OnDeinit)

Include/Confluence/
  Inputs.mqh                    — All configurable inputs (timeframes, risk, symbols)
  Constants.mqh                 — Enums, score thresholds, magic number
  Types.mqh                     — Structs (ScoreCard, ManagedPosition, PendingSetup)
  Utilities.mqh                 — Logging, symbol parsing, helpers

  # Layer 1 — Structure (mandatory gate)
  MarketData.mqh                — OHLC data, indicators, new-bar detection
  SwingDetector.mqh             — Swing high/low identification
  StructureAnalyzer.mqh         — BOS / CHoCH detection
  OrderBlockDetector.mqh        — Order Block identification

  # Layer 2 — Confluence signals
  ZoneAnalysis.mqh              — Premium/Discount zone analysis
  LiquiditySweep.mqh            — Liquidity sweep detection
  FairValueGap.mqh              — FVG identification
  InducementDetector.mqh        — Inducement pattern detection

  # Layer 3 — Technical confirmation
  TechnicalIndicators.mqh       — RSI, MACD, Stochastic, Volume
  LinearRegressionChannel.mqh   — LRC calculation
  ATRAnalyzer.mqh               — ATR-based volatility analysis
  VWAPCalculator.mqh            — VWAP calculation
  PreviousDayLevels.mqh         — Previous day H/L/C levels

  # Layer 4 — Timing & context
  SessionManager.mqh            — London/NY session detection
  NewsFilter.mqh                — High-impact news avoidance (MT5 Calendar)
  MicroStructureShift.mqh       — M5 micro BOS/CHoCH confirmation

  # Scoring & execution
  ScoringEngine.mqh             — 4-layer scoring (0–12 scale)
  TradeExecutor.mqh             — Zone preparation & market execution
  OrderExpirationManager.mqh    — Zone expiry & re-scoring (3-candle max)

  # Risk & position management
  RiskManager.mqh               — Position sizing (% risk per trade)
  TradeManager.mqh              — Trailing stop, break-even, partial close
  TradeInvalidator.mqh          — Setup invalidation checks
  CorrelationGuard.mqh          — Correlated pair exposure limit

  # Tracking & UI
  Dashboard.mqh                 — On-chart dashboard (12-pair status grid)
  AlertManager.mqh              — MT5 alerts & push notifications
  TradeJournal.mqh              — CSV trade journal logging
  WinRateTracker.mqh            — Per-symbol win rate tracking
  StreakManager.mqh              — Win/loss streak tracking
  AdaptiveOptimizer.mqh         — Signal lift learning & weight adjustment
```

## Scoring System

| Score | Quality   | Action  |
|-------|-----------|---------|
| 0–6   | NEUTRAL   | REJECT  |
| 7     | WATCH     | REJECT  |
| 8     | CONSIDER  | TRADE   |
| 9–10  | STRONG    | TRADE   |
| 11–12 | PREMIUM   | TRADE   |

Layer 1 (Structure) is a mandatory gate — if BOS/CHoCH + Order Block aren't present, the setup is rejected regardless of other scores.

## Current Configuration (Day Trading)

| Setting              | Value   | Purpose                              |
|----------------------|---------|--------------------------------------|
| Trend timeframe      | H4      | Higher timeframe trend direction     |
| Execution timeframe  | M15     | Zone discovery scan (every 15 min)   |
| Entry timeframe      | M15     | Entry signal triggers                |
| Micro timeframe      | M5      | Micro structure shift confirmation   |
| News buffer          | 60 min  | Avoid trading around news events     |
| Risk per trade       | 2%      | Account risk per position            |
| Max positions        | 3       | Max simultaneous open trades         |
| Zone expiry          | 3 bars  | Max candles before zone re-scored    |

## Symbols (default)

EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD, USDCAD, NZDUSD, EURGBP, EURJPY, GBPJPY, AUDJPY, XAUUSD

## Prerequisites

- **MetaTrader 5** installed on your computer ([download here](https://www.metatrader5.com/en/download))
- A **broker account** connected to MT5 (demo or live)

## Installation (Step by Step)

### Step 1: Download this project

Click the green **Code** button at the top of this page, then click **Download ZIP**. Extract the ZIP to any folder on your computer (e.g., your Desktop).

Alternatively, if you have Git installed:
```
git clone https://github.com/gitDivine/confluence-trading-bot.git
```

### Step 2: Open your MT5 data folder

1. Open **MetaTrader 5**
2. Click **File** (top-left menu) → **Open Data Folder**
3. A Windows Explorer window will open — double-click the **MQL5** folder inside it
4. Keep this window open — you'll paste files here in the next step

### Step 3: Copy the bot files into MT5

Go back to the folder where you downloaded/extracted this project. You'll see two folders: **Include** and **Experts**.

1. Copy the **Include** folder and paste it into the **MQL5** folder you opened in Step 2
2. Copy the **Experts** folder and paste it into the same **MQL5** folder
3. If Windows asks "Do you want to merge/replace?", click **Yes**

When done correctly, you should see these files exist:
- `MQL5\Include\Confluence\Inputs.mqh` (and 33 other .mqh files)
- `MQL5\Experts\ConfluenceTradingSystem.mq5`

### Step 4: Add the 12 symbols to Market Watch

1. In MetaTrader 5, press **Ctrl+U** on your keyboard — the Symbols window opens
2. In the search bar, type each symbol name (e.g., `EURUSD`) and double-click it to add
3. Repeat for all 12 symbols: EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD, USDCAD, NZDUSD, EURGBP, EURJPY, GBPJPY, AUDJPY, XAUUSD
4. Click **OK** when done

**Note:** Some brokers add a suffix to symbol names (e.g., `EURUSDm` or `EURUSD.pro`). If your broker does this, set the suffix in the EA settings later (Step 6).

### Step 5: Compile the bot

1. In MetaTrader 5, press **F4** — this opens **MetaEditor**
2. On the left panel, navigate to **Expert Advisors** → double-click **ConfluenceTradingSystem.mq5** to open it
3. Press **F7** to compile
4. Look at the bottom panel — it should say **0 errors**. Warnings are OK, errors are not
5. Go back to MetaTrader 5 (click it in your taskbar or press **Alt+Tab**)

### Step 6: Attach the bot to a chart

1. In MetaTrader 5, open any chart — right-click any symbol in Market Watch (e.g., EURUSD) and select **Chart Window**
2. Press **Ctrl+N** to open the **Navigator** panel on the left side
3. Expand **Expert Advisors** — you should see **ConfluenceTradingSystem**
4. **Drag** it from the Navigator onto your chart
5. A settings popup will appear:
   - Go to the **Common** tab and check **Allow Algo Trading**
   - Go to the **Inputs** tab — here you can change settings like risk %, symbols, etc. (or leave defaults)
   - Click **OK**
6. **Important:** Click the **AutoTrading** button in the MT5 toolbar at the top. It must show a **green icon** (not red). If it's red, the bot cannot trade.

### Step 7: Risk confirmation

When the bot starts, a popup will appear showing your risk settings:
- **Risk per trade** — what % of your account you risk on each trade (default: 2%)
- **Max daily loss** — the bot stops trading if you lose this much in one day (default: 5%)
- **Max positions** — how many trades can be open at once (default: 3)

It also shows the actual dollar amount at risk based on your account size.

- Click **Yes** to start the bot with these settings
- Click **No** to stop — then right-click the EA on your chart → **Properties** → **Inputs** tab to change any setting, then re-attach

### Step 8: Verify it's running

- You should see a **dashboard** on your chart showing all 12 symbols
- The bot will perform its first scan within 15 minutes
- Check the **Experts** tab at the bottom of MT5 (press **Ctrl+T**, then click the **Experts** tab) to see the bot's log messages

## How It Works

1. **Every 15 minutes** — scans all 12 pairs through the 4-layer scoring engine
2. **Score >= 8** — prepares an OB zone (stores zone boundaries internally)
3. **Every tick** — monitors active zones; when price enters an OB zone, fires a market order
4. **Zone expiry** — if price doesn't reach the zone within 3 candles, the setup is re-scored. If score drops below 8, the zone is removed
5. **Position management** — trailing stop, break-even move, and partial close are handled automatically

## Disclaimer

This bot is provided as-is for educational and personal use. Trading forex involves significant risk of loss. Past performance does not guarantee future results. Always test on a **demo account** before using real money. The author is not responsible for any financial losses incurred from using this software.

## License

MIT — free to use, modify, and share.
