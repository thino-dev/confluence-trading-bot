//+------------------------------------------------------------------+
//|                                              LiquiditySweep.mqh   |
//|                          Confluence Trading System                 |
//|                          Institutional liquidity sweep detection  |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_LIQUIDITYSWEEP_MQH
#define CONFLUENCE_LIQUIDITYSWEEP_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"

//+------------------------------------------------------------------+
//| Liquidity Sweep Detector                                          |
//| Detects when price wicks beyond a key swing level then reverses. |
//| A sweep at the OB zone = strong institutional footprint.         |
//+------------------------------------------------------------------+
class CLiquiditySweep
{
private:
   CMarketData*      m_data;
   CLogger           m_log;

public:
   CLiquiditySweep() : m_data(NULL) { m_log.SetPrefix("LiqSweep"); }

   void Init(CMarketData *data) { m_data = data; }

   //--- Detect liquidity sweep near the OB zone
   //    For LONG: sell-side sweep (wick below key low, close above)
   //    For SHORT: buy-side sweep (wick above key high, close below)
   bool DetectSweepAtOB(const string symbol, ENUM_TIMEFRAMES tf,
                         const OrderBlock &ob,
                         ENUM_TRADE_DIRECTION direction,
                         const SwingPoint &swingHighs[], int highCount,
                         const SwingPoint &swingLows[], int lowCount,
                         LiquiditySweep &sweep)
   {
      sweep.Reset();

      MqlRates rates[];
      int copied = m_data.GetRates(symbol, tf, 0, 20, rates);
      if(copied < 5) return false;

      // Define OB proximity tolerance (within 1 ATR of OB zone)
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tolerance = (ob.highPrice - ob.lowPrice) * 2.0;
      if(tolerance <= 0) tolerance = 50 * point;

      // Check recent bars (last 10) for sweep pattern
      for(int i = 0; i < MathMin(10, copied); i++)
      {
         if(direction == TRADE_LONG)
         {
            // Sell-side liquidity sweep: wick below key swing low, close above
            for(int j = 0; j < lowCount; j++)
            {
               double keyLevel = swingLows[j].price;

               // Bar wicked below the key level
               if(rates[i].low < keyLevel && rates[i].close > keyLevel)
               {
                  // Check proximity to OB zone
                  if(MathAbs(rates[i].low - ob.lowPrice) <= tolerance ||
                     (rates[i].low >= ob.lowPrice && rates[i].low <= ob.highPrice))
                  {
                     sweep.sweptLevel     = keyLevel;
                     sweep.wickExtreme    = rates[i].low;
                     sweep.time           = rates[i].time;
                     sweep.barIndex       = i;
                     sweep.isBuySideSweep = false; // Sell stops were swept
                     return true;
                  }
               }
            }
         }
         else if(direction == TRADE_SHORT)
         {
            // Buy-side liquidity sweep: wick above key swing high, close below
            for(int j = 0; j < highCount; j++)
            {
               double keyLevel = swingHighs[j].price;

               if(rates[i].high > keyLevel && rates[i].close < keyLevel)
               {
                  if(MathAbs(rates[i].high - ob.highPrice) <= tolerance ||
                     (rates[i].high >= ob.lowPrice && rates[i].high <= ob.highPrice))
                  {
                     sweep.sweptLevel     = keyLevel;
                     sweep.wickExtreme    = rates[i].high;
                     sweep.time           = rates[i].time;
                     sweep.barIndex       = i;
                     sweep.isBuySideSweep = true; // Buy stops were swept
                     return true;
                  }
               }
            }
         }
      }

      return false;
   }
};

#endif
