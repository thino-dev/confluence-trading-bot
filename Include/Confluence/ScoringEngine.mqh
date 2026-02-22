//+------------------------------------------------------------------+
//|                                              ScoringEngine.mqh    |
//|                          Confluence Trading System                 |
//|                          4-layer confluence scoring system        |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_SCORINGENGINE_MQH
#define CONFLUENCE_SCORINGENGINE_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"
#include "SwingDetector.mqh"
#include "StructureAnalyzer.mqh"
#include "OrderBlockDetector.mqh"
#include "ZoneAnalysis.mqh"
#include "LiquiditySweep.mqh"
#include "FairValueGap.mqh"
#include "InducementDetector.mqh"
#include "MicroStructureShift.mqh"
#include "TechnicalIndicators.mqh"
#include "LinearRegressionChannel.mqh"
#include "ATRAnalyzer.mqh"
#include "VWAPCalculator.mqh"
#include "PreviousDayLevels.mqh"
#include "SessionManager.mqh"
#include "WinRateTracker.mqh"

//+------------------------------------------------------------------+
//| Scoring Engine                                                    |
//| Orchestrates all 4 layers and produces a final ScoreCard.        |
//+------------------------------------------------------------------+
class CScoringEngine
{
private:
   CMarketData*             m_data;
   CSwingDetector*          m_swing;
   CStructureAnalyzer*      m_structure;
   COrderBlockDetector*     m_obDetector;
   CZoneAnalysis*           m_zone;
   CLiquiditySweep*         m_liqSweep;
   CFairValueGap*           m_fvg;
   CInducementDetector*     m_inducement;
   CMicroStructureShift*    m_microMSS;
   CTechnicalIndicators*    m_tech;
   CLinearRegressionChannel* m_lrc;
   CATRAnalyzer*            m_atr;
   CVWAPCalculator*         m_vwap;
   CPreviousDayLevels*      m_pdl;
   CSessionManager*         m_session;
   CWinRateTracker*         m_winRate;
   CLogger                  m_log;

   // Adaptive learning
   AdaptiveWeights          m_adaptiveWeights;
   bool                     m_useAdaptive;

public:
   CScoringEngine() : m_useAdaptive(false) { m_log.SetPrefix("Scorer"); m_adaptiveWeights.Reset(); }

   //--- Set adaptive weights from the optimizer
   void SetAdaptiveWeights(const AdaptiveWeights &w)
   {
      m_adaptiveWeights = w;
      m_useAdaptive = w.isActive;
   }

   void Init(CMarketData *data, CSwingDetector *swing, CStructureAnalyzer *structure,
             COrderBlockDetector *obDet, CZoneAnalysis *zone,
             CLiquiditySweep *liq, CFairValueGap *fvg, CInducementDetector *idm,
             CMicroStructureShift *mss, CTechnicalIndicators *tech,
             CLinearRegressionChannel *lrc, CATRAnalyzer *atr,
             CVWAPCalculator *vwap, CPreviousDayLevels *pdl,
             CSessionManager *session, CWinRateTracker *winRate)
   {
      m_data      = data;
      m_swing     = swing;
      m_structure = structure;
      m_obDetector= obDet;
      m_zone      = zone;
      m_liqSweep  = liq;
      m_fvg       = fvg;
      m_inducement= idm;
      m_microMSS  = mss;
      m_tech      = tech;
      m_lrc       = lrc;
      m_atr       = atr;
      m_vwap      = vwap;
      m_pdl       = pdl;
      m_session   = session;
      m_winRate   = winRate;
   }

   //=================================================================
   // LAYER 1: Mandatory Gate
   // All 5 checks must pass or analysis stops immediately.
   //=================================================================
   bool EvaluateLayer1(const string symbol, ScoreCard &card)
   {
      card.gatePass = false;
      card.symbol = symbol;
      card.analysisTime = TimeCurrent();

      // 1. HTF Trend
      ENUM_TIMEFRAMES usedTF;
      card.htfTrend = m_structure.DetermineHTFTrend(symbol, usedTF);
      card.htfTimeframeUsed = usedTF;
      card.htfTrendConfirmed = (card.htfTrend != TREND_NEUTRAL);

      if(!card.htfTrendConfirmed)
         return false;

      // Set trade direction from trend
      card.direction = (card.htfTrend == TREND_BULLISH) ? TRADE_LONG : TRADE_SHORT;

      // 2. BOS Count
      BOSEvent bosEvents[];
      CHoCHEvent chochEvents[];
      int bosCount = 0, chochCount = 0, retracementBar = -1;

      card.bosCount = m_structure.CountConsecutiveBOS(
         symbol, card.htfTrend,
         bosEvents, bosCount, chochEvents, chochCount, retracementBar);

      card.bosCountMet = (card.bosCount >= InpMinBOSCount);
      if(!card.bosCountMet)
         return false;

      // 3. Order Block
      BOSEvent lastBOS;
      if(bosCount > 0)
         lastBOS = bosEvents[bosCount - 1];

      card.obFound = m_obDetector.FindOrderBlock(
         symbol, InpExecutionTF, card.htfTrend, retracementBar, lastBOS, card.activeOB);

      if(!card.obFound)
         return false;

      // 4. OB in correct zone (premium/discount)
      SwingPoint htfHighs[], htfLows[];
      int htfHighCount = 0, htfLowCount = 0;
      m_swing.DetectSwings(symbol, card.htfTimeframeUsed,
         InpSwingLookback, InpSwingLeftBars, InpSwingRightBars,
         htfHighs, htfHighCount, htfLows, htfLowCount);

      double rangeHigh = 0, rangeLow = 0;
      m_swing.GetSwingRange(htfHighs, htfHighCount, htfLows, htfLowCount,
                            rangeHigh, rangeLow);

      card.activeOB.zoneType = m_zone.ClassifyOBZone(card.activeOB, rangeHigh, rangeLow);
      card.obInCorrectZone = m_zone.IsOBInCorrectZone(card.activeOB, card.direction,
                                                       rangeHigh, rangeLow);
      if(!card.obInCorrectZone)
         return false;

      // Calculate entry/SL/TP
      SwingPoint targetSwing;
      if(card.direction == TRADE_LONG)
         m_swing.FindNearestSwingHigh(htfHighs, htfHighCount, card.activeOB.highPrice, targetSwing);
      else
         m_swing.FindNearestSwingLow(htfLows, htfLowCount, card.activeOB.lowPrice, targetSwing);

      if(targetSwing.price <= 0)
      {
         // Use range boundary as fallback
         targetSwing.price = (card.direction == TRADE_LONG) ? rangeHigh : rangeLow;
      }

      m_zone.CalculateTradeParams(card.activeOB, card.direction, targetSwing,
                                   card.entryPrice, card.stopLoss, card.takeProfit1);

      // 5. Risk:Reward (spread-adjusted)
      card.spreadAtAnalysis = GetSpreadAsPrice(symbol);
      card.rrSpreadAdjusted = m_zone.CalculateRR(
         symbol, card.entryPrice, card.stopLoss, card.takeProfit1, card.direction);
      card.riskRewardRatio = card.rrSpreadAdjusted;
      card.rrMet = (card.rrSpreadAdjusted >= InpMinRR);

      if(!card.rrMet)
         return false;

      // 5b. ADX regime filter (Improvement #2)
      SymbolHandles handles;
      if(m_data.GetHandles(symbol, handles))
      {
         card.adxAboveThreshold = m_atr.IsADXAboveThreshold(symbol, handles, card.adxValue);
      }
      else
      {
         card.adxAboveThreshold = false;
         card.adxValue = 0;
      }

      if(!card.adxAboveThreshold)
         return false;

      // All 5 mandatory checks passed
      card.gatePass = true;
      return true;
   }

   //=================================================================
   // LAYER 2: Extended SMC
   //=================================================================
   void EvaluateLayer2(const string symbol, ScoreCard &card)
   {
      if(!card.gatePass) return;

      // Get swing data on execution TF for Layer 2 checks
      SwingPoint execHighs[], execLows[];
      int execHighCount = 0, execLowCount = 0;
      m_swing.DetectSwings(symbol, InpExecutionTF,
         InpSwingLookback, InpSwingLeftBars, InpSwingRightBars,
         execHighs, execHighCount, execLows, execLowCount);

      // 2a. Liquidity Sweep at OB
      LiquiditySweep sweep;
      card.liquiditySweepAtOB = m_liqSweep.DetectSweepAtOB(
         symbol, InpExecutionTF, card.activeOB, card.direction,
         execHighs, execHighCount, execLows, execLowCount, sweep);

      // 2b. FVG overlapping OB
      FairValueGap fvgs[];
      int fvgCount = 0;
      m_fvg.DetectFVGs(symbol, InpExecutionTF, 50, fvgs, fvgCount);
      card.fvgOverlapOB = m_fvg.CheckFVGOverlapOB(fvgs, fvgCount, card.activeOB, card.direction);

      // 2c. Inducement taken
      card.inducementTaken = m_inducement.DetectInducement(
         symbol, InpExecutionTF, card.activeOB, card.direction,
         execHighs, execHighCount, execLows, execLowCount);

      // 2d. Micro MSS on lower TF
      card.microMSSConfirmed = m_microMSS.DetectMSSAtOB(symbol, card.activeOB, card.direction);
   }

   //=================================================================
   // LAYER 3: Technical Confluence
   //=================================================================
   void EvaluateLayer3(const string symbol, ScoreCard &card)
   {
      if(!card.gatePass) return;

      SymbolHandles handles;
      if(!m_data.GetHandles(symbol, handles)) return;

      // 3a. RSI Divergence
      card.rsiDivergence = m_tech.DetectRSIDivergence(symbol, card.direction, handles);

      // 3b. EMA Confluence
      card.emaConfluence = m_tech.CheckEMAConfluence(symbol, card.activeOB, handles);

      // 3c. Volume Surge
      card.volumeSurge = m_tech.CheckVolumeSurge(symbol, InpExecutionTF);

      // 3d. Linear Regression Channel
      card.lrcAtBound = m_lrc.CheckLRCConfluence(symbol, InpExecutionTF, card.direction);

      // 3e. ATR Compression
      card.atrCompression = m_atr.IsATRCompressed(symbol, handles);
   }

   //=================================================================
   // LAYER 4: Outsourced High Win-Rate Frameworks
   //=================================================================
   void EvaluateLayer4(const string symbol, ScoreCard &card)
   {
      if(!card.gatePass) return;

      // 4a. VWAP Retest
      card.vwapRetest = m_vwap.IsRetestingVWAP(symbol, card.activeOB);

      // 4b. PDH/PDL Alignment
      card.pdhPdlAlignment = m_pdl.CheckPDHPDLAlignment(symbol, card.activeOB, card.direction);

      // 4c. Session Killzone
      card.sessionKillzone = m_session.IsInKillzone();

      // 4d. Fibonacci Golden Pocket
      SwingPoint htfHighs[], htfLows[];
      int htfHighCount = 0, htfLowCount = 0;
      m_swing.DetectSwings(symbol, card.htfTimeframeUsed,
         InpSwingLookback, InpSwingLeftBars, InpSwingRightBars,
         htfHighs, htfHighCount, htfLows, htfLowCount);

      double rangeHigh = 0, rangeLow = 0;
      m_swing.GetSwingRange(htfHighs, htfHighCount, htfLows, htfLowCount,
                            rangeHigh, rangeLow);
      card.fibGoldenPocket = m_zone.IsInGoldenPocket(
         card.activeOB, card.direction, rangeHigh, rangeLow);

      // 4e. Pair Win-Rate (2+ wins)
      card.historicalWins = m_winRate.GetWinCount(symbol);
      card.winRateQualified = m_winRate.HasMinimumWins(symbol, 2);
   }

   //=================================================================
   // CONTRADICTION DETECTION
   //=================================================================
   void EvaluateContradictions(const string symbol, ScoreCard &card)
   {
      if(!card.gatePass) return;

      card.contradictionCount = 0;
      card.contradictionReasons = "";

      SymbolHandles handles;
      if(!m_data.GetHandles(symbol, handles)) return;

      // 1. Counter-direction RSI extreme
      double rsi = m_tech.GetRSI(symbol, handles);
      if(card.direction == TRADE_LONG && rsi > 70)
      {
         card.contradictionCount++;
         card.contradictionReasons += "RSI_OB;";
      }
      if(card.direction == TRADE_SHORT && rsi < 30)
      {
         card.contradictionCount++;
         card.contradictionReasons += "RSI_OS;";
      }

      // 2. Volume declining on recent impulses
      if(m_tech.IsVolumeDeclining(symbol, InpExecutionTF, 5))
      {
         card.contradictionCount++;
         card.contradictionReasons += "VOL_DECLINE;";
      }

      // 3. EMA slope opposing trade direction
      double emaFastCurr = m_tech.GetEMAFast(handles, 0);
      double emaFastPrev = m_tech.GetEMAFast(handles, 1);
      if(card.direction == TRADE_LONG && emaFastCurr < emaFastPrev)
      {
         card.contradictionCount++;
         card.contradictionReasons += "EMA_SLOPE;";
      }
      if(card.direction == TRADE_SHORT && emaFastCurr > emaFastPrev)
      {
         card.contradictionCount++;
         card.contradictionReasons += "EMA_SLOPE;";
      }

      // 4. NY Lunch session (weak trading window)
      if(m_session.IsNYLunch())
      {
         card.contradictionCount++;
         card.contradictionReasons += "NY_LUNCH;";
      }

      // 5. OB near but not inside golden pocket
      if(!card.fibGoldenPocket)
      {
         // Check if it's NEAR the golden pocket (within 5% of range)
         // If near but not inside = minor contradiction
         SwingPoint htfHighs[], htfLows[];
         int hc = 0, lc = 0;
         m_swing.DetectSwings(symbol, card.htfTimeframeUsed,
            InpSwingLookback, InpSwingLeftBars, InpSwingRightBars,
            htfHighs, hc, htfLows, lc);

         double rh = 0, rl = 0;
         if(m_swing.GetSwingRange(htfHighs, hc, htfLows, lc, rh, rl))
         {
            double range = rh - rl;
            double fib618 = rh - range * 0.618;
            double fib786 = rh - range * 0.786;
            double obMid = card.activeOB.midPrice;

            // Near = within 10% of golden pocket range on either side
            double gpRange = MathAbs(fib618 - fib786);
            double nearThreshold = gpRange * 0.5;

            if(MathAbs(obMid - fib618) <= nearThreshold || MathAbs(obMid - fib786) <= nearThreshold)
            {
               card.contradictionCount++;
               card.contradictionReasons += "NEAR_GP;";
            }
         }
      }
   }

   //=================================================================
   // FINAL SCORE CALCULATION
   //=================================================================
   void CalculateFinalScore(ScoreCard &card)
   {
      if(!card.gatePass)
      {
         card.totalScore = 0;
         card.qualityLevel = QUALITY_REJECT;
         return;
      }

      // Map all 14 Layer 2/3/4 signals to indexed array
      bool sigs[ADAPTIVE_SIGNAL_COUNT];
      sigs[0]  = card.liquiditySweepAtOB;
      sigs[1]  = card.fvgOverlapOB;
      sigs[2]  = card.inducementTaken;
      sigs[3]  = card.microMSSConfirmed;
      sigs[4]  = card.rsiDivergence;
      sigs[5]  = card.emaConfluence;
      sigs[6]  = card.volumeSurge;
      sigs[7]  = card.lrcAtBound;
      sigs[8]  = card.atrCompression;
      sigs[9]  = card.vwapRetest;
      sigs[10] = card.pdhPdlAlignment;
      sigs[11] = card.sessionKillzone;
      sigs[12] = card.fibGoldenPocket;
      sigs[13] = card.winRateQualified;

      double score = 0;

      if(m_useAdaptive && m_adaptiveWeights.isActive)
      {
         // Adaptive weights (learned from trade journal)
         for(int i = 0; i < ADAPTIVE_SIGNAL_COUNT; i++)
            if(sigs[i]) score += m_adaptiveWeights.weights[i];
         score += card.contradictionCount * m_adaptiveWeights.contradictionPenalty;
      }
      else
      {
         // Base weights from input parameters
         double baseW[ADAPTIVE_SIGNAL_COUNT];
         baseW[0]  = InpWeight_LiqSweep;
         baseW[1]  = InpWeight_FVGOverlap;
         baseW[2]  = InpWeight_Inducement;
         baseW[3]  = InpWeight_MicroMSS;
         baseW[4]  = InpWeight_RSIDivergence;
         baseW[5]  = InpWeight_EMAConfluence;
         baseW[6]  = InpWeight_VolumeSurge;
         baseW[7]  = InpWeight_LRC;
         baseW[8]  = InpWeight_ATRCompress;
         baseW[9]  = InpWeight_VWAP;
         baseW[10] = InpWeight_PDHPDL;
         baseW[11] = InpWeight_Session;
         baseW[12] = InpWeight_Fibonacci;
         baseW[13] = InpWeight_WinRate;

         for(int i = 0; i < ADAPTIVE_SIGNAL_COUNT; i++)
            if(sigs[i]) score += baseW[i];
         score += card.contradictionCount * InpContradictionPenalty;
      }

      // Floor at 0, round to integer
      int finalScore = (int)MathRound(MathMax(0.0, score));
      card.totalScore = finalScore;

      // Classify quality level
      if(finalScore <= SCORE_REJECT_MAX)       card.qualityLevel = QUALITY_REJECT;
      else if(finalScore <= SCORE_WATCH_MAX)   card.qualityLevel = QUALITY_WATCH;
      else if(finalScore < SCORE_ENTER_MIN)    card.qualityLevel = QUALITY_CONSIDER;
      else if(finalScore < SCORE_PRIORITY_MIN) card.qualityLevel = QUALITY_ENTER;
      else                                     card.qualityLevel = QUALITY_PRIORITY;
   }

   //=================================================================
   // FULL ANALYSIS (runs all layers in sequence)
   //=================================================================
   bool FullAnalysis(const string symbol, ScoreCard &card)
   {
      card.Reset();

      if(!EvaluateLayer1(symbol, card))
         return false;

      EvaluateLayer2(symbol, card);
      EvaluateLayer3(symbol, card);
      EvaluateLayer4(symbol, card);
      EvaluateContradictions(symbol, card);
      CalculateFinalScore(card);

      return card.gatePass;
   }
};

#endif
