//+------------------------------------------------------------------+
//|                                                  MarketData.mqh   |
//|                          Confluence Trading System                 |
//|                          Cross-symbol data fetching + handles     |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_MARKETDATA_MQH
#define CONFLUENCE_MARKETDATA_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| Cross-symbol market data manager                                  |
//+------------------------------------------------------------------+
class CMarketData
{
private:
   SymbolHandles     m_handles[MAX_SYMBOLS];
   int               m_symbolCount;
   datetime          m_lastBarTime[MAX_SYMBOLS]; // Per-symbol new-bar detection
   CLogger           m_log;

public:
   CMarketData() : m_symbolCount(0) { m_log.SetPrefix("MktData"); }

   //--- Initialize indicator handles for all symbols
   bool Init(const string &symbols[], int count)
   {
      m_symbolCount = MathMin(count, MAX_SYMBOLS);

      for(int i = 0; i < m_symbolCount; i++)
      {
         m_handles[i].Reset();
         m_handles[i].symbol = symbols[i];
         m_lastBarTime[i] = 0;

         // Ensure symbol is in Market Watch
         if(!SymbolSelect(symbols[i], true))
         {
            m_log.Warning(StringFormat("Symbol %s not available at broker", symbols[i]));
            continue;
         }

         // Create indicator handles on the execution timeframe
         m_handles[i].adxHandle = iADX(symbols[i], InpHTF_Primary, InpADXPeriod);
         m_handles[i].rsiHandle = iRSI(symbols[i], InpEntryTF, InpRSIPeriod, PRICE_CLOSE);
         m_handles[i].emaFastHandle = iMA(symbols[i], InpEntryTF, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
         m_handles[i].emaMidHandle  = iMA(symbols[i], InpEntryTF, InpEMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
         m_handles[i].emaSlowHandle = iMA(symbols[i], InpEntryTF, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
         m_handles[i].atrHandle = iATR(symbols[i], InpExecutionTF, InpATRPeriod);

         // Validate handles
         if(m_handles[i].adxHandle == INVALID_HANDLE ||
            m_handles[i].rsiHandle == INVALID_HANDLE ||
            m_handles[i].emaFastHandle == INVALID_HANDLE ||
            m_handles[i].emaMidHandle == INVALID_HANDLE ||
            m_handles[i].emaSlowHandle == INVALID_HANDLE ||
            m_handles[i].atrHandle == INVALID_HANDLE)
         {
            m_log.Error(StringFormat("Failed to create indicator handles for %s", symbols[i]));
            m_handles[i].initialized = false;
         }
         else
         {
            m_handles[i].initialized = true;
            m_log.Info(StringFormat("Handles initialized for %s", symbols[i]));
         }
      }

      return true;
   }

   //--- Release all indicator handles
   void Deinit()
   {
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(m_handles[i].adxHandle != INVALID_HANDLE)      IndicatorRelease(m_handles[i].adxHandle);
         if(m_handles[i].rsiHandle != INVALID_HANDLE)      IndicatorRelease(m_handles[i].rsiHandle);
         if(m_handles[i].emaFastHandle != INVALID_HANDLE)  IndicatorRelease(m_handles[i].emaFastHandle);
         if(m_handles[i].emaMidHandle != INVALID_HANDLE)   IndicatorRelease(m_handles[i].emaMidHandle);
         if(m_handles[i].emaSlowHandle != INVALID_HANDLE)  IndicatorRelease(m_handles[i].emaSlowHandle);
         if(m_handles[i].atrHandle != INVALID_HANDLE)      IndicatorRelease(m_handles[i].atrHandle);
         m_handles[i].Reset();
      }
   }

   //--- Get symbol index by name
   int GetSymbolIndex(const string symbol)
   {
      for(int i = 0; i < m_symbolCount; i++)
         if(m_handles[i].symbol == symbol)
            return i;
      return -1;
   }

   //--- Get handles for a symbol
   bool GetHandles(const string symbol, SymbolHandles &handles)
   {
      int idx = GetSymbolIndex(symbol);
      if(idx < 0 || !m_handles[idx].initialized)
         return false;
      handles = m_handles[idx];
      return true;
   }

   //--- New bar detection per symbol on execution timeframe
   bool IsNewBar(const string symbol)
   {
      int idx = GetSymbolIndex(symbol);
      if(idx < 0) return false;

      datetime current = iTime(symbol, InpExecutionTF, 0);
      if(current == 0) return false;

      if(current != m_lastBarTime[idx])
      {
         m_lastBarTime[idx] = current;
         return true;
      }
      return false;
   }

   //--- Copy rates for any symbol/timeframe
   int GetRates(const string symbol, ENUM_TIMEFRAMES tf, int startPos, int count, MqlRates &rates[])
   {
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, startPos, count, rates);
      if(copied < count)
         m_log.Warning(StringFormat("GetRates %s %s: requested %d, got %d",
                       symbol, EnumToString(tf), count, copied));
      return copied;
   }

   //--- Copy close prices
   int GetClose(const string symbol, ENUM_TIMEFRAMES tf, int startPos, int count, double &closes[])
   {
      ArraySetAsSeries(closes, true);
      return CopyClose(symbol, tf, startPos, count, closes);
   }

   //--- Copy high prices
   int GetHigh(const string symbol, ENUM_TIMEFRAMES tf, int startPos, int count, double &highs[])
   {
      ArraySetAsSeries(highs, true);
      return CopyHigh(symbol, tf, startPos, count, highs);
   }

   //--- Copy low prices
   int GetLow(const string symbol, ENUM_TIMEFRAMES tf, int startPos, int count, double &lows[])
   {
      ArraySetAsSeries(lows, true);
      return CopyLow(symbol, tf, startPos, count, lows);
   }

   //--- Copy tick volume
   int GetVolume(const string symbol, ENUM_TIMEFRAMES tf, int startPos, int count, long &volumes[])
   {
      ArraySetAsSeries(volumes, true);
      return CopyTickVolume(symbol, tf, startPos, count, volumes);
   }

   //--- Get indicator buffer value
   bool GetIndicatorValue(int handle, int bufferIdx, int shift, double &value)
   {
      double buf[1];
      if(CopyBuffer(handle, bufferIdx, shift, 1, buf) < 1)
         return false;
      value = buf[0];
      return true;
   }

   //--- Get multiple indicator values
   int GetIndicatorValues(int handle, int bufferIdx, int startPos, int count, double &values[])
   {
      ArraySetAsSeries(values, true);
      return CopyBuffer(handle, bufferIdx, startPos, count, values);
   }

   //--- Get current bid price for any symbol
   double GetBid(const string symbol)
   {
      return SymbolInfoDouble(symbol, SYMBOL_BID);
   }

   //--- Get current ask price for any symbol
   double GetAsk(const string symbol)
   {
      return SymbolInfoDouble(symbol, SYMBOL_ASK);
   }

   //--- Get current spread in points
   int GetSpreadPoints(const string symbol)
   {
      return (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   }

   //--- Check if symbol data is ready (enough bars available)
   bool IsDataReady(const string symbol, ENUM_TIMEFRAMES tf, int minBars)
   {
      int bars = iBars(symbol, tf);
      return (bars >= minBars);
   }

   //--- Get symbol count
   int GetSymbolCount() const { return m_symbolCount; }

   //--- Get symbol name by index
   string GetSymbolName(int idx) const
   {
      if(idx >= 0 && idx < m_symbolCount)
         return m_handles[idx].symbol;
      return "";
   }
};

#endif
