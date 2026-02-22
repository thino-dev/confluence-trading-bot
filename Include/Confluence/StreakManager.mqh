//+------------------------------------------------------------------+
//|                                              StreakManager.mqh    |
//|                          Confluence Trading System                 |
//|                          Win/loss streak tracking + size adjust   |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_STREAKMANAGER_MQH
#define CONFLUENCE_STREAKMANAGER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| Streak Manager                                                    |
//| Tracks consecutive wins/losses and adjusts position size mode.   |
//| After 3 losses  -> SIZE_REDUCED (50%)                            |
//| After 3 wins at reduced -> restore SIZE_NORMAL                   |
//| After 5 wins at full on PRIORITY -> SIZE_BOOSTED (150%)          |
//+------------------------------------------------------------------+
class CStreakManager
{
private:
   StreakState        m_state;
   CLogger           m_log;

public:
   CStreakManager() { m_log.SetPrefix("Streak"); m_state.Reset(); }

   //--- Record a trade result and update streak
   void RecordResult(bool isWin, ENUM_QUALITY_LEVEL quality)
   {
      if(isWin)
      {
         m_state.consecutiveWins++;
         m_state.consecutiveLosses = 0;

         switch(m_state.currentSizeMode)
         {
            case SIZE_REDUCED:
               m_state.winsAtReduced++;
               if(m_state.winsAtReduced >= InpConsecWinRestore)
               {
                  m_state.currentSizeMode = SIZE_NORMAL;
                  m_state.winsAtReduced = 0;
                  m_log.Info("Streak restored to NORMAL size after wins at reduced");
               }
               break;

            case SIZE_NORMAL:
               if(quality >= QUALITY_PRIORITY)
               {
                  m_state.winsAtFullOnPriority++;
                  if(m_state.winsAtFullOnPriority >= InpConsecWinBoost)
                  {
                     m_state.currentSizeMode = SIZE_BOOSTED;
                     m_log.Info("Streak BOOSTED: 5+ wins at full size on PRIORITY setups");
                  }
               }
               else
               {
                  m_state.winsAtFullOnPriority = 0; // Reset if non-PRIORITY win
               }
               break;

            case SIZE_BOOSTED:
               // Stay boosted while winning
               break;
         }
      }
      else
      {
         m_state.consecutiveLosses++;
         m_state.consecutiveWins = 0;
         m_state.winsAtFullOnPriority = 0;

         // Any loss exits boosted mode
         if(m_state.currentSizeMode == SIZE_BOOSTED)
         {
            m_state.currentSizeMode = SIZE_NORMAL;
            m_log.Info("Lost BOOSTED mode after loss");
         }

         if(m_state.consecutiveLosses >= InpConsecLossThreshold &&
            m_state.currentSizeMode == SIZE_NORMAL)
         {
            m_state.currentSizeMode = SIZE_REDUCED;
            m_state.winsAtReduced = 0;
            m_log.Warning(StringFormat("REDUCED size activated after %d consecutive losses",
                          m_state.consecutiveLosses));
         }
      }
   }

   //--- Get current size mode
   ENUM_SIZE_MODE GetSizeMode() const { return m_state.currentSizeMode; }

   //--- Get size multiplier based on current mode
   double GetSizeMultiplier() const
   {
      switch(m_state.currentSizeMode)
      {
         case SIZE_REDUCED: return InpReducedSizeFactor;
         case SIZE_BOOSTED: return InpBoostedSizeFactor;
         default:           return 1.0;
      }
   }

   //--- Get streak state for dashboard display
   void GetState(StreakState &state) const { state = m_state; }

   int GetConsecutiveWins() const   { return m_state.consecutiveWins; }
   int GetConsecutiveLosses() const { return m_state.consecutiveLosses; }

   //--- Update daily/weekly equity tracking
   void UpdateEquityTracking()
   {
      datetime now = TimeCurrent();
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Reset daily equity if new day
      datetime todayStart = StartOfDay(now);
      if(m_state.dailyResetTime < todayStart)
      {
         m_state.dailyStartEquity = equity;
         m_state.dailyResetTime = todayStart;
      }

      // Reset weekly equity if new week
      datetime weekStart = StartOfWeek(now);
      if(m_state.weeklyResetTime < weekStart)
      {
         m_state.weeklyStartEquity = equity;
         m_state.weeklyResetTime = weekStart;
      }
   }

   double GetDailyStartEquity() const  { return m_state.dailyStartEquity; }
   double GetWeeklyStartEquity() const { return m_state.weeklyStartEquity; }

   //--- Save state to binary file
   bool SaveState(const string filename)
   {
      int handle = FileOpen(filename, FILE_WRITE | FILE_BIN);
      if(handle == INVALID_HANDLE) return false;
      FileWriteStruct(handle, m_state);
      FileClose(handle);
      return true;
   }

   //--- Load state from binary file
   bool LoadState(const string filename)
   {
      int handle = FileOpen(filename, FILE_READ | FILE_BIN);
      if(handle == INVALID_HANDLE)
      {
         m_state.Reset();
         return false;
      }
      FileReadStruct(handle, m_state);
      FileClose(handle);
      m_log.Info(StringFormat("Loaded streak state: mode=%d, W=%d, L=%d",
                 m_state.currentSizeMode, m_state.consecutiveWins,
                 m_state.consecutiveLosses));
      return true;
   }
};

#endif
