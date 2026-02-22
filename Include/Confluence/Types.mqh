//+------------------------------------------------------------------+
//|                                                      Types.mqh    |
//|                          Confluence Trading System                 |
//|                          All structs and type definitions          |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_TYPES_MQH
#define CONFLUENCE_TYPES_MQH

#include "Constants.mqh"

//+------------------------------------------------------------------+
//| Swing point on a specific timeframe                               |
//+------------------------------------------------------------------+
struct SwingPoint
{
   double            price;
   datetime          time;
   int               barIndex;
   bool              isHigh;       // true=swing high, false=swing low

   void Reset()
   {
      price    = 0;
      time     = 0;
      barIndex = -1;
      isHigh   = false;
   }
};

//+------------------------------------------------------------------+
//| Break of Structure event                                          |
//+------------------------------------------------------------------+
struct BOSEvent
{
   ENUM_BOS_TYPE     type;
   double            brokenLevel;  // The swing level that was broken
   double            breakPrice;   // Price that broke the level
   datetime          time;
   int               barIndex;

   void Reset()
   {
      type        = BOS_NONE;
      brokenLevel = 0;
      breakPrice  = 0;
      time        = 0;
      barIndex    = -1;
   }
};

//+------------------------------------------------------------------+
//| Change of Character event                                         |
//+------------------------------------------------------------------+
struct CHoCHEvent
{
   ENUM_CHOCH_TYPE   type;
   double            brokenLevel;
   datetime          time;
   int               barIndex;

   void Reset()
   {
      type        = CHOCH_NONE;
      brokenLevel = 0;
      time        = 0;
      barIndex    = -1;
   }
};

//+------------------------------------------------------------------+
//| Order Block zone                                                  |
//+------------------------------------------------------------------+
struct OrderBlock
{
   ENUM_OB_TYPE      type;
   double            highPrice;       // Top of OB zone
   double            lowPrice;        // Bottom of OB zone
   double            midPrice;        // (high+low)/2 for zone classification
   datetime          formationTime;
   int               barIndex;
   bool              isMitigated;     // Price traded through and closed beyond
   ENUM_ZONE_TYPE    zoneType;        // Premium or Discount

   void Reset()
   {
      type          = OB_NONE;
      highPrice     = 0;
      lowPrice      = 0;
      midPrice      = 0;
      formationTime = 0;
      barIndex      = -1;
      isMitigated   = false;
      zoneType      = ZONE_EQUILIBRIUM;
   }
};

//+------------------------------------------------------------------+
//| Fair Value Gap                                                    |
//+------------------------------------------------------------------+
struct FairValueGap
{
   double            highPrice;    // Top of gap
   double            lowPrice;     // Bottom of gap
   datetime          time;
   int               barIndex;
   bool              isBullish;    // true=bullish FVG (gap up)
   bool              isFilled;     // Price has returned to fill the gap

   void Reset()
   {
      highPrice = 0;
      lowPrice  = 0;
      time      = 0;
      barIndex  = -1;
      isBullish = false;
      isFilled  = false;
   }
};

//+------------------------------------------------------------------+
//| Liquidity Sweep event                                             |
//+------------------------------------------------------------------+
struct LiquiditySweep
{
   double            sweptLevel;      // The key level that was swept
   double            wickExtreme;     // How far the wick went beyond
   datetime          time;
   int               barIndex;
   bool              isBuySideSweep;  // true=swept above (buy stops), false=swept below (sell stops)

   void Reset()
   {
      sweptLevel     = 0;
      wickExtreme    = 0;
      time           = 0;
      barIndex       = -1;
      isBuySideSweep = false;
   }
};

//+------------------------------------------------------------------+
//| Full score breakdown for one symbol analysis                      |
//+------------------------------------------------------------------+
struct ScoreCard
{
   string            symbol;
   ENUM_TRADE_DIRECTION direction;
   datetime          analysisTime;

   //--- Layer 1: Mandatory Gate (all must be true)
   bool              htfTrendConfirmed;
   ENUM_TREND_DIRECTION htfTrend;
   ENUM_TIMEFRAMES   htfTimeframeUsed;    // Which TF resolved the trend
   bool              bosCountMet;
   int               bosCount;
   bool              obFound;
   OrderBlock        activeOB;
   bool              obInCorrectZone;
   bool              rrMet;
   double            riskRewardRatio;
   double            rrSpreadAdjusted;
   bool              adxAboveThreshold;
   double            adxValue;
   bool              gatePass;            // All 5 mandatory checks passed

   //--- Layer 2: Extended SMC
   bool              liquiditySweepAtOB;  // +weight
   bool              fvgOverlapOB;        // +weight
   bool              inducementTaken;     // +weight
   bool              microMSSConfirmed;   // +weight

   //--- Layer 3: Technical
   bool              rsiDivergence;       // +weight
   bool              emaConfluence;       // +weight
   bool              volumeSurge;         // +weight
   bool              lrcAtBound;          // +weight (linear regression channel)
   bool              atrCompression;      // +weight

   //--- Layer 4: Outsourced
   bool              vwapRetest;          // +weight
   bool              pdhPdlAlignment;     // +weight
   bool              sessionKillzone;     // +weight
   bool              fibGoldenPocket;     // +weight
   bool              winRateQualified;    // +weight (2+ historical wins)
   int               historicalWins;

   //--- Contradictions
   int               contradictionCount;
   string            contradictionReasons;

   //--- Final score
   int               totalScore;
   ENUM_QUALITY_LEVEL qualityLevel;

   //--- Trade invalidators (any true = instant reject)
   bool              wrongHTFDirection;
   bool              insufficientBOS;
   bool              rrBelowMinimum;
   bool              wrongZone;
   bool              newsWithin4Hours;
   bool              hasInvalidator;

   //--- Trade parameters (populated only if score >= threshold)
   double            entryPrice;
   double            stopLoss;
   double            takeProfit1;      // 50% exit — previous swing
   double            takeProfit2;      // Trailing target
   double            lotSize;
   double            spreadAtAnalysis;

   void Reset()
   {
      symbol              = "";
      direction           = TRADE_NONE;
      analysisTime        = 0;
      htfTrendConfirmed   = false;
      htfTrend            = TREND_NEUTRAL;
      htfTimeframeUsed    = PERIOD_D1;
      bosCountMet         = false;
      bosCount            = 0;
      obFound             = false;
      activeOB.Reset();
      obInCorrectZone     = false;
      rrMet               = false;
      riskRewardRatio     = 0;
      rrSpreadAdjusted    = 0;
      adxAboveThreshold   = false;
      adxValue            = 0;
      gatePass            = false;

      liquiditySweepAtOB  = false;
      fvgOverlapOB        = false;
      inducementTaken     = false;
      microMSSConfirmed   = false;

      rsiDivergence       = false;
      emaConfluence       = false;
      volumeSurge         = false;
      lrcAtBound          = false;
      atrCompression      = false;

      vwapRetest          = false;
      pdhPdlAlignment     = false;
      sessionKillzone     = false;
      fibGoldenPocket     = false;
      winRateQualified    = false;
      historicalWins      = 0;

      contradictionCount  = 0;
      contradictionReasons= "";

      totalScore          = 0;
      qualityLevel        = QUALITY_REJECT;

      wrongHTFDirection   = false;
      insufficientBOS     = false;
      rrBelowMinimum      = false;
      wrongZone           = false;
      newsWithin4Hours    = false;
      hasInvalidator      = false;

      entryPrice          = 0;
      stopLoss            = 0;
      takeProfit1         = 0;
      takeProfit2         = 0;
      lotSize             = 0;
      spreadAtAnalysis    = 0;
   }
};

//+------------------------------------------------------------------+
//| Active managed position (open trade being monitored)              |
//+------------------------------------------------------------------+
struct ManagedPosition
{
   ulong             ticket;
   string            symbol;
   ENUM_TRADE_DIRECTION direction;
   double            entryPrice;
   double            originalSL;
   double            currentSL;
   double            takeProfit1;     // 50% close target
   double            takeProfit2;     // Trailing target (initially 0)
   double            originalVolume;
   double            currentVolume;
   bool              tp1Hit;          // First target reached, partial close done
   bool              slMovedToBE;     // SL moved to breakeven after 1:1
   int               scoreAtEntry;
   ENUM_QUALITY_LEVEL qualityAtEntry;
   datetime          entryTime;
   datetime          lastCheckTime;   // Last CHoCH check time
   string            exitReason;      // Set before close: "CHoCH","SL","TP","TRAILING"

   void Reset()
   {
      ticket         = 0;
      symbol         = "";
      direction      = TRADE_NONE;
      entryPrice     = 0;
      originalSL     = 0;
      currentSL      = 0;
      takeProfit1    = 0;
      takeProfit2    = 0;
      originalVolume = 0;
      currentVolume  = 0;
      tp1Hit         = false;
      slMovedToBE    = false;
      scoreAtEntry   = 0;
      qualityAtEntry = QUALITY_REJECT;
      entryTime      = 0;
      lastCheckTime  = 0;
      exitReason     = "";
   }
};

//+------------------------------------------------------------------+
//| Watched zone tracking (market execution when price enters zone)   |
//+------------------------------------------------------------------+
struct PendingSetup
{
   string            symbol;
   ENUM_TRADE_DIRECTION direction;
   double            entryPrice;       // OB edge price (limit level)
   double            obHighPrice;      // Top of OB zone
   double            obLowPrice;       // Bottom of OB zone
   double            stopLoss;
   double            takeProfit;
   double            lotSize;
   int               scoreAtPlacement;
   ENUM_QUALITY_LEVEL qualityAtPlacement;
   datetime          placedTime;
   int               candlesSincePlaced;
   int               maxCandles;
   bool              isActive;

   void Reset()
   {
      symbol             = "";
      direction          = TRADE_NONE;
      entryPrice         = 0;
      obHighPrice        = 0;
      obLowPrice         = 0;
      stopLoss           = 0;
      takeProfit         = 0;
      lotSize            = 0;
      scoreAtPlacement   = 0;
      qualityAtPlacement = QUALITY_REJECT;
      placedTime         = 0;
      candlesSincePlaced = 0;
      maxCandles         = 3;
      isActive           = false;
   }
};

//+------------------------------------------------------------------+
//| Win-rate tracker record (persisted to CSV)                        |
//+------------------------------------------------------------------+
struct WinRateRecord
{
   string            symbol;
   int               totalTrades;
   int               wins;
   int               losses;
   double            winRate;
   double            totalProfitPips;
   double            totalLossPips;
   double            profitFactor;
   datetime          lastUpdated;

   void Reset()
   {
      symbol          = "";
      totalTrades     = 0;
      wins            = 0;
      losses          = 0;
      winRate         = 0;
      totalProfitPips = 0;
      totalLossPips   = 0;
      profitFactor    = 0;
      lastUpdated     = 0;
   }
};

//+------------------------------------------------------------------+
//| Streak tracking state (persisted to binary file)                  |
//+------------------------------------------------------------------+
struct StreakState
{
   int               consecutiveWins;
   int               consecutiveLosses;
   ENUM_SIZE_MODE    currentSizeMode;
   int               winsAtReduced;        // Wins since entering reduced mode
   int               winsAtFullOnPriority; // Consecutive wins at full on PRIORITY setups
   double            dailyStartEquity;     // Equity at start of trading day
   double            weeklyStartEquity;    // Equity at start of trading week
   datetime          dailyResetTime;
   datetime          weeklyResetTime;

   void Reset()
   {
      consecutiveWins      = 0;
      consecutiveLosses    = 0;
      currentSizeMode      = SIZE_NORMAL;
      winsAtReduced        = 0;
      winsAtFullOnPriority = 0;
      dailyStartEquity     = 0;
      weeklyStartEquity    = 0;
      dailyResetTime       = 0;
      weeklyResetTime      = 0;
   }
};

//+------------------------------------------------------------------+
//| Indicator handle storage per symbol                               |
//+------------------------------------------------------------------+
struct SymbolHandles
{
   string            symbol;
   int               adxHandle;
   int               rsiHandle;
   int               emaFastHandle;     // 21 EMA
   int               emaMidHandle;      // 50 EMA
   int               emaSlowHandle;     // 200 EMA
   int               atrHandle;
   bool              initialized;

   void Reset()
   {
      symbol         = "";
      adxHandle      = INVALID_HANDLE;
      rsiHandle      = INVALID_HANDLE;
      emaFastHandle  = INVALID_HANDLE;
      emaMidHandle   = INVALID_HANDLE;
      emaSlowHandle  = INVALID_HANDLE;
      atrHandle      = INVALID_HANDLE;
      initialized    = false;
   }
};

//+------------------------------------------------------------------+
//| Trade Journal Entry (for adaptive learning)                       |
//| Captures full signal state at entry + trade outcome.              |
//+------------------------------------------------------------------+
struct TradeJournalEntry
{
   string            symbol;
   ulong             ticket;
   ENUM_TRADE_DIRECTION direction;
   datetime          entryTime;
   datetime          exitTime;
   int               scoreAtEntry;
   ENUM_QUALITY_LEVEL qualityAtEntry;

   // Layer 2/3/4 signal states at entry (14 signals)
   // 0=liqSweep, 1=fvg, 2=inducement, 3=microMSS,
   // 4=rsiDiv, 5=ema, 6=volume, 7=lrc, 8=atrCompress,
   // 9=vwap, 10=pdhPdl, 11=session, 12=fib, 13=winRate
   bool              signals[ADAPTIVE_SIGNAL_COUNT];

   int               contradictionCount;
   int               bosCount;
   double            rrSpreadAdjusted;
   double            adxValue;
   double            entryPrice;
   double            exitPrice;
   double            stopLoss;
   double            takeProfit;
   double            profitPips;
   double            profitMoney;
   bool              isWin;
   string            exitReason;
   int               durationBars;

   void Reset()
   {
      symbol            = "";
      ticket            = 0;
      direction         = TRADE_NONE;
      entryTime         = 0;
      exitTime          = 0;
      scoreAtEntry      = 0;
      qualityAtEntry    = QUALITY_REJECT;
      for(int i = 0; i < ADAPTIVE_SIGNAL_COUNT; i++) signals[i] = false;
      contradictionCount= 0;
      bosCount          = 0;
      rrSpreadAdjusted  = 0;
      adxValue          = 0;
      entryPrice        = 0;
      exitPrice         = 0;
      stopLoss          = 0;
      takeProfit        = 0;
      profitPips        = 0;
      profitMoney       = 0;
      isWin             = false;
      exitReason        = "";
      durationBars      = 0;
   }
};

//+------------------------------------------------------------------+
//| Adaptive Weights (learned from trade journal)                     |
//| Layer 1 gate + invalidators are NEVER adapted.                    |
//+------------------------------------------------------------------+
struct AdaptiveWeights
{
   double            weights[ADAPTIVE_SIGNAL_COUNT];
   double            contradictionPenalty;
   int               totalTradesAnalyzed;
   bool              isActive;
   datetime          lastOptimized;

   void Reset()
   {
      for(int i = 0; i < ADAPTIVE_SIGNAL_COUNT; i++) weights[i] = 0;
      contradictionPenalty = -1.0;
      totalTradesAnalyzed = 0;
      isActive            = false;
      lastOptimized       = 0;
   }
};

#endif
