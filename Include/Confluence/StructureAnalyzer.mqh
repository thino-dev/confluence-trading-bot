//+------------------------------------------------------------------+
//|                                            StructureAnalyzer.mqh  |
//|                          Confluence Trading System                 |
//|                          HTF Trend, BOS/CHoCH counting           |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_STRUCTUREANALYZER_MQH
#define CONFLUENCE_STRUCTUREANALYZER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"
#include "SwingDetector.mqh"

//+------------------------------------------------------------------+
//| Market Structure Analyzer                                         |
//| Determines HTF trend, counts BOS, detects CHoCH.                |
//+------------------------------------------------------------------+
class CStructureAnalyzer
{
private:
   CMarketData*      m_data;
   CSwingDetector*   m_swingDetector;
   CLogger           m_log;

public:
   CStructureAnalyzer() : m_data(NULL), m_swingDetector(NULL) { m_log.SetPrefix("Structure"); }

   void Init(CMarketData *data, CSwingDetector *swing)
   {
      m_data = data;
      m_swingDetector = swing;
   }

   //--- Determine HTF trend with cascade: Primary -> Fallback1 -> Fallback2
   ENUM_TREND_DIRECTION DetermineHTFTrend(const string symbol, ENUM_TIMEFRAMES &usedTF)
   {
      ENUM_TIMEFRAMES timeframes[3];
      timeframes[0] = InpHTF_Primary;
      timeframes[1] = InpHTF_Fallback1;
      timeframes[2] = InpHTF_Fallback2;

      for(int t = 0; t < 3; t++)
      {
         SwingPoint highs[], lows[];
         int highCount = 0, lowCount = 0;

         if(!m_swingDetector.DetectSwings(symbol, timeframes[t],
            InpSwingLookback, InpSwingLeftBars, InpSwingRightBars,
            highs, highCount, lows, lowCount))
            continue;

         if(highCount < 2 || lowCount < 2)
            continue;

         ENUM_TREND_DIRECTION trend = ClassifyTrend(highs, highCount, lows, lowCount);

         if(trend != TREND_NEUTRAL)
         {
            usedTF = timeframes[t];
            return trend;
         }
      }

      usedTF = InpHTF_Primary;
      return TREND_NEUTRAL;
   }

   //--- Count consecutive BOS on the execution timeframe
   //    Returns BOS count and populates the last relevant OB retracement bar index
   int CountConsecutiveBOS(const string symbol,
                           ENUM_TREND_DIRECTION htfTrend,
                           BOSEvent &bosEvents[], int &bosEventCount,
                           CHoCHEvent &chochEvents[], int &chochEventCount,
                           int &lastRetracementBar)
   {
      bosEventCount  = 0;
      chochEventCount = 0;
      lastRetracementBar = -1;

      SwingPoint highs[], lows[];
      int highCount = 0, lowCount = 0;

      if(!m_swingDetector.DetectSwings(symbol, InpExecutionTF,
         InpSwingLookback, InpSwingLeftBars, InpSwingRightBars,
         highs, highCount, lows, lowCount))
         return 0;

      ArrayResize(bosEvents, MAX_BOS_EVENTS);
      ArrayResize(chochEvents, MAX_BOS_EVENTS);

      int consecutiveBOS = 0;
      int totalBOS = 0;

      if(htfTrend == TREND_BULLISH)
         consecutiveBOS = CountBullishBOS(highs, highCount, lows, lowCount,
                                          bosEvents, bosEventCount,
                                          chochEvents, chochEventCount,
                                          lastRetracementBar);
      else if(htfTrend == TREND_BEARISH)
         consecutiveBOS = CountBearishBOS(highs, highCount, lows, lowCount,
                                          bosEvents, bosEventCount,
                                          chochEvents, chochEventCount,
                                          lastRetracementBar);

      ArrayResize(bosEvents, bosEventCount);
      ArrayResize(chochEvents, chochEventCount);

      return consecutiveBOS;
   }

   //--- Detect CHoCH on a specific timeframe (used for trade exit)
   bool DetectCHoCHSince(const string symbol, ENUM_TIMEFRAMES tf,
                          ENUM_TRADE_DIRECTION tradeDir, datetime sinceTime)
   {
      SwingPoint highs[], lows[];
      int highCount = 0, lowCount = 0;

      if(!m_swingDetector.DetectSwings(symbol, tf, 50,
         MathMin(InpSwingLeftBars, 2), MathMin(InpSwingRightBars, 2),
         highs, highCount, lows, lowCount))
         return false;

      if(tradeDir == TRADE_LONG)
      {
         // Bearish CHoCH = swing low breaks below previous swing low
         for(int i = 0; i < lowCount - 1; i++)
         {
            if(lows[i].time < sinceTime) break;
            if(lows[i].price < lows[i + 1].price)
               return true; // Lower low = CHoCH against long
         }
      }
      else if(tradeDir == TRADE_SHORT)
      {
         // Bullish CHoCH = swing high breaks above previous swing high
         for(int i = 0; i < highCount - 1; i++)
         {
            if(highs[i].time < sinceTime) break;
            if(highs[i].price > highs[i + 1].price)
               return true; // Higher high = CHoCH against short
         }
      }

      return false;
   }

private:
   //--- Classify trend from swing structure
   ENUM_TREND_DIRECTION ClassifyTrend(const SwingPoint &highs[], int highCount,
                                       const SwingPoint &lows[], int lowCount)
   {
      // Compare most recent 2 swing highs and 2 swing lows
      // highs[0] = most recent, highs[1] = previous
      bool higherHigh = (highs[0].price > highs[1].price);
      bool higherLow  = (lows[0].price > lows[1].price);
      bool lowerHigh  = (highs[0].price < highs[1].price);
      bool lowerLow   = (lows[0].price < lows[1].price);

      if(higherHigh && higherLow)  return TREND_BULLISH;
      if(lowerHigh && lowerLow)    return TREND_BEARISH;

      // If we have 3+ points, check the broader pattern
      if(highCount >= 3 && lowCount >= 3)
      {
         int bullishCount = 0, bearishCount = 0;

         for(int i = 0; i < MathMin(highCount - 1, 3); i++)
         {
            if(highs[i].price > highs[i + 1].price) bullishCount++;
            else bearishCount++;
         }
         for(int i = 0; i < MathMin(lowCount - 1, 3); i++)
         {
            if(lows[i].price > lows[i + 1].price) bullishCount++;
            else bearishCount++;
         }

         if(bullishCount >= 4) return TREND_BULLISH;
         if(bearishCount >= 4) return TREND_BEARISH;
      }

      return TREND_NEUTRAL;
   }

   //--- Count consecutive bullish BOS (uptrend)
   int CountBullishBOS(const SwingPoint &highs[], int highCount,
                        const SwingPoint &lows[], int lowCount,
                        BOSEvent &bosEvents[], int &bosCount,
                        CHoCHEvent &chochEvents[], int &chochCount,
                        int &lastRetracementBar)
   {
      // Work from oldest to newest to track sequence
      // highs[highCount-1] = oldest, highs[0] = newest
      int consecutive = 0;
      int maxConsecutive = 0;
      int bestRetracementBar = -1;
      double prevHighLevel = 0;
      double prevLowLevel = 0;
      bool hasPrevHigh = false;

      // Iterate swing highs from old to new
      for(int i = highCount - 1; i >= 0; i--)
      {
         if(!hasPrevHigh)
         {
            prevHighLevel = highs[i].price;
            hasPrevHigh = true;
            continue;
         }

         // Check if current high breaks above previous high = BOS
         if(highs[i].price > prevHighLevel)
         {
            // Check for CHoCH between this BOS and the previous one
            bool chochBetween = false;
            if(lowCount >= 2)
            {
               for(int j = lowCount - 1; j > 0; j--)
               {
                  // Only check lows between previous high and current high
                  if(lows[j].time <= highs[i + 1].time) continue;
                  if(lows[j].time >= highs[i].time) break;

                  // Check if this low breaks below its predecessor
                  if(j < lowCount - 1 && lows[j].price < lows[j + 1].price)
                  {
                     chochBetween = true;
                     CHoCHEvent ev;
                     ev.type = CHOCH_BEARISH;
                     ev.brokenLevel = lows[j + 1].price;
                     ev.time = lows[j].time;
                     ev.barIndex = lows[j].barIndex;
                     AppendCHoCH(chochEvents, ev, chochCount);
                     break;
                  }
               }
            }

            if(chochBetween)
            {
               consecutive = 1; // Reset and start counting from this BOS
            }
            else
            {
               consecutive++;
            }

            BOSEvent bos;
            bos.type = BOS_BULLISH;
            bos.brokenLevel = prevHighLevel;
            bos.breakPrice = highs[i].price;
            bos.time = highs[i].time;
            bos.barIndex = highs[i].barIndex;
            AppendBOS(bosEvents, bos, bosCount);

            if(consecutive > maxConsecutive)
            {
               maxConsecutive = consecutive;
               // The retracement bar is the swing low between this BOS and the previous
               for(int j = 0; j < lowCount; j++)
               {
                  if(lows[j].time < highs[i].time && (i + 1 >= highCount || lows[j].time > highs[i + 1].time))
                  {
                     bestRetracementBar = lows[j].barIndex;
                     break;
                  }
               }
            }

            prevHighLevel = highs[i].price;
         }
         else
         {
            prevHighLevel = MathMax(prevHighLevel, highs[i].price);
         }
      }

      lastRetracementBar = bestRetracementBar;
      return maxConsecutive;
   }

   //--- Count consecutive bearish BOS (downtrend)
   int CountBearishBOS(const SwingPoint &highs[], int highCount,
                        const SwingPoint &lows[], int lowCount,
                        BOSEvent &bosEvents[], int &bosCount,
                        CHoCHEvent &chochEvents[], int &chochCount,
                        int &lastRetracementBar)
   {
      int consecutive = 0;
      int maxConsecutive = 0;
      int bestRetracementBar = -1;
      double prevLowLevel = 0;
      bool hasPrevLow = false;

      for(int i = lowCount - 1; i >= 0; i--)
      {
         if(!hasPrevLow)
         {
            prevLowLevel = lows[i].price;
            hasPrevLow = true;
            continue;
         }

         if(lows[i].price < prevLowLevel)
         {
            bool chochBetween = false;
            if(highCount >= 2)
            {
               for(int j = highCount - 1; j > 0; j--)
               {
                  if(highs[j].time <= lows[i + 1].time) continue;
                  if(highs[j].time >= lows[i].time) break;

                  if(j < highCount - 1 && highs[j].price > highs[j + 1].price)
                  {
                     chochBetween = true;
                     CHoCHEvent ev;
                     ev.type = CHOCH_BULLISH;
                     ev.brokenLevel = highs[j + 1].price;
                     ev.time = highs[j].time;
                     ev.barIndex = highs[j].barIndex;
                     AppendCHoCH(chochEvents, ev, chochCount);
                     break;
                  }
               }
            }

            if(chochBetween)
               consecutive = 1;
            else
               consecutive++;

            BOSEvent bos;
            bos.type = BOS_BEARISH;
            bos.brokenLevel = prevLowLevel;
            bos.breakPrice = lows[i].price;
            bos.time = lows[i].time;
            bos.barIndex = lows[i].barIndex;
            AppendBOS(bosEvents, bos, bosCount);

            if(consecutive > maxConsecutive)
            {
               maxConsecutive = consecutive;
               for(int j = 0; j < highCount; j++)
               {
                  if(highs[j].time < lows[i].time && (i + 1 >= lowCount || highs[j].time > lows[i + 1].time))
                  {
                     bestRetracementBar = highs[j].barIndex;
                     break;
                  }
               }
            }

            prevLowLevel = lows[i].price;
         }
         else
         {
            prevLowLevel = MathMin(prevLowLevel, lows[i].price);
         }
      }

      lastRetracementBar = bestRetracementBar;
      return maxConsecutive;
   }
};

#endif
