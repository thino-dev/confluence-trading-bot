//+------------------------------------------------------------------+
//|                                                FairValueGap.mqh   |
//|                          Confluence Trading System                 |
//|                          3-candle imbalance gap detection         |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_FAIRVALUEGAP_MQH
#define CONFLUENCE_FAIRVALUEGAP_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"

//+------------------------------------------------------------------+
//| Fair Value Gap Detector                                           |
//| FVG = 3-candle formation where candle 1 wick and candle 3 wick  |
//| don't overlap, leaving a gap that price tends to fill.           |
//+------------------------------------------------------------------+
class CFairValueGap
{
private:
   CMarketData*      m_data;
   CLogger           m_log;

public:
   CFairValueGap() : m_data(NULL) { m_log.SetPrefix("FVG"); }

   void Init(CMarketData *data) { m_data = data; }

   //--- Detect all unfilled FVGs in recent bars
   int DetectFVGs(const string symbol, ENUM_TIMEFRAMES tf,
                   int lookback, FairValueGap &fvgs[], int &fvgCount)
   {
      fvgCount = 0;

      MqlRates rates[];
      int copied = m_data.GetRates(symbol, tf, 0, lookback, rates);
      if(copied < 3) return 0;

      ArrayResize(fvgs, MAX_FVG_ZONES);

      // Scan triplets: rates[i-1], rates[i], rates[i+1]
      // In series mode: i+1 is OLDER, i-1 is NEWER
      for(int i = 1; i < copied - 1; i++)
      {
         // Bullish FVG: candle before the impulse (i+1) high < candle after (i-1) low
         // Gap between older candle's high and newer candle's low
         if(rates[i - 1].low > rates[i + 1].high)
         {
            FairValueGap fvg;
            fvg.highPrice = rates[i - 1].low;   // Top of gap
            fvg.lowPrice  = rates[i + 1].high;   // Bottom of gap
            fvg.time      = rates[i].time;
            fvg.barIndex  = i;
            fvg.isBullish = true;

            // Check if gap has been filled by recent price action
            fvg.isFilled = false;
            for(int k = i - 1; k >= 0; k--)
            {
               if(rates[k].low <= fvg.lowPrice)
               {
                  fvg.isFilled = true;
                  break;
               }
            }

            if(!fvg.isFilled && fvgCount < MAX_FVG_ZONES)
            {
               AppendFVG(fvgs, fvg, fvgCount);
            }
         }

         // Bearish FVG: candle before (i+1) low > candle after (i-1) high
         if(rates[i - 1].high < rates[i + 1].low)
         {
            FairValueGap fvg;
            fvg.highPrice = rates[i + 1].low;    // Top of gap
            fvg.lowPrice  = rates[i - 1].high;   // Bottom of gap
            fvg.time      = rates[i].time;
            fvg.barIndex  = i;
            fvg.isBullish = false;

            fvg.isFilled = false;
            for(int k = i - 1; k >= 0; k--)
            {
               if(rates[k].high >= fvg.highPrice)
               {
                  fvg.isFilled = true;
                  break;
               }
            }

            if(!fvg.isFilled && fvgCount < MAX_FVG_ZONES)
            {
               AppendFVG(fvgs, fvg, fvgCount);
            }
         }
      }

      ArrayResize(fvgs, fvgCount);
      return fvgCount;
   }

   //--- Check if any FVG overlaps with the OB zone
   bool CheckFVGOverlapOB(const FairValueGap &fvgs[], int fvgCount,
                           const OrderBlock &ob,
                           ENUM_TRADE_DIRECTION direction)
   {
      for(int i = 0; i < fvgCount; i++)
      {
         // FVG must match the trade direction
         if(direction == TRADE_LONG && !fvgs[i].isBullish) continue;
         if(direction == TRADE_SHORT && fvgs[i].isBullish) continue;

         // Check overlap between FVG zone and OB zone
         double overlapHigh = MathMin(fvgs[i].highPrice, ob.highPrice);
         double overlapLow  = MathMax(fvgs[i].lowPrice, ob.lowPrice);

         if(overlapHigh > overlapLow)
            return true;
      }
      return false;
   }
};

#endif
