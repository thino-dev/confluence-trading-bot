//+------------------------------------------------------------------+
//|                                   ConfluenceTradingSystem.mq5     |
//|                          Confluence Trading System v1.0           |
//|                          4-Layer SMC Confluence EA                |
//|                          12 Forex Pairs | Full Auto-Trade        |
//+------------------------------------------------------------------+
#property copyright "Confluence Trading System"
#property link      ""
#property version   "1.00"
#property strict
#property description "Automated 4-layer Smart Money Concepts confluence trading system"
#property description "Scans 12 forex pairs, scores setups, auto-trades above threshold"

//=== INCLUDES ===
#include <Confluence\Constants.mqh>
#include <Confluence\Types.mqh>
#include <Confluence\Inputs.mqh>
#include <Confluence\Utilities.mqh>
#include <Confluence\MarketData.mqh>
#include <Confluence\SwingDetector.mqh>
#include <Confluence\StructureAnalyzer.mqh>
#include <Confluence\OrderBlockDetector.mqh>
#include <Confluence\ZoneAnalysis.mqh>
#include <Confluence\LiquiditySweep.mqh>
#include <Confluence\FairValueGap.mqh>
#include <Confluence\InducementDetector.mqh>
#include <Confluence\MicroStructureShift.mqh>
#include <Confluence\TechnicalIndicators.mqh>
#include <Confluence\LinearRegressionChannel.mqh>
#include <Confluence\ATRAnalyzer.mqh>
#include <Confluence\VWAPCalculator.mqh>
#include <Confluence\PreviousDayLevels.mqh>
#include <Confluence\SessionManager.mqh>
#include <Confluence\NewsFilter.mqh>
#include <Confluence\ScoringEngine.mqh>
#include <Confluence\TradeInvalidator.mqh>
#include <Confluence\RiskManager.mqh>
#include <Confluence\CorrelationGuard.mqh>
#include <Confluence\StreakManager.mqh>
#include <Confluence\TradeExecutor.mqh>
#include <Confluence\TradeManager.mqh>
#include <Confluence\OrderExpirationManager.mqh>
#include <Confluence\WinRateTracker.mqh>
#include <Confluence\AlertManager.mqh>
#include <Confluence\Dashboard.mqh>
#include <Confluence\TradeJournal.mqh>
#include <Confluence\AdaptiveOptimizer.mqh>

//=== GLOBAL OBJECTS ===
CLogger                  g_log;
CMarketData              g_marketData;
CSwingDetector           g_swingDetector;
CStructureAnalyzer       g_structureAnalyzer;
COrderBlockDetector      g_obDetector;
CZoneAnalysis            g_zoneAnalysis;
CLiquiditySweep          g_liqSweep;
CFairValueGap            g_fvg;
CInducementDetector      g_inducement;
CMicroStructureShift     g_microMSS;
CTechnicalIndicators     g_tech;
CLinearRegressionChannel g_lrc;
CATRAnalyzer             g_atr;
CVWAPCalculator          g_vwap;
CPreviousDayLevels       g_pdl;
CSessionManager          g_session;
CNewsFilter              g_newsFilter;
CScoringEngine           g_scorer;
CTradeInvalidator        g_invalidator;
CStreakManager           g_streak;
CCorrelationGuard        g_corrGuard;
CRiskManager             g_riskMgr;
CTradeExecutor           g_executor;
CTradeManager            g_tradeMgr;
COrderExpirationManager  g_expiryMgr;
CWinRateTracker          g_winRate;
CAlertManager            g_alerts;
CDashboard               g_dashboard;
CTradeJournal            g_journal;
CAdaptiveOptimizer       g_optimizer;

//=== GLOBAL STATE ===
string                   g_symbols[];
int                      g_symbolCount = 0;
ManagedPosition          g_positions[MAX_POSITIONS];
int                      g_positionCount = 0;
PendingSetup             g_pendingSetups[MAX_PENDING_SETUPS];
int                      g_pendingCount = 0;
datetime                 g_lastSaveTime = 0;
datetime                 g_lastOptimizeTime = 0;
bool                     g_firstRun = true;       // Force full scan on first timer tick
ScoreCard                g_lastScores[MAX_SYMBOLS]; // Cache last score per symbol

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_log.SetPrefix("CTS");

   // 0. Risk settings confirmation — prompt user before starting
   string riskMsg = StringFormat(
      "=== CONFLUENCE TRADING SYSTEM ===\n\n"
      "Please confirm your risk settings:\n\n"
      "  Risk per trade:      %.1f%% of equity\n"
      "  Max daily loss:      %.1f%%\n"
      "  Max weekly loss:     %.1f%%\n"
      "  Max positions:       %d\n\n"
      "Account equity: $%.2f\n"
      "Risk per trade: $%.2f\n\n"
      "Click YES to start trading with these settings.\n"
      "Click NO to stop — then right-click the EA → Properties → Inputs to adjust.",
      InpRiskPercent,
      InpDailyLossLimit,
      InpWeeklyLossLimit,
      InpMaxPositions,
      AccountInfoDouble(ACCOUNT_EQUITY),
      AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0
   );

   int response = MessageBox(riskMsg, "Risk Settings Confirmation", MB_YESNO | MB_ICONQUESTION);
   if(response != IDYES)
   {
      Print("[CTS] User declined risk settings. EA stopped. Adjust inputs via Properties → Inputs tab.");
      return INIT_FAILED;
   }

   g_log.Info("=== Confluence Trading System v1.0 Initializing ===");

   // 1. Parse symbol list
   g_symbolCount = ParseSymbolList(InpSymbols, InpSymbolSuffix, g_symbols);
   if(g_symbolCount == 0)
   {
      g_log.Error("No valid symbols configured. Check InpSymbols input.");
      return INIT_FAILED;
   }

   g_log.Info(StringFormat("Monitoring %d symbols", g_symbolCount));

   // 2. Validate symbols in Market Watch
   for(int i = g_symbolCount - 1; i >= 0; i--)
   {
      if(!SymbolSelect(g_symbols[i], true))
      {
         g_log.Warning(StringFormat("Symbol %s not available — removed", g_symbols[i]));
         // Remove from array
         for(int j = i; j < g_symbolCount - 1; j++)
            g_symbols[j] = g_symbols[j + 1];
         g_symbolCount--;
      }
   }

   if(g_symbolCount == 0)
   {
      g_log.Error("No valid symbols after broker validation.");
      return INIT_FAILED;
   }

   // 3. Initialize market data (indicator handles for all symbols)
   if(!g_marketData.Init(g_symbols, g_symbolCount))
   {
      g_log.Error("Failed to initialize market data.");
      return INIT_FAILED;
   }

   // 4. Initialize all modules
   g_swingDetector.Init(&g_marketData);
   g_structureAnalyzer.Init(&g_marketData, &g_swingDetector);
   g_obDetector.Init(&g_marketData);
   g_liqSweep.Init(&g_marketData);
   g_fvg.Init(&g_marketData);
   g_inducement.Init(&g_marketData);
   g_microMSS.Init(&g_marketData, &g_swingDetector);
   g_tech.Init(&g_marketData, &g_swingDetector);
   g_lrc.Init(&g_marketData);
   g_atr.Init(&g_marketData);
   g_vwap.Init(&g_marketData);
   g_pdl.Init(&g_marketData);
   g_invalidator.Init(&g_newsFilter);

   g_scorer.Init(&g_marketData, &g_swingDetector, &g_structureAnalyzer,
                  &g_obDetector, &g_zoneAnalysis,
                  &g_liqSweep, &g_fvg, &g_inducement, &g_microMSS,
                  &g_tech, &g_lrc, &g_atr,
                  &g_vwap, &g_pdl, &g_session, &g_winRate);

   g_riskMgr.Init(&g_streak, &g_corrGuard);
   g_executor.Init(&g_riskMgr, InpMagicNumber);
   g_journal.Init("confluence_journal.csv");
   g_tradeMgr.Init(&g_marketData, &g_structureAnalyzer, &g_atr,
                    &g_streak, &g_winRate, &g_journal, InpMagicNumber);
   g_expiryMgr.Init(&g_scorer, &g_invalidator);
   g_optimizer.Init(&g_journal, "confluence_adaptive_weights.csv");

   // 5. Load persistent data
   g_winRate.LoadFromFile("confluence_winrate.csv");
   g_streak.LoadState("confluence_state.bin");
   g_streak.UpdateEquityTracking();
   g_journal.LoadFromFile("confluence_journal.csv");

   // 5b. Load adaptive weights and apply to scorer if available
   if(InpEnableAdaptive)
   {
      if(g_optimizer.LoadWeights("confluence_adaptive_weights.csv"))
      {
         AdaptiveWeights aw;
         g_optimizer.GetWeights(aw);
         g_scorer.SetAdaptiveWeights(aw);
         g_log.Info("Adaptive weights loaded and applied to scorer.");
      }
   }

   // 6. Recover open positions
   g_tradeMgr.RecoverOpenPositions(InpMagicNumber, g_positions, g_positionCount);
   g_log.Info(StringFormat("Recovered %d open positions", g_positionCount));

   // 7. Initialize score cache
   for(int i = 0; i < MAX_SYMBOLS; i++)
      g_lastScores[i].Reset();

   // 8. Set timer
   if(!EventSetTimer(InpTimerSeconds))
   {
      g_log.Error("Failed to set timer");
      return INIT_FAILED;
   }

   // 9. Create dashboard
   g_dashboard.Create();

   // 10. Populate dashboard with symbol names immediately so user sees them
   for(int i = 0; i < g_symbolCount; i++)
   {
      ScoreCard initCard;
      initCard.Reset();
      initCard.symbol = g_symbols[i];
      g_dashboard.UpdateSymbolStatus(i, initCard);
      g_dashboard.UpdatePositionStatus(i, "--", C'100,100,100');
   }
   ChartRedraw();

   // Log each validated symbol for transparency
   for(int i = 0; i < g_symbolCount; i++)
      g_log.Info(StringFormat("  [%d] %s — active", i + 1, g_symbols[i]));

   g_log.Info(StringFormat("=== Initialization complete. %d symbols, trading %s ===",
              g_symbolCount, InpEnableTrading ? "ENABLED" : "DISABLED"));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Save persistent data
   g_winRate.SaveToFile("confluence_winrate.csv");
   g_streak.SaveState("confluence_state.bin");
   g_journal.SaveToFile("confluence_journal.csv");
   if(InpEnableAdaptive)
      g_optimizer.SaveWeights("confluence_adaptive_weights.csv");

   // Release indicator handles
   g_marketData.Deinit();

   // Destroy dashboard
   g_dashboard.Destroy();

   // Kill timer
   EventKillTimer();

   g_log.Info(StringFormat("Confluence Trading System deinitialized. Reason: %d", reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//| Manages positions + monitors OB zones for market execution.      |
//+------------------------------------------------------------------+
void OnTick()
{
   // Manage open positions (trailing, BE, CHoCH exit, partial close)
   if(g_positionCount > 0)
      g_tradeMgr.ManageAllPositions(g_positions, g_positionCount);

   // Monitor watched zones — execute market order when price enters zone
   if(g_pendingCount > 0 && InpEnableTrading)
      CheckZoneTriggers();
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//| Multi-pair scanning and new trade detection.                     |
//| Runs every N seconds, but only does heavy work on new bars.      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Pre-flight: update equity tracking
   g_streak.UpdateEquityTracking();

   // Pre-flight: check loss limits
   if(g_riskMgr.IsDailyLossLimitReached())
   {
      g_alerts.Send(ALERT_LOSS_LIMIT_WARN, "Daily loss limit reached. Trading paused.");
      UpdateDashboardFooter(false);
      return;
   }
   if(g_riskMgr.IsWeeklyLossLimitReached())
   {
      g_alerts.Send(ALERT_LOSS_LIMIT_WARN, "Weekly loss limit reached. Trading paused.");
      UpdateDashboardFooter(false);
      return;
   }

   // Scan all symbols
   bool forceFullScan = g_firstRun;  // First run after init: scan everything now
   if(g_firstRun) g_firstRun = false;

   for(int i = 0; i < g_symbolCount; i++)
   {
      string symbol = g_symbols[i];

      // New bar detection on execution TF (skip if no new bar)
      // Exception: first run after init always scans
      if(!forceFullScan && !g_marketData.IsNewBar(symbol))
         continue;

      // Ensure data is ready
      if(!g_marketData.IsDataReady(symbol, InpExecutionTF, InpSwingLookback))
      {
         if(forceFullScan)
            g_log.Warning(StringFormat("%s: data not ready yet (need %d bars on %s)",
                          symbol, InpSwingLookback, EnumToString(InpExecutionTF)));
         continue;
      }

      // Check pending order expiration for this symbol
      g_expiryMgr.CheckExpiration(symbol, g_pendingSetups, g_pendingCount);

      // Skip if we already have a pending order for this symbol
      if(HasPendingOrder(symbol))
         continue;

      // Skip if we already have an open position for this symbol
      if(HasOpenPosition(symbol))
         continue;

      // === Full 4-Layer Analysis ===
      ScoreCard card;
      card.Reset();

      bool gatePass = g_scorer.EvaluateLayer1(symbol, card);

      if(!gatePass)
      {
         g_lastScores[i] = card;
         g_dashboard.UpdateSymbolStatus(i, card);
         g_dashboard.UpdatePositionStatus(i, "--", C'100,100,100');
         continue;
      }

      // Check invalidators early
      if(g_invalidator.Check(card))
      {
         g_lastScores[i] = card;
         g_dashboard.UpdateSymbolStatus(i, card);
         g_dashboard.UpdatePositionStatus(i, "--", C'100,100,100');
         continue;
      }

      // Layer 2-4
      g_scorer.EvaluateLayer2(symbol, card);
      g_scorer.EvaluateLayer3(symbol, card);
      g_scorer.EvaluateLayer4(symbol, card);
      g_scorer.EvaluateContradictions(symbol, card);
      g_scorer.CalculateFinalScore(card);

      // Cache and update dashboard
      g_lastScores[i] = card;
      g_dashboard.UpdateSymbolStatus(i, card);

      // Log the analysis
      g_log.Info(StringFormat("%s | %s | BOS:%d | Score:%d | %s | RR:%.1f | Contra:%d",
                 symbol, DirectionToString(card.direction),
                 card.bosCount, card.totalScore,
                 QualityToString(card.qualityLevel),
                 card.rrSpreadAdjusted, card.contradictionCount));

      // === Decision: Store Zone or Skip ===
      if(card.totalScore >= InpMinScoreToTrade && InpEnableTrading)
      {
         // Pre-trade risk checks
         if(!g_riskMgr.PreTradeCheck(symbol, card, g_positions, g_positionCount))
            continue;

         // Store as watched zone (market execution when price arrives)
         PendingSetup setup;
         if(g_executor.PrepareZone(card, setup))
         {
            if(g_pendingCount < MAX_PENDING_SETUPS)
            {
               g_pendingSetups[g_pendingCount] = setup;
               g_pendingCount++;
            }

            // Send alert
            g_alerts.SendSetupAlert(card);
            g_dashboard.UpdatePositionStatus(i, "ZONE", clrYellow);
         }
      }
   }

   // Update dashboard footer
   UpdateDashboardFooter(true);

   // Periodic adaptive optimization
   if(InpEnableAdaptive &&
      TimeCurrent() - g_lastOptimizeTime > InpAdaptFrequencyMins * 60)
   {
      if(g_optimizer.Optimize())
      {
         AdaptiveWeights aw;
         g_optimizer.GetWeights(aw);
         g_scorer.SetAdaptiveWeights(aw);
         g_log.Info(StringFormat("Adaptive weights updated (%d trades analyzed)",
                    aw.totalTradesAnalyzed));
      }
      g_lastOptimizeTime = TimeCurrent();
   }

   // Periodic state save (every 5 minutes)
   if(TimeCurrent() - g_lastSaveTime > 300)
   {
      g_winRate.SaveToFile("confluence_winrate.csv");
      g_streak.SaveState("confluence_state.bin");
      g_journal.SaveToFile("confluence_journal.csv");
      if(InpEnableAdaptive)
         g_optimizer.SaveWeights("confluence_adaptive_weights.csv");
      g_lastSaveTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Strategy Tester custom metric                                     |
//+------------------------------------------------------------------+
double OnTester()
{
   double profitFactor   = TesterStatistics(STAT_PROFIT_FACTOR);
   double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);
   double sharpeRatio    = TesterStatistics(STAT_SHARPE_RATIO);
   double trades         = TesterStatistics(STAT_TRADES);

   // Penalize insufficient trade count
   if(trades < 30)
      return 0.0;

   // Weighted custom fitness
   return profitFactor * 0.4 + recoveryFactor * 0.3 + sharpeRatio * 0.3;
}

//+------------------------------------------------------------------+
//| Helper: Monitor zones and execute market orders when triggered    |
//+------------------------------------------------------------------+
void CheckZoneTriggers()
{
   for(int i = g_pendingCount - 1; i >= 0; i--)
   {
      if(!g_pendingSetups[i].isActive) continue;

      // Check if price has entered the OB zone
      if(!g_executor.IsPriceInZone(g_pendingSetups[i]))
         continue;

      // Price is in the zone — execute market order
      ManagedPosition pos;
      pos.Reset();

      if(g_executor.ExecuteMarketOrder(g_pendingSetups[i], pos))
      {
         // Fill managed position fields
         pos.originalSL     = g_pendingSetups[i].stopLoss;
         pos.currentSL      = g_pendingSetups[i].stopLoss;
         pos.takeProfit1    = g_pendingSetups[i].takeProfit;
         pos.scoreAtEntry   = g_pendingSetups[i].scoreAtPlacement;
         pos.qualityAtEntry = g_pendingSetups[i].qualityAtPlacement;
         pos.tp1Hit         = false;
         pos.slMovedToBE    = false;
         pos.lastCheckTime  = TimeCurrent();

         if(g_positionCount < MAX_POSITIONS)
         {
            g_positions[g_positionCount] = pos;
            g_positionCount++;
         }

         // Snapshot ScoreCard to journal for adaptive learning
         int symIdx = GetSymbolIndex(pos.symbol);
         if(symIdx >= 0)
            g_journal.LogTradeOpen(pos.ticket, g_lastScores[symIdx]);

         g_alerts.Send(ALERT_ORDER_TRIGGERED,
            StringFormat("%s %s EXECUTED @ %.5f [Score:%d]",
                         pos.symbol, DirectionToString(pos.direction),
                         pos.entryPrice, pos.scoreAtEntry));

         // Update dashboard
         if(symIdx >= 0)
            g_dashboard.UpdatePositionStatus(symIdx,
               DirectionToString(pos.direction),
               pos.direction == TRADE_LONG ? clrLime : clrRed);
      }

      // Remove zone regardless of success (don't retry failed orders)
      RemovePendingSetup(i);
   }
}

//+------------------------------------------------------------------+
//| Helper: Update dashboard footer                                   |
//+------------------------------------------------------------------+
void UpdateDashboardFooter(bool isActive)
{
   double pnl = 0;
   for(int i = 0; i < g_positionCount; i++)
   {
      if(PositionSelectByTicket(g_positions[i].ticket))
         pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }

   StreakState streakState;
   g_streak.GetState(streakState);

   g_dashboard.UpdateFooter(
      pnl,
      g_riskMgr.GetDailyDrawdownPct(),
      g_riskMgr.GetWeeklyDrawdownPct(),
      g_positionCount, InpMaxPositions,
      streakState.consecutiveWins,
      streakState.consecutiveLosses,
      streakState.currentSizeMode,
      isActive && InpEnableTrading);

   // Update position status for all symbols
   for(int i = 0; i < g_symbolCount; i++)
   {
      string sym = g_symbols[i];
      bool hasPos = false;
      bool hasPend = false;

      for(int j = 0; j < g_positionCount; j++)
      {
         if(g_positions[j].symbol == sym)
         {
            g_dashboard.UpdatePositionStatus(i,
               DirectionToString(g_positions[j].direction),
               g_positions[j].direction == TRADE_LONG ? clrLime : clrRed);
            hasPos = true;
            break;
         }
      }

      if(!hasPos)
      {
         for(int j = 0; j < g_pendingCount; j++)
         {
            if(g_pendingSetups[j].symbol == sym && g_pendingSetups[j].isActive)
            {
               g_dashboard.UpdatePositionStatus(i, "ZONE", clrYellow);
               hasPend = true;
               break;
            }
         }
      }

      if(!hasPos && !hasPend)
         g_dashboard.UpdatePositionStatus(i, "--", C'100,100,100');
   }
}

//+------------------------------------------------------------------+
//| Helper: Check if symbol has a pending order                       |
//+------------------------------------------------------------------+
bool HasPendingOrder(const string symbol)
{
   for(int i = 0; i < g_pendingCount; i++)
      if(g_pendingSetups[i].symbol == symbol && g_pendingSetups[i].isActive)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Helper: Check if symbol has an open position                      |
//+------------------------------------------------------------------+
bool HasOpenPosition(const string symbol)
{
   for(int i = 0; i < g_positionCount; i++)
      if(g_positions[i].symbol == symbol)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Helper: Get symbol index                                          |
//+------------------------------------------------------------------+
int GetSymbolIndex(const string symbol)
{
   for(int i = 0; i < g_symbolCount; i++)
      if(g_symbols[i] == symbol)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Helper: Remove pending setup by index                             |
//+------------------------------------------------------------------+
void RemovePendingSetup(int idx)
{
   for(int i = idx; i < g_pendingCount - 1; i++)
      g_pendingSetups[i] = g_pendingSetups[i + 1];
   g_pendingCount--;
}
//+------------------------------------------------------------------+
