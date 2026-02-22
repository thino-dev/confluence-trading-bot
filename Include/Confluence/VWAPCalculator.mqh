//+------------------------------------------------------------------+
//|                                              VWAPCalculator.mqh   |
//|                          Confluence Trading System                 |
//|                          Daily/Weekly VWAP from tick volume       |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_VWAPCALCULATOR_MQH
#define CONFLUENCE_VWAPCALCULATOR_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"

//+------------------------------------------------------------------+
//| VWAP Calculator                                                   |
//| Manually calculates VWAP from M1 tick volume data.               |
//| No external indicator needed — $0 cost.                          |
//| VWAP = Sum(typical_price * volume) / Sum(volume)                 |
//+------------------------------------------------------------------+
class CVWAPCalculator
{
private:
   CMarketData*      m_data;
   CLogger           m_log;

public:
   CVWAPCalculator() : m_data(NULL) { m_log.SetPrefix("VWAP"); }

   void Init(CMarketData *data) { m_data = data; }

   //--- Calculate daily VWAP
   double CalculateDailyVWAP(const string symbol)
   {
      datetime dayStart = StartOfDay(TimeCurrent());
      return CalculateVWAP(symbol, dayStart);
   }

   //--- Calculate weekly VWAP
   double CalculateWeeklyVWAP(const string symbol)
   {
      datetime weekStart = StartOfWeek(TimeCurrent());
      return CalculateVWAP(symbol, weekStart);
   }

   //--- Check if price is retesting VWAP (near VWAP within tolerance)
   bool IsRetestingVWAP(const string symbol, const OrderBlock &ob)
   {
      double dailyVWAP  = CalculateDailyVWAP(symbol);
      double weeklyVWAP = CalculateWeeklyVWAP(symbol);

      if(dailyVWAP <= 0 && weeklyVWAP <= 0) return false;

      double obMid = ob.midPrice;
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

      // Tolerance: OB zone encompasses VWAP, or VWAP is within 0.3% of OB mid
      double tolerance = obMid * 0.003;
      if(tolerance < 30 * point) tolerance = 30 * point;

      // Check daily VWAP
      if(dailyVWAP > 0)
      {
         if(MathAbs(dailyVWAP - obMid) <= tolerance ||
            (dailyVWAP >= ob.lowPrice && dailyVWAP <= ob.highPrice))
            return true;
      }

      // Check weekly VWAP
      if(weeklyVWAP > 0)
      {
         if(MathAbs(weeklyVWAP - obMid) <= tolerance ||
            (weeklyVWAP >= ob.lowPrice && weeklyVWAP <= ob.highPrice))
            return true;
      }

      return false;
   }

private:
   //--- Core VWAP calculation from session start
   double CalculateVWAP(const string symbol, datetime sessionStart)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      // Copy M1 bars from session start to now
      int copied = CopyRates(symbol, PERIOD_M1, sessionStart, TimeCurrent(), rates);
      if(copied <= 0) return 0;

      double cumulativeTPV = 0; // Sum of (typical_price * volume)
      double cumulativeVol = 0; // Sum of volume

      for(int i = copied - 1; i >= 0; i--)
      {
         double typicalPrice = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
         double vol = (double)rates[i].tick_volume;

         cumulativeTPV += typicalPrice * vol;
         cumulativeVol += vol;
      }

      if(cumulativeVol <= 0) return 0;
      return cumulativeTPV / cumulativeVol;
   }
};

#endif
