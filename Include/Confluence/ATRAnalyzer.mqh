//+------------------------------------------------------------------+
//|                                                ATRAnalyzer.mqh    |
//|                          Confluence Trading System                 |
//|                          ATR compression + ADX regime filter      |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_ATRANALYZER_MQH
#define CONFLUENCE_ATRANALYZER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"

//+------------------------------------------------------------------+
//| ATR Analyzer                                                      |
//| 1) ATR compression detection (replaces chart pattern detection). |
//|    Compressed ATR = consolidation before expansion = flag/triangle|
//| 2) ADX regime filter (mandatory Layer 1 check).                  |
//|    ADX > threshold = trending. Below = ranging, skip pair.       |
//+------------------------------------------------------------------+
class CATRAnalyzer
{
private:
   CMarketData*      m_data;
   CLogger           m_log;

public:
   CATRAnalyzer() : m_data(NULL) { m_log.SetPrefix("ATR"); }

   void Init(CMarketData *data) { m_data = data; }

   //--- Check if ATR is compressed (consolidation before expansion)
   bool IsATRCompressed(const string symbol, const SymbolHandles &handles)
   {
      double atrValues[];
      int copied = m_data.GetIndicatorValues(handles.atrHandle, 0, 0, 30, atrValues);
      if(copied < 25) return false;

      // Calculate 20-period moving average of ATR (bars 1-20, skip current)
      double atrMA = 0;
      for(int i = 1; i <= 20; i++)
         atrMA += atrValues[i];
      atrMA /= 20.0;

      if(atrMA <= 0) return false;

      // Current ATR vs average
      double currentATR = atrValues[0];
      double ratio = currentATR / atrMA;

      // Compression: current ATR < threshold ratio of average
      bool isCompressed = (ratio < InpATRCompressRatio);

      // Bonus: check if ATR has been declining for 5+ bars
      if(isCompressed)
      {
         int decliningCount = 0;
         for(int i = 0; i < 5; i++)
         {
            if(atrValues[i] <= atrValues[i + 1])
               decliningCount++;
         }
         // Need at least 4 of 5 declining
         return (decliningCount >= 4);
      }

      return false;
   }

   //--- Get ADX value for trend strength check (Layer 1 mandatory)
   bool IsADXAboveThreshold(const string symbol, const SymbolHandles &handles,
                              double &adxValue)
   {
      adxValue = 0;

      // ADX main line is buffer 0
      if(!m_data.GetIndicatorValue(handles.adxHandle, 0, 0, adxValue))
         return false;

      return (adxValue >= InpADXThreshold);
   }

   //--- Get current ATR value (used for trailing stop calculation)
   double GetCurrentATR(const string symbol, const SymbolHandles &handles)
   {
      double val = 0;
      m_data.GetIndicatorValue(handles.atrHandle, 0, 0, val);
      return val;
   }
};

#endif
