//+------------------------------------------------------------------+
//|                                          OrderBlockDetector.mqh   |
//|                          Confluence Trading System                 |
//|                          OB identification + validation           |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_ORDERBLOCKDETECTOR_MQH
#define CONFLUENCE_ORDERBLOCKDETECTOR_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"

//+------------------------------------------------------------------+
//| Order Block Detector                                              |
//| Finds the last opposing candle before an impulse move.           |
//| Validates that the OB has not been mitigated.                    |
//+------------------------------------------------------------------+
class COrderBlockDetector
{
private:
   CMarketData*      m_data;
   CLogger           m_log;

public:
   COrderBlockDetector() : m_data(NULL) { m_log.SetPrefix("OB"); }

   void Init(CMarketData *data) { m_data = data; }

   //--- Find the most relevant order block after BOS confirmation
   //    retracementBar = the bar index of the retracement that created the OB
   bool FindOrderBlock(const string symbol, ENUM_TIMEFRAMES tf,
                        ENUM_TREND_DIRECTION trend,
                        int retracementBar,
                        const BOSEvent &lastBOS,
                        OrderBlock &ob)
   {
      ob.Reset();

      MqlRates rates[];
      int copied = m_data.GetRates(symbol, tf, 0, InpSwingLookback, rates);
      if(copied < retracementBar + 5)
         return false;

      if(trend == TREND_BULLISH)
         return FindBullishOB(rates, copied, retracementBar, lastBOS, ob);
      else if(trend == TREND_BEARISH)
         return FindBearishOB(rates, copied, retracementBar, lastBOS, ob);

      return false;
   }

   //--- Check if an order block has been mitigated (invalidated)
   bool IsMitigated(const string symbol, ENUM_TIMEFRAMES tf, const OrderBlock &ob)
   {
      MqlRates rates[];
      int copied = m_data.GetRates(symbol, tf, 0, ob.barIndex, rates);
      if(copied <= 0) return false;

      // Check all bars since OB formation
      for(int i = ob.barIndex - 1; i >= 0; i--)
      {
         if(i >= copied) continue;

         if(ob.type == OB_BULLISH)
         {
            // Bullish OB mitigated when price closes below OB low
            if(rates[i].close < ob.lowPrice)
               return true;
         }
         else if(ob.type == OB_BEARISH)
         {
            // Bearish OB mitigated when price closes above OB high
            if(rates[i].close > ob.highPrice)
               return true;
         }
      }
      return false;
   }

private:
   //--- Find bullish order block (last bearish candle before bullish impulse)
   bool FindBullishOB(const MqlRates &rates[], int barCount,
                       int retracementBar, const BOSEvent &lastBOS,
                       OrderBlock &ob)
   {
      // Search backwards from the retracement area for the last bearish candle
      // before the bullish impulse that led to the BOS
      int searchStart = retracementBar;
      int searchEnd   = MathMin(retracementBar + 10, barCount - 1);

      for(int i = searchStart; i <= searchEnd; i++)
      {
         // Bearish candle: close < open
         if(rates[i].close < rates[i].open)
         {
            // Verify an impulse move followed (next bars should be bullish)
            bool impulseConfirmed = false;
            if(i > 0)
            {
               double moveAfter = 0;
               int barsChecked = 0;
               for(int j = i - 1; j >= MathMax(0, i - 5); j--)
               {
                  moveAfter += (rates[j].close - rates[j].open);
                  barsChecked++;
               }
               // Impulse = net positive move with good magnitude
               if(barsChecked > 0 && moveAfter > 0)
                  impulseConfirmed = true;
            }

            if(impulseConfirmed || i == searchStart)
            {
               ob.type          = OB_BULLISH;
               ob.highPrice     = rates[i].high;
               ob.lowPrice      = rates[i].low;
               ob.midPrice      = (ob.highPrice + ob.lowPrice) / 2.0;
               ob.formationTime = rates[i].time;
               ob.barIndex      = i;
               ob.isMitigated   = false;

               // Check mitigation: has price closed below OB since formation?
               for(int k = i - 1; k >= 0; k--)
               {
                  if(rates[k].close < ob.lowPrice)
                  {
                     ob.isMitigated = true;
                     break;
                  }
               }

               if(!ob.isMitigated)
                  return true;
            }
         }
      }
      return false;
   }

   //--- Find bearish order block (last bullish candle before bearish impulse)
   bool FindBearishOB(const MqlRates &rates[], int barCount,
                       int retracementBar, const BOSEvent &lastBOS,
                       OrderBlock &ob)
   {
      int searchStart = retracementBar;
      int searchEnd   = MathMin(retracementBar + 10, barCount - 1);

      for(int i = searchStart; i <= searchEnd; i++)
      {
         // Bullish candle: close > open
         if(rates[i].close > rates[i].open)
         {
            bool impulseConfirmed = false;
            if(i > 0)
            {
               double moveAfter = 0;
               int barsChecked = 0;
               for(int j = i - 1; j >= MathMax(0, i - 5); j--)
               {
                  moveAfter += (rates[j].close - rates[j].open);
                  barsChecked++;
               }
               // Impulse = net negative move
               if(barsChecked > 0 && moveAfter < 0)
                  impulseConfirmed = true;
            }

            if(impulseConfirmed || i == searchStart)
            {
               ob.type          = OB_BEARISH;
               ob.highPrice     = rates[i].high;
               ob.lowPrice      = rates[i].low;
               ob.midPrice      = (ob.highPrice + ob.lowPrice) / 2.0;
               ob.formationTime = rates[i].time;
               ob.barIndex      = i;
               ob.isMitigated   = false;

               for(int k = i - 1; k >= 0; k--)
               {
                  if(rates[k].close > ob.highPrice)
                  {
                     ob.isMitigated = true;
                     break;
                  }
               }

               if(!ob.isMitigated)
                  return true;
            }
         }
      }
      return false;
   }
};

#endif
