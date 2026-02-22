//+------------------------------------------------------------------+
//|                                                SwingDetector.mqh  |
//|                          Confluence Trading System                 |
//|                          Fractal-based swing high/low detection   |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_SWINGDETECTOR_MQH
#define CONFLUENCE_SWINGDETECTOR_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"

//+------------------------------------------------------------------+
//| Swing Point Detector                                              |
//| Identifies swing highs and lows using a fractal-based approach.  |
//| A swing high has its high > N bars on each side.                 |
//| A swing low has its low < N bars on each side.                   |
//+------------------------------------------------------------------+
class CSwingDetector
{
private:
   CMarketData*      m_data;
   CLogger           m_log;

public:
   CSwingDetector() : m_data(NULL) { m_log.SetPrefix("Swing"); }

   void Init(CMarketData *data) { m_data = data; }

   //--- Detect all swing highs and lows for a symbol/timeframe
   //    Results are sorted most-recent-first (index 0 = newest)
   bool DetectSwings(const string symbol, ENUM_TIMEFRAMES tf,
                     int lookback, int leftBars, int rightBars,
                     SwingPoint &highs[], int &highCount,
                     SwingPoint &lows[], int &lowCount)
   {
      highCount = 0;
      lowCount  = 0;

      MqlRates rates[];
      int copied = m_data.GetRates(symbol, tf, 0, lookback, rates);
      if(copied < leftBars + rightBars + 1)
         return false;

      ArrayResize(highs, MAX_SWING_POINTS);
      ArrayResize(lows, MAX_SWING_POINTS);

      // Scan from rightBars to copied-leftBars
      // rates[] is series-ordered: [0]=current, [1]=previous, etc.
      for(int i = rightBars; i < copied - leftBars; i++)
      {
         bool isSwingHigh = true;
         bool isSwingLow  = true;

         // Check left side
         for(int j = 1; j <= leftBars; j++)
         {
            if(rates[i + j].high >= rates[i].high) isSwingHigh = false;
            if(rates[i + j].low  <= rates[i].low)  isSwingLow  = false;
            if(!isSwingHigh && !isSwingLow) break;
         }

         // Check right side (more recent bars)
         if(isSwingHigh || isSwingLow)
         {
            for(int j = 1; j <= rightBars; j++)
            {
               if(rates[i - j].high >= rates[i].high) isSwingHigh = false;
               if(rates[i - j].low  <= rates[i].low)  isSwingLow  = false;
               if(!isSwingHigh && !isSwingLow) break;
            }
         }

         if(isSwingHigh && highCount < MAX_SWING_POINTS)
         {
            SwingPoint sp;
            sp.price    = rates[i].high;
            sp.time     = rates[i].time;
            sp.barIndex = i;
            sp.isHigh   = true;
            highs[highCount] = sp;
            highCount++;
         }

         if(isSwingLow && lowCount < MAX_SWING_POINTS)
         {
            SwingPoint sp;
            sp.price    = rates[i].low;
            sp.time     = rates[i].time;
            sp.barIndex = i;
            sp.isHigh   = false;
            lows[lowCount] = sp;
            lowCount++;
         }
      }

      // Trim arrays to actual count
      ArrayResize(highs, highCount);
      ArrayResize(lows, lowCount);

      // Already in most-recent-first order since rates[] is series
      return (highCount > 0 || lowCount > 0);
   }

   //--- Find the most recent swing high above a given price
   bool FindNearestSwingHigh(const SwingPoint &highs[], int count,
                              double abovePrice, SwingPoint &result)
   {
      for(int i = 0; i < count; i++)
      {
         if(highs[i].price > abovePrice)
         {
            result = highs[i];
            return true;
         }
      }
      return false;
   }

   //--- Find the most recent swing low below a given price
   bool FindNearestSwingLow(const SwingPoint &lows[], int count,
                             double belowPrice, SwingPoint &result)
   {
      for(int i = 0; i < count; i++)
      {
         if(lows[i].price < belowPrice)
         {
            result = lows[i];
            return true;
         }
      }
      return false;
   }

   //--- Get the highest swing high in the array
   double GetHighestSwing(const SwingPoint &highs[], int count)
   {
      double highest = 0;
      for(int i = 0; i < count; i++)
         if(highs[i].price > highest)
            highest = highs[i].price;
      return highest;
   }

   //--- Get the lowest swing low in the array
   double GetLowestSwing(const SwingPoint &lows[], int count)
   {
      if(count == 0) return 0;
      double lowest = lows[0].price;
      for(int i = 1; i < count; i++)
         if(lows[i].price < lowest)
            lowest = lows[i].price;
      return lowest;
   }

   //--- Get the most significant recent swing range (for Fib/zone calc)
   bool GetSwingRange(const SwingPoint &highs[], int highCount,
                      const SwingPoint &lows[], int lowCount,
                      double &rangeHigh, double &rangeLow)
   {
      if(highCount < 1 || lowCount < 1)
         return false;

      // Use the most recent significant high and low
      rangeHigh = highs[0].price;
      rangeLow  = lows[0].price;

      // Ensure range makes sense
      if(rangeHigh <= rangeLow)
      {
         // Try expanding to second swing if available
         if(highCount > 1) rangeHigh = MathMax(highs[0].price, highs[1].price);
         if(lowCount > 1)  rangeLow  = MathMin(lows[0].price, lows[1].price);
      }

      return (rangeHigh > rangeLow);
   }
};

#endif
