//+------------------------------------------------------------------+
//|                                               RiskManager.mqh    |
//|                          Confluence Trading System                 |
//|                          Position sizing, loss limits, risk mgmt |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_RISKMANAGER_MQH
#define CONFLUENCE_RISKMANAGER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "StreakManager.mqh"
#include "CorrelationGuard.mqh"

//+------------------------------------------------------------------+
//| Risk Manager                                                      |
//| 2% of equity per trade. Daily/weekly loss limits.                |
//| Streak-adjusted sizing. Correlation guard. Risk budget check.    |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   CStreakManager*    m_streak;
   CCorrelationGuard* m_corrGuard;
   CLogger           m_log;

public:
   CRiskManager() : m_streak(NULL), m_corrGuard(NULL)
   { m_log.SetPrefix("Risk"); }

   void Init(CStreakManager *streak, CCorrelationGuard *corrGuard)
   {
      m_streak = streak;
      m_corrGuard = corrGuard;
   }

   //--- Calculate lot size for a trade
   double CalculateLotSize(const string symbol, double entry, double sl)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmount = equity * InpRiskPercent / 100.0;

      // Apply streak modifier
      if(m_streak != NULL)
         riskAmount *= m_streak.GetSizeMultiplier();

      // Calculate SL distance in points
      double slDistance = MathAbs(entry - sl);
      if(slDistance <= 0) return 0;

      // Get tick value and tick size
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

      if(tickValue <= 0 || tickSize <= 0) return 0;

      // Value per point
      double valuePerPoint = tickValue / tickSize;

      // Lot size = risk amount / (SL distance * value per point)
      double lots = riskAmount / (slDistance * valuePerPoint);

      // Normalize to broker constraints
      lots = NormalizeLots(symbol, lots);

      return lots;
   }

   //--- Check if daily loss limit has been reached
   bool IsDailyLossLimitReached()
   {
      if(m_streak == NULL) return false;

      m_streak.UpdateEquityTracking();
      double startEquity = m_streak.GetDailyStartEquity();
      if(startEquity <= 0) return false;

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double drawdownPct = (startEquity - currentEquity) / startEquity * 100.0;

      return (drawdownPct >= InpDailyLossLimit);
   }

   //--- Check if weekly loss limit has been reached
   bool IsWeeklyLossLimitReached()
   {
      if(m_streak == NULL) return false;

      double startEquity = m_streak.GetWeeklyStartEquity();
      if(startEquity <= 0) return false;

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double drawdownPct = (startEquity - currentEquity) / startEquity * 100.0;

      return (drawdownPct >= InpWeeklyLossLimit);
   }

   //--- Get current daily drawdown percentage
   double GetDailyDrawdownPct()
   {
      if(m_streak == NULL) return 0;

      double startEquity = m_streak.GetDailyStartEquity();
      if(startEquity <= 0) return 0;

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (startEquity - currentEquity) / startEquity * 100.0;
   }

   //--- Get current weekly drawdown percentage
   double GetWeeklyDrawdownPct()
   {
      if(m_streak == NULL) return 0;

      double startEquity = m_streak.GetWeeklyStartEquity();
      if(startEquity <= 0) return 0;

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (startEquity - currentEquity) / startEquity * 100.0;
   }

   //--- Check if we have room in the daily risk budget for another trade
   bool DailyRiskBudgetAllows()
   {
      double dailyDD = GetDailyDrawdownPct();
      // Allow new trade if daily drawdown + one max loss won't exceed limit
      return (dailyDD + InpRiskPercent < InpDailyLossLimit);
   }

   //--- Check correlation guard
   bool CorrelationAllows(const string symbol,
                           const ManagedPosition &positions[], int posCount)
   {
      if(m_corrGuard == NULL) return true;
      return m_corrGuard.IsAllowed(symbol, positions, posCount);
   }

   //--- Check max positions limit
   bool MaxPositionsAllows(int currentPositionCount)
   {
      return (currentPositionCount < InpMaxPositions);
   }

   //--- During drawdown, only allow high-quality setups
   int GetMinScoreDuringDrawdown()
   {
      if(m_streak == NULL) return InpMinScoreToTrade;

      if(m_streak.GetSizeMode() == SIZE_REDUCED)
         return SCORE_ENTER_MIN; // Only ENTER (11+) during drawdown

      return InpMinScoreToTrade;
   }

   //--- Full pre-trade risk check
   bool PreTradeCheck(const string symbol, const ScoreCard &card,
                       const ManagedPosition &positions[], int posCount)
   {
      // 1. Max positions
      if(!MaxPositionsAllows(posCount))
      {
         m_log.Info(StringFormat("%s blocked: max positions (%d/%d)",
                    symbol, posCount, InpMaxPositions));
         return false;
      }

      // 2. Correlation guard
      if(!CorrelationAllows(symbol, positions, posCount))
         return false;

      // 3. Daily risk budget
      if(!DailyRiskBudgetAllows())
      {
         m_log.Info(StringFormat("%s blocked: daily risk budget exhausted (DD=%.1f%%)",
                    symbol, GetDailyDrawdownPct()));
         return false;
      }

      // 4. Daily/weekly loss limits
      if(IsDailyLossLimitReached())
      {
         m_log.Warning("Daily loss limit reached. All trading paused.");
         return false;
      }
      if(IsWeeklyLossLimitReached())
      {
         m_log.Warning("Weekly loss limit reached. All trading paused.");
         return false;
      }

      // 5. During drawdown, require higher score
      int minScore = GetMinScoreDuringDrawdown();
      if(card.totalScore < minScore)
      {
         m_log.Info(StringFormat("%s blocked: score %d below drawdown threshold %d",
                    symbol, card.totalScore, minScore));
         return false;
      }

      return true;
   }
};

#endif
