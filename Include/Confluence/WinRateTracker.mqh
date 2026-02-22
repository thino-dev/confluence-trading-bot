//+------------------------------------------------------------------+
//|                                             WinRateTracker.mqh    |
//|                          Confluence Trading System                 |
//|                          Pair win-rate persistence (CSV)          |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_WINRATETRACKER_MQH
#define CONFLUENCE_WINRATETRACKER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| Win Rate Tracker                                                  |
//| Persists trade results per pair to CSV file.                     |
//| Replaces manual "pair backtest" from original system.            |
//| If pair has 2+ historical wins = +2 confluence points.           |
//+------------------------------------------------------------------+
class CWinRateTracker
{
private:
   WinRateRecord     m_records[MAX_SYMBOLS];
   int               m_recordCount;
   CLogger           m_log;

public:
   CWinRateTracker() : m_recordCount(0) { m_log.SetPrefix("WinRate"); }

   //--- Load records from CSV file
   bool LoadFromFile(const string filename)
   {
      m_recordCount = 0;

      int handle = FileOpen(filename, FILE_READ | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
      {
         m_log.Info("No existing win-rate file. Starting fresh.");
         return false;
      }

      // Skip header line
      if(!FileIsEnding(handle))
         FileReadString(handle); // Skip header row by reading to next line

      while(!FileIsEnding(handle) && m_recordCount < MAX_SYMBOLS)
      {
         string sym = FileReadString(handle);
         if(StringLen(sym) == 0) break;

         m_records[m_recordCount].symbol          = sym;
         m_records[m_recordCount].totalTrades     = (int)FileReadNumber(handle);
         m_records[m_recordCount].wins            = (int)FileReadNumber(handle);
         m_records[m_recordCount].losses          = (int)FileReadNumber(handle);
         m_records[m_recordCount].winRate         = FileReadNumber(handle);
         m_records[m_recordCount].totalProfitPips = FileReadNumber(handle);
         m_records[m_recordCount].totalLossPips   = FileReadNumber(handle);
         m_records[m_recordCount].profitFactor    = FileReadNumber(handle);
         m_records[m_recordCount].lastUpdated     = FileReadDatetime(handle);
         m_recordCount++;
      }

      FileClose(handle);
      m_log.Info(StringFormat("Loaded %d win-rate records", m_recordCount));
      return true;
   }

   //--- Save records to CSV file
   bool SaveToFile(const string filename)
   {
      int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
      {
         m_log.Error("Cannot write win-rate file");
         return false;
      }

      // Write header
      FileWrite(handle, "SYMBOL", "TOTAL_TRADES", "WINS", "LOSSES",
                "WIN_RATE", "PROFIT_PIPS", "LOSS_PIPS",
                "PROFIT_FACTOR", "LAST_UPDATED");

      for(int i = 0; i < m_recordCount; i++)
      {
         FileWrite(handle,
            m_records[i].symbol,
            IntegerToString(m_records[i].totalTrades),
            IntegerToString(m_records[i].wins),
            IntegerToString(m_records[i].losses),
            DoubleToString(m_records[i].winRate, 2),
            DoubleToString(m_records[i].totalProfitPips, 1),
            DoubleToString(m_records[i].totalLossPips, 1),
            DoubleToString(m_records[i].profitFactor, 2),
            TimeToString(m_records[i].lastUpdated));
      }

      FileClose(handle);
      return true;
   }

   //--- Record a completed trade result
   void RecordTrade(const string symbol, bool isWin, double profitPips)
   {
      int idx = FindOrCreateRecord(symbol);
      if(idx < 0) return;

      m_records[idx].totalTrades++;

      if(isWin)
      {
         m_records[idx].wins++;
         m_records[idx].totalProfitPips += MathAbs(profitPips);
      }
      else
      {
         m_records[idx].losses++;
         m_records[idx].totalLossPips += MathAbs(profitPips);
      }

      // Recalculate derived fields
      if(m_records[idx].totalTrades > 0)
         m_records[idx].winRate = (double)m_records[idx].wins / m_records[idx].totalTrades * 100.0;
      if(m_records[idx].totalLossPips > 0)
         m_records[idx].profitFactor = m_records[idx].totalProfitPips / m_records[idx].totalLossPips;

      m_records[idx].lastUpdated = TimeCurrent();
   }

   //--- Check if pair has minimum historical wins
   bool HasMinimumWins(const string symbol, int minWins = 2)
   {
      int idx = FindRecord(symbol);
      if(idx < 0) return false;
      return (m_records[idx].wins >= minWins);
   }

   //--- Get win count for a symbol
   int GetWinCount(const string symbol)
   {
      int idx = FindRecord(symbol);
      if(idx < 0) return 0;
      return m_records[idx].wins;
   }

   //--- Get win rate for a symbol
   double GetWinRate(const string symbol)
   {
      int idx = FindRecord(symbol);
      if(idx < 0) return 0;
      return m_records[idx].winRate;
   }

private:
   int FindRecord(const string symbol)
   {
      for(int i = 0; i < m_recordCount; i++)
         if(m_records[i].symbol == symbol)
            return i;
      return -1;
   }

   int FindOrCreateRecord(const string symbol)
   {
      int idx = FindRecord(symbol);
      if(idx >= 0) return idx;

      if(m_recordCount >= MAX_SYMBOLS)
      {
         m_log.Error("Win-rate tracker full");
         return -1;
      }

      m_records[m_recordCount].Reset();
      m_records[m_recordCount].symbol = symbol;
      m_recordCount++;
      return m_recordCount - 1;
   }
};

#endif
