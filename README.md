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
| Risk per trade       | 1%      | Account risk per position            |
| Max positions        | 3       | Max simultaneous open trades         |
| Zone expiry          | 3 bars  | Max candles before zone re-scored    |

## Symbols (default)

EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD, USDCAD, NZDUSD, EURGBP, EURJPY, GBPJPY, AUDJPY, XAUUSD

## Installation

### 1. Locate your MT5 data folder

In MetaTrader 5: **File → Open Data Folder** → navigate to `MQL5/`

Typical path:
```
C:\Users\<YOU>\AppData\Roaming\MetaQuotes\Terminal\<TERMINAL_ID>\MQL5\
```

### 2. Copy files

Copy the project folders into your MT5 data folder:

```
# From this repo:
Include/Confluence/*.mqh  →  MQL5/Include/Confluence/*.mqh
Experts/ConfluenceTradingSystem.mq5  →  MQL5/Experts/ConfluenceTradingSystem.mq5
```

### 3. Add symbols to Market Watch

In MT5, press **Ctrl+U** (Symbols), and make sure all 12 symbols are added to your Market Watch window.

### 4. Compile

Open MetaEditor (**F4**), open `ConfluenceTradingSystem.mq5`, press **F7** to compile. Should show **0 errors**.

### 5. Attach to chart

1. Open any chart (e.g., EURUSD H1)
2. In the Navigator panel (Ctrl+N), find **Expert Advisors → ConfluenceTradingSystem**
3. Drag it onto the chart
4. In the popup, check **Allow Algo Trading**
5. Click **OK**
6. Enable the **AutoTrading** button in the MT5 toolbar (must show green)

### 6. Verify

The on-chart dashboard should appear showing all 12 symbols. After the first M15 bar completes, scores will populate.

## How It Works

1. **Every 15 minutes** — scans all 12 pairs through the 4-layer scoring engine
2. **Score >= 8** — prepares an OB zone (stores zone boundaries internally)
3. **Every tick** — monitors active zones; when price enters an OB zone, fires a market order
4. **Zone expiry** — if price doesn't reach the zone within 3 candles, the setup is re-scored. If score drops below 8, the zone is removed
5. **Position management** — trailing stop, break-even move, and partial close are handled automatically

## License

Private — not for redistribution.
