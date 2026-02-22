//+------------------------------------------------------------------+
//|                                                      Inputs.mqh   |
//|                          Confluence Trading System                 |
//|                          All configurable input parameters         |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_INPUTS_MQH
#define CONFLUENCE_INPUTS_MQH

//=============================================================================
// GENERAL
//=============================================================================
input group "=== General ==="
input string   InpSymbols        = "EURUSD,GBPUSD,USDJPY,USDCHF,USDCAD,AUDUSD,"
                                   "NZDUSD,GBPJPY,EURJPY,EURGBP,GBPAUD,EURAUD";
input string   InpSymbolSuffix   = "";              // Broker suffix (e.g. ".m" or "pro")
input int      InpMagicNumber    = 20260219;        // Magic number for order ID
input int      InpTimerSeconds   = 5;               // OnTimer interval (seconds)
input bool     InpEnableTrading  = true;            // Master switch: live trading on/off
input bool     InpEnableAlerts   = true;            // Push notifications on/off
input bool     InpShowDashboard  = true;            // On-chart dashboard on/off

//=============================================================================
// TIMEFRAMES
//=============================================================================
input group "=== Timeframes (Day Trading) ==="
input ENUM_TIMEFRAMES InpHTF_Primary   = PERIOD_H4;  // HTF: Primary trend timeframe
input ENUM_TIMEFRAMES InpHTF_Fallback1 = PERIOD_D1;  // HTF: Fallback 1
input ENUM_TIMEFRAMES InpHTF_Fallback2 = PERIOD_H1;  // HTF: Fallback 2 (last resort)
input ENUM_TIMEFRAMES InpExecutionTF   = PERIOD_M15; // Execution timeframe (scan every 15 min)
input ENUM_TIMEFRAMES InpEntryTF       = PERIOD_M15; // Entry trigger timeframe
input ENUM_TIMEFRAMES InpMicroTF1      = PERIOD_M5;  // Micro MSS timeframe 1
input ENUM_TIMEFRAMES InpMicroTF2      = PERIOD_M5;  // Micro MSS timeframe 2

//=============================================================================
// SWING DETECTION
//=============================================================================
input group "=== Swing Detection ==="
input int      InpSwingLeftBars  = 3;               // Left confirmation bars
input int      InpSwingRightBars = 3;               // Right confirmation bars
input int      InpSwingLookback  = 200;             // Bars to analyze

//=============================================================================
// STRUCTURE ANALYSIS
//=============================================================================
input group "=== Structure ==="
input int      InpMinBOSCount    = 3;               // Minimum consecutive BOS required
input double   InpMinRR          = 1.5;             // Minimum R:R (spread-adjusted)
input double   InpADXThreshold   = 22.0;            // ADX minimum for trending confirmation
input int      InpADXPeriod      = 14;              // ADX period

//=============================================================================
// SCORING WEIGHTS (Improvement #1 — fully configurable)
//=============================================================================
input group "=== Scoring Weights ==="
// Layer 2
input int      InpWeight_LiqSweep      = 2;         // Liquidity sweep at OB
input int      InpWeight_FVGOverlap    = 2;         // FVG overlapping OB
input int      InpWeight_Inducement    = 1;         // Inducement taken
input int      InpWeight_MicroMSS      = 2;         // Micro MSS confirmed
// Layer 3
input int      InpWeight_RSIDivergence = 1;         // RSI divergence at OB
input int      InpWeight_EMAConfluence = 1;         // EMA confluence at OB
input int      InpWeight_VolumeSurge   = 1;         // Volume surge
input int      InpWeight_LRC           = 1;         // Linear regression channel
input int      InpWeight_ATRCompress   = 1;         // ATR compression
// Layer 4
input int      InpWeight_VWAP          = 1;         // VWAP retest
input int      InpWeight_PDHPDL        = 1;         // PDH/PDL alignment
input int      InpWeight_Session       = 1;         // Session killzone
input int      InpWeight_Fibonacci     = 1;         // Fibonacci golden pocket
input int      InpWeight_WinRate       = 2;         // Historical win-rate (2+ wins)
// Contradictions
input int      InpContradictionPenalty = -1;         // Per contradiction signal

//=============================================================================
// ENTRY / EXIT THRESHOLDS
//=============================================================================
input group "=== Thresholds ==="
input int      InpMinScoreToTrade = 8;              // Minimum score to enter (CONSIDER+)
input int      InpScorePriority   = 14;             // Score for PRIORITY setups

//=============================================================================
// RISK MANAGEMENT
//=============================================================================
input group "=== Risk Management ==="
input double   InpRiskPercent       = 2.0;          // Risk % per trade (of equity)
input double   InpDailyLossLimit    = 5.0;          // Daily loss limit %
input double   InpWeeklyLossLimit   = 10.0;         // Weekly loss limit %
input int      InpMaxPositions      = 3;            // Max simultaneous positions
input int      InpMaxSameCurrency   = 2;            // Max positions sharing same currency
input double   InpReducedSizeFactor = 0.5;          // Size multiplier after consec losses
input double   InpBoostedSizeFactor = 1.5;          // Size multiplier for PRIORITY streak
input int      InpConsecLossThreshold = 3;          // Consecutive losses to trigger reduced
input int      InpConsecWinRestore    = 3;          // Consecutive wins at reduced to restore
input int      InpConsecWinBoost      = 5;          // Consecutive wins at full for boost

//=============================================================================
// TRADE MANAGEMENT
//=============================================================================
input group "=== Trade Management ==="
input double   InpPartialClosePct     = 50.0;       // % to close at TP1
input double   InpBreakevenTriggerRR  = 1.0;        // R:R at which SL moves to BE
input double   InpTrailingATRMult     = 1.5;        // Trailing stop ATR multiplier
input int      InpOrderExpiryCandles  = 3;          // Pending order expiry (candle closes)
input double   InpBEBufferPips        = 1.0;        // Pips beyond entry for BE stop

//=============================================================================
// TECHNICAL INDICATORS
//=============================================================================
input group "=== Technical Indicators ==="
input int      InpRSIPeriod         = 14;           // RSI period
input int      InpEMA_Fast          = 21;           // EMA fast period
input int      InpEMA_Mid           = 50;           // EMA mid period
input int      InpEMA_Slow          = 200;          // EMA slow period
input double   InpVolSurgeMultiplier = 1.5;         // Volume surge threshold (x avg)
input int      InpVolAvgPeriod       = 20;          // Volume average period
input int      InpLRCPeriod          = 50;          // Linear regression channel period
input int      InpATRPeriod          = 14;          // ATR period
input double   InpATRCompressRatio   = 0.70;        // ATR compression threshold
input double   InpEMAProximityPct    = 0.5;         // EMA proximity % to OB zone

//=============================================================================
// SESSIONS (broker server time)
//=============================================================================
input group "=== Sessions ==="
input int      InpLondonStartHour = 8;              // London open hour (server time)
input int      InpLondonEndHour   = 17;             // London close hour
input int      InpNYStartHour     = 13;             // NY open hour (server time)
input int      InpNYEndHour       = 22;             // NY close hour
input int      InpAsianStartHour  = 0;              // Asian open hour
input int      InpAsianEndHour    = 8;              // Asian close hour

//=============================================================================
// ADAPTIVE LEARNING
//=============================================================================
input group "=== Adaptive Learning ==="
input bool     InpEnableAdaptive       = true;       // Enable adaptive weight learning
input int      InpAdaptMinTrades       = 30;          // Minimum trades before adapting
input double   InpAdaptStrength        = 0.3;         // Adaptation strength (0.0=none, 1.0=full)
input double   InpAdaptMinWeight       = 0.0;         // Minimum signal weight (floor)
input double   InpAdaptMaxWeightMult   = 2.5;         // Max weight multiplier over base
input int      InpAdaptFrequencyMins   = 60;          // Re-optimize every N minutes

//=============================================================================
// NEWS FILTER
//=============================================================================
input group "=== News Filter ==="
input bool     InpEnableNewsFilter     = true;       // Enable news filter
input int      InpNewsBufferMinutes    = 60;         // Minutes before news to avoid (1 hr)
input bool     InpFilterHighImpactOnly = true;       // Only filter high-impact events

#endif
