//+------------------------------------------------------------------+
//|                                          AdaptiveOptimizer.mqh    |
//|                          Confluence Trading System                 |
//|                          Self-improving weight optimization       |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_ADAPTIVEOPTIMIZER_MQH
#define CONFLUENCE_ADAPTIVEOPTIMIZER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "TradeJournal.mqh"

//+------------------------------------------------------------------+
//| Adaptive Optimizer                                                |
//| Reads trade journal, measures each signal's contribution to       |
//| winning trades, and adjusts Layer 2/3/4 scoring weights.          |
//|                                                                    |
//| CORE PRINCIPLE: Layer 1 gate and invalidators are NEVER touched.  |
//| Only the optional signal weights (14 signals) are adapted.        |
//|                                                                    |
//| Algorithm:                                                         |
//| For each signal i:                                                 |
//|   winRateOn  = wins when signal ON  / total when signal ON         |
//|   winRateOff = wins when signal OFF / total when signal OFF        |
//|   lift = winRateOn - winRateOff                                   |
//|   adaptedWeight = baseWeight * (1.0 + lift * strength)            |
//|   clamped to [minWeight, baseWeight * maxMultiplier]              |
//|                                                                    |
//| Signals that reliably predict wins get boosted.                   |
//| Signals uncorrelated with wins get reduced.                       |
//| Changes are gradual (blended with previous weights).              |
//+------------------------------------------------------------------+
class CAdaptiveOptimizer
{
private:
   CTradeJournal*       m_journal;
   CLogger              m_log;
   AdaptiveWeights      m_weights;
   AdaptiveWeights      m_prevWeights;   // For blending
   string               m_weightsFile;

   double               m_adaptStrength;
   double               m_minWeight;
   double               m_maxWeightMult;
   int                  m_minTrades;
   double               m_blendFactor;   // 0.7 = 70% new + 30% old

public:
   CAdaptiveOptimizer() : m_journal(NULL), m_adaptStrength(0.3),
                            m_minWeight(0.0), m_maxWeightMult(2.5),
                            m_minTrades(30), m_blendFactor(0.7)
   {
      m_log.SetPrefix("Optimizer");
      m_weights.Reset();
      m_prevWeights.Reset();
   }

   void Init(CTradeJournal *journal, const string weightsFile)
   {
      m_journal       = journal;
      m_weightsFile   = weightsFile;
      m_adaptStrength = InpAdaptStrength;
      m_minWeight     = InpAdaptMinWeight;
      m_maxWeightMult = InpAdaptMaxWeightMult;
      m_minTrades     = InpAdaptMinTrades;

      // Initialize weights from base inputs
      InitBaseWeights(m_weights);
      m_prevWeights = m_weights;
   }

   //--- Run optimization pass. Returns true if weights were updated.
   bool Optimize()
   {
      if(m_journal == NULL) return false;

      TradeJournalEntry entries[];
      int count = 0;
      m_journal.GetAllEntries(entries, count);

      if(count < m_minTrades)
      {
         m_log.Info(StringFormat("Not enough trades for adaptation (%d/%d)",
                    count, m_minTrades));
         return false;
      }

      // Save previous weights for blending
      m_prevWeights = m_weights;

      // Calculate new weights based on signal lift
      AdaptiveWeights newWeights;
      InitBaseWeights(newWeights);

      for(int sig = 0; sig < ADAPTIVE_SIGNAL_COUNT; sig++)
      {
         double lift = CalcSignalLift(sig, entries, count);
         double baseW = GetBaseWeight(sig);

         // Apply lift to base weight
         double adapted = baseW * (1.0 + lift * m_adaptStrength);

         // Clamp to bounds
         double maxW = baseW * m_maxWeightMult;
         if(maxW < 1.0) maxW = 1.0; // Ensure reasonable upper bound
         adapted = MathMax(m_minWeight, MathMin(maxW, adapted));

         // Blend with previous weight for stability
         newWeights.weights[sig] = adapted * m_blendFactor
                                 + m_prevWeights.weights[sig] * (1.0 - m_blendFactor);
      }

      // Adapt contradiction penalty
      double contraLift = CalcContradictionLift(entries, count);
      double baseContra = (double)InpContradictionPenalty;
      double adaptedContra = baseContra * (1.0 + contraLift * m_adaptStrength);
      // Contradiction penalty should stay negative; clamp to [-3, 0]
      newWeights.contradictionPenalty = MathMax(-3.0, MathMin(0.0, adaptedContra));

      newWeights.totalTradesAnalyzed = count;
      newWeights.isActive = true;
      newWeights.lastOptimized = TimeCurrent();

      m_weights = newWeights;

      // Log the results
      LogWeightUpdate(entries, count);

      return true;
   }

   //--- Get current adaptive weights
   void GetWeights(AdaptiveWeights &w) const
   {
      w = m_weights;
   }

   bool HasActiveWeights() const { return m_weights.isActive; }

   //--- File persistence for adaptive weights

   bool LoadWeights(const string filename)
   {
      string fname = (filename != "") ? filename : m_weightsFile;
      if(fname == "") return false;

      int handle = FileOpen(fname, FILE_READ | FILE_TXT | FILE_ANSI);
      if(handle == INVALID_HANDLE) return false;

      // Skip header
      if(!FileIsEnding(handle))
         FileReadString(handle);

      if(!FileIsEnding(handle))
      {
         string line = FileReadString(handle);
         string fields[];
         int cnt = StringSplit(line, ',', fields);

         if(cnt >= ADAPTIVE_SIGNAL_COUNT + 4)
         {
            for(int i = 0; i < ADAPTIVE_SIGNAL_COUNT; i++)
               m_weights.weights[i] = StringToDouble(fields[i]);

            int off = ADAPTIVE_SIGNAL_COUNT;
            m_weights.contradictionPenalty = StringToDouble(fields[off]);
            m_weights.totalTradesAnalyzed  = (int)StringToInteger(fields[off + 1]);
            m_weights.isActive             = (StringToInteger(fields[off + 2]) != 0);
            m_weights.lastOptimized        = (datetime)StringToInteger(fields[off + 3]);

            m_prevWeights = m_weights;

            m_log.Info(StringFormat("Loaded adaptive weights (%d trades analyzed)",
                       m_weights.totalTradesAnalyzed));
         }
      }

      FileClose(handle);
      return m_weights.isActive;
   }

   bool SaveWeights(const string filename)
   {
      string fname = (filename != "") ? filename : m_weightsFile;
      if(fname == "") return false;

      int handle = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(handle == INVALID_HANDLE) return false;

      // Header
      string header = "";
      string sigNames[] = {"LiqSweep","FVG","Inducement","MicroMSS",
                            "RSIDiv","EMA","Volume","LRC","ATRComp",
                            "VWAP","PDHPDL","Session","Fib","WinRate"};

      for(int i = 0; i < ADAPTIVE_SIGNAL_COUNT; i++)
         header += sigNames[i] + ",";
      header += "ContraPenalty,TradesAnalyzed,IsActive,LastOptimized";
      FileWriteString(handle, header + "\n");

      // Values
      string line = "";
      for(int i = 0; i < ADAPTIVE_SIGNAL_COUNT; i++)
         line += DoubleToString(m_weights.weights[i], 3) + ",";

      line += StringFormat("%.3f,%d,%d,%d",
         m_weights.contradictionPenalty,
         m_weights.totalTradesAnalyzed,
         m_weights.isActive ? 1 : 0,
         (long)m_weights.lastOptimized);

      FileWriteString(handle, line + "\n");
      FileClose(handle);
      return true;
   }

private:
   //--- Initialize weights from base input parameters
   void InitBaseWeights(AdaptiveWeights &w)
   {
      w.Reset();
      w.weights[0]  = InpWeight_LiqSweep;
      w.weights[1]  = InpWeight_FVGOverlap;
      w.weights[2]  = InpWeight_Inducement;
      w.weights[3]  = InpWeight_MicroMSS;
      w.weights[4]  = InpWeight_RSIDivergence;
      w.weights[5]  = InpWeight_EMAConfluence;
      w.weights[6]  = InpWeight_VolumeSurge;
      w.weights[7]  = InpWeight_LRC;
      w.weights[8]  = InpWeight_ATRCompress;
      w.weights[9]  = InpWeight_VWAP;
      w.weights[10] = InpWeight_PDHPDL;
      w.weights[11] = InpWeight_Session;
      w.weights[12] = InpWeight_Fibonacci;
      w.weights[13] = InpWeight_WinRate;
      w.contradictionPenalty = InpContradictionPenalty;
   }

   //--- Get base input weight for signal index
   double GetBaseWeight(int idx)
   {
      switch(idx)
      {
         case 0:  return InpWeight_LiqSweep;
         case 1:  return InpWeight_FVGOverlap;
         case 2:  return InpWeight_Inducement;
         case 3:  return InpWeight_MicroMSS;
         case 4:  return InpWeight_RSIDivergence;
         case 5:  return InpWeight_EMAConfluence;
         case 6:  return InpWeight_VolumeSurge;
         case 7:  return InpWeight_LRC;
         case 8:  return InpWeight_ATRCompress;
         case 9:  return InpWeight_VWAP;
         case 10: return InpWeight_PDHPDL;
         case 11: return InpWeight_Session;
         case 12: return InpWeight_Fibonacci;
         case 13: return InpWeight_WinRate;
      }
      return 1.0;
   }

   //--- Calculate "lift" of a signal: how much it improves win rate
   //    lift > 0 = signal predicts wins, lift < 0 = signal predicts losses
   double CalcSignalLift(int sigIdx, const TradeJournalEntry &entries[], int count)
   {
      int onTotal = 0, onWins = 0;
      int offTotal = 0, offWins = 0;

      for(int i = 0; i < count; i++)
      {
         if(entries[i].signals[sigIdx])
         {
            onTotal++;
            if(entries[i].isWin) onWins++;
         }
         else
         {
            offTotal++;
            if(entries[i].isWin) offWins++;
         }
      }

      // Need minimum sample in both groups
      if(onTotal < 3 || offTotal < 3)
         return 0.0;

      double winRateOn  = (double)onWins / (double)onTotal;
      double winRateOff = (double)offWins / (double)offTotal;

      return winRateOn - winRateOff;
   }

   //--- Calculate how contradictions correlate with losses
   double CalcContradictionLift(const TradeJournalEntry &entries[], int count)
   {
      // Split into high-contradiction and low-contradiction groups
      int highContraTotal = 0, highContraWins = 0;
      int lowContraTotal = 0, lowContraWins = 0;

      for(int i = 0; i < count; i++)
      {
         if(entries[i].contradictionCount >= 2)
         {
            highContraTotal++;
            if(entries[i].isWin) highContraWins++;
         }
         else
         {
            lowContraTotal++;
            if(entries[i].isWin) lowContraWins++;
         }
      }

      if(highContraTotal < 3 || lowContraTotal < 3)
         return 0.0;

      double wrHigh = (double)highContraWins / (double)highContraTotal;
      double wrLow  = (double)lowContraWins / (double)lowContraTotal;

      // If high contradictions have lower win rate, penalty should be stronger
      // Positive lift = contradictions hurt → make penalty more negative
      return wrLow - wrHigh;
   }

   //--- Log the weight update for transparency
   void LogWeightUpdate(const TradeJournalEntry &entries[], int count)
   {
      // Calculate overall stats
      int wins = 0;
      for(int i = 0; i < count; i++)
         if(entries[i].isWin) wins++;

      double overallWR = (count > 0) ? (double)wins / count * 100.0 : 0;

      m_log.Info(StringFormat(
         "=== Adaptive Optimization Complete ===\n"
         "  Trades: %d | Win Rate: %.1f%%\n"
         "  Weights: [%.2f, %.2f, %.2f, %.2f | %.2f, %.2f, %.2f, %.2f, %.2f | %.2f, %.2f, %.2f, %.2f, %.2f]\n"
         "  Contra penalty: %.2f",
         count, overallWR,
         m_weights.weights[0], m_weights.weights[1], m_weights.weights[2], m_weights.weights[3],
         m_weights.weights[4], m_weights.weights[5], m_weights.weights[6], m_weights.weights[7], m_weights.weights[8],
         m_weights.weights[9], m_weights.weights[10], m_weights.weights[11], m_weights.weights[12], m_weights.weights[13],
         m_weights.contradictionPenalty));

      // Per-signal lift report
      for(int sig = 0; sig < ADAPTIVE_SIGNAL_COUNT; sig++)
      {
         double lift = CalcSignalLift(sig, entries, count);
         double baseW = GetBaseWeight(sig);
         string sigName = GetSignalName(sig);

         m_log.Info(StringFormat("  %s: base=%.1f adapted=%.2f lift=%+.3f",
                    sigName, baseW, m_weights.weights[sig], lift));
      }
   }

   string GetSignalName(int idx)
   {
      switch(idx)
      {
         case 0:  return "LiqSweep   ";
         case 1:  return "FVG        ";
         case 2:  return "Inducement ";
         case 3:  return "MicroMSS   ";
         case 4:  return "RSI Div    ";
         case 5:  return "EMA Conf   ";
         case 6:  return "Volume     ";
         case 7:  return "LRC        ";
         case 8:  return "ATR Comp   ";
         case 9:  return "VWAP       ";
         case 10: return "PDH/PDL    ";
         case 11: return "Session    ";
         case 12: return "Fibonacci  ";
         case 13: return "Win Rate   ";
      }
      return "Unknown    ";
   }
};

#endif
