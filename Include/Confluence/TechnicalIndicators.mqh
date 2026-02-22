//+------------------------------------------------------------------+
//|                                          TechnicalIndicators.mqh  |
//|                          Confluence Trading System                 |
//|                          RSI divergence, EMA confluence, Volume   |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_TECHNICALINDICATORS_MQH
#define CONFLUENCE_TECHNICALINDICATORS_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"
#include "SwingDetector.mqh"

//+------------------------------------------------------------------+
//| Technical Indicator Analysis                                      |
//| RSI divergence, EMA confluence at OB, Volume surge.              |
//| Secondary confirmation only — never primary signal.               |
//+------------------------------------------------------------------+
class CTechnicalIndicators
{
private:
   CMarketData*      m_data;
   CSwingDetector*   m_swingDetector;
   CLogger           m_log;

public:
   CTechnicalIndicators() : m_data(NULL), m_swingDetector(NULL)
   { m_log.SetPrefix("Tech"); }

   void Init(CMarketData *data, CSwingDetector *swing)
   {
      m_data = data;
      m_swingDetector = swing;
   }

   //--- Detect RSI divergence at the OB zone
   bool DetectRSIDivergence(const string symbol, ENUM_TRADE_DIRECTION direction,
                             const SymbolHandles &handles)
   {
      // Get RSI values
      double rsiValues[];
      int rsiCopied = m_data.GetIndicatorValues(handles.rsiHandle, 0, 0, 30, rsiValues);
      if(rsiCopied < 20) return false;

      // Get close prices on entry TF for swing comparison
      double closes[];
      int closeCopied = m_data.GetClose(symbol, InpEntryTF, 0, 30, closes);
      if(closeCopied < 20) return false;

      if(direction == TRADE_LONG)
      {
         // Bullish divergence: price makes lower low, RSI makes higher low
         int priceLow1Bar = -1, priceLow2Bar = -1;
         double priceLow1 = 0, priceLow2 = 0;

         // Find two recent swing lows in price
         FindSwingLowInArray(closes, closeCopied, 1, 12, priceLow1, priceLow1Bar);
         FindSwingLowInArray(closes, closeCopied, priceLow1Bar + 3, 25, priceLow2, priceLow2Bar);

         if(priceLow1Bar < 0 || priceLow2Bar < 0) return false;

         double rsiAtLow1 = rsiValues[priceLow1Bar];
         double rsiAtLow2 = rsiValues[priceLow2Bar];

         // Price lower low + RSI higher low = bullish divergence
         return (priceLow1 < priceLow2 && rsiAtLow1 > rsiAtLow2);
      }
      else if(direction == TRADE_SHORT)
      {
         // Bearish divergence: price makes higher high, RSI makes lower high
         int priceHigh1Bar = -1, priceHigh2Bar = -1;
         double priceHigh1 = 0, priceHigh2 = 0;

         FindSwingHighInArray(closes, closeCopied, 1, 12, priceHigh1, priceHigh1Bar);
         FindSwingHighInArray(closes, closeCopied, priceHigh1Bar + 3, 25, priceHigh2, priceHigh2Bar);

         if(priceHigh1Bar < 0 || priceHigh2Bar < 0) return false;

         double rsiAtHigh1 = rsiValues[priceHigh1Bar];
         double rsiAtHigh2 = rsiValues[priceHigh2Bar];

         return (priceHigh1 > priceHigh2 && rsiAtHigh1 < rsiAtHigh2);
      }

      return false;
   }

   //--- Check EMA confluence at the OB zone
   //    21/50 EMA sits within proximity of OB = dynamic support/resistance aligns
   bool CheckEMAConfluence(const string symbol, const OrderBlock &ob,
                            const SymbolHandles &handles)
   {
      double emaFast = 0, emaMid = 0;

      if(!m_data.GetIndicatorValue(handles.emaFastHandle, 0, 0, emaFast)) return false;
      if(!m_data.GetIndicatorValue(handles.emaMidHandle, 0, 0, emaMid)) return false;

      double obMid = ob.midPrice;
      double proximityThreshold = obMid * InpEMAProximityPct / 100.0;

      // Check if either EMA is within proximity of the OB zone
      bool fastNearOB = (MathAbs(emaFast - obMid) <= proximityThreshold) ||
                        (emaFast >= ob.lowPrice && emaFast <= ob.highPrice);
      bool midNearOB  = (MathAbs(emaMid - obMid) <= proximityThreshold) ||
                        (emaMid >= ob.lowPrice && emaMid <= ob.highPrice);

      return (fastNearOB || midNearOB);
   }

   //--- Check volume surge: current bar volume > 1.5x 20-period average
   bool CheckVolumeSurge(const string symbol, ENUM_TIMEFRAMES tf)
   {
      long volumes[];
      int copied = m_data.GetVolume(symbol, tf, 0, InpVolAvgPeriod + 1, volumes);
      if(copied < InpVolAvgPeriod + 1) return false;

      // Calculate average volume (excluding current bar)
      double avgVolume = 0;
      for(int i = 1; i <= InpVolAvgPeriod; i++)
         avgVolume += (double)volumes[i];
      avgVolume /= InpVolAvgPeriod;

      if(avgVolume <= 0) return false;

      // Current bar volume vs average
      double currentVol = (double)volumes[0];
      return (currentVol >= avgVolume * InpVolSurgeMultiplier);
   }

   //--- Check for volume declining on recent BOS impulse candles (contradiction)
   bool IsVolumeDeclining(const string symbol, ENUM_TIMEFRAMES tf, int bars)
   {
      long volumes[];
      int copied = m_data.GetVolume(symbol, tf, 0, bars + 1, volumes);
      if(copied < bars + 1) return false;

      // Check if volume has been declining for consecutive bars
      int decliningCount = 0;
      for(int i = 0; i < bars - 1; i++)
      {
         if(volumes[i] < volumes[i + 1])
            decliningCount++;
      }

      return (decliningCount >= bars - 1);
   }

   //--- Get current RSI value
   double GetRSI(const string symbol, const SymbolHandles &handles)
   {
      double val = 0;
      m_data.GetIndicatorValue(handles.rsiHandle, 0, 0, val);
      return val;
   }

   //--- Get current EMA value
   double GetEMAFast(const SymbolHandles &handles, int shift = 0)
   {
      double val = 0;
      m_data.GetIndicatorValue(handles.emaFastHandle, 0, shift, val);
      return val;
   }

   //--- Check if price is above 200 EMA (bullish macro)
   bool IsPriceAbove200EMA(const string symbol, const SymbolHandles &handles)
   {
      double emaSlow = 0;
      if(!m_data.GetIndicatorValue(handles.emaSlowHandle, 0, 0, emaSlow))
         return false;
      return (m_data.GetBid(symbol) > emaSlow);
   }

private:
   //--- Find a swing low in a price array (simple local minimum)
   void FindSwingLowInArray(const double &arr[], int arrSize,
                             int startBar, int endBar,
                             double &lowPrice, int &lowBar)
   {
      lowPrice = DBL_MAX;
      lowBar = -1;
      endBar = MathMin(endBar, arrSize - 1);

      for(int i = startBar; i <= endBar; i++)
      {
         if(arr[i] < lowPrice)
         {
            // Check it's a local minimum (lower than neighbors)
            bool isLocal = true;
            if(i > startBar && arr[i - 1] <= arr[i]) isLocal = false;
            if(i < endBar && arr[i + 1] <= arr[i]) isLocal = false;

            if(isLocal || arr[i] < lowPrice * 0.999)
            {
               lowPrice = arr[i];
               lowBar = i;
            }
         }
      }
   }

   //--- Find a swing high in a price array (simple local maximum)
   void FindSwingHighInArray(const double &arr[], int arrSize,
                              int startBar, int endBar,
                              double &highPrice, int &highBar)
   {
      highPrice = 0;
      highBar = -1;
      endBar = MathMin(endBar, arrSize - 1);

      for(int i = startBar; i <= endBar; i++)
      {
         if(arr[i] > highPrice)
         {
            bool isLocal = true;
            if(i > startBar && arr[i - 1] >= arr[i]) isLocal = false;
            if(i < endBar && arr[i + 1] >= arr[i]) isLocal = false;

            if(isLocal || arr[i] > highPrice * 1.001)
            {
               highPrice = arr[i];
               highBar = i;
            }
         }
      }
   }
};

#endif
