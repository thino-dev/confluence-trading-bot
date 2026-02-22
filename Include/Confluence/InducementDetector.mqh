//+------------------------------------------------------------------+
//|                                          InducementDetector.mqh   |
//|                          Confluence Trading System                 |
//|                          False break / inducement detection       |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_INDUCEMENTDETECTOR_MQH
#define CONFLUENCE_INDUCEMENTDETECTOR_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"

//+------------------------------------------------------------------+
//| Inducement Detector                                               |
//| Inducement = a deliberate false signal that traps retail traders  |
//| before the real move. In an uptrend: brief dip below minor swing |
//| low triggers retail shorts, then price continues up.             |
//+------------------------------------------------------------------+
class CInducementDetector
{
private:
   CMarketData*      m_data;
   CLogger           m_log;

public:
   CInducementDetector() : m_data(NULL) { m_log.SetPrefix("IDM"); }

   void Init(CMarketData *data) { m_data = data; }

   //--- Detect inducement near the OB zone
   bool DetectInducement(const string symbol, ENUM_TIMEFRAMES tf,
                          const OrderBlock &ob,
                          ENUM_TRADE_DIRECTION direction,
                          const SwingPoint &swingHighs[], int highCount,
                          const SwingPoint &swingLows[], int lowCount)
   {
      MqlRates rates[];
      int copied = m_data.GetRates(symbol, tf, 0, 30, rates);
      if(copied < 10) return false;

      double tolerance = (ob.highPrice - ob.lowPrice) * 3.0;
      if(tolerance <= 0) return false;

      if(direction == TRADE_LONG)
      {
         // In uptrend: look for a brief break below a MINOR swing low
         // followed by immediate recovery above it
         // This must happen near the OB zone
         return DetectBullishInducement(rates, copied, ob, swingLows, lowCount, tolerance);
      }
      else if(direction == TRADE_SHORT)
      {
         // In downtrend: brief break above a minor swing high
         // followed by recovery below
         return DetectBearishInducement(rates, copied, ob, swingHighs, highCount, tolerance);
      }

      return false;
   }

private:
   bool DetectBullishInducement(const MqlRates &rates[], int barCount,
                                 const OrderBlock &ob,
                                 const SwingPoint &lows[], int lowCount,
                                 double tolerance)
   {
      // Look in recent bars for a break below a minor swing low + recovery
      for(int i = 1; i < MathMin(15, barCount - 1); i++)
      {
         // Check proximity to OB zone
         if(MathAbs(rates[i].low - ob.midPrice) > tolerance) continue;

         // Look for minor swing lows that were briefly broken
         for(int j = 0; j < lowCount; j++)
         {
            double minorLow = lows[j].price;

            // Bar wicked below the minor low
            if(rates[i].low < minorLow)
            {
               // But closed above it (or very near it)
               if(rates[i].close > minorLow)
               {
                  // Next bar (more recent) continued higher
                  if(i > 0 && rates[i - 1].close > rates[i].close)
                     return true;
               }
            }
         }
      }
      return false;
   }

   bool DetectBearishInducement(const MqlRates &rates[], int barCount,
                                 const OrderBlock &ob,
                                 const SwingPoint &highs[], int highCount,
                                 double tolerance)
   {
      for(int i = 1; i < MathMin(15, barCount - 1); i++)
      {
         if(MathAbs(rates[i].high - ob.midPrice) > tolerance) continue;

         for(int j = 0; j < highCount; j++)
         {
            double minorHigh = highs[j].price;

            if(rates[i].high > minorHigh)
            {
               if(rates[i].close < minorHigh)
               {
                  if(i > 0 && rates[i - 1].close < rates[i].close)
                     return true;
               }
            }
         }
      }
      return false;
   }
};

#endif
