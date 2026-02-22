//+------------------------------------------------------------------+
//|                                           PreviousDayLevels.mqh   |
//|                          Confluence Trading System                 |
//|                          PDH/PDL (Previous Day High/Low)         |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_PREVIOUSDAYLEVELS_MQH
#define CONFLUENCE_PREVIOUSDAYLEVELS_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"

//+------------------------------------------------------------------+
//| Previous Day Levels                                               |
//| PDH/PDL are the most consistently respected key levels.          |
//| Market makers and algorithms reference them heavily.             |
//+------------------------------------------------------------------+
class CPreviousDayLevels
{
private:
   CMarketData*      m_data;
   CLogger           m_log;

public:
   CPreviousDayLevels() : m_data(NULL) { m_log.SetPrefix("PDL"); }

   void Init(CMarketData *data) { m_data = data; }

   //--- Get previous day's high and low
   bool GetPDHPDL(const string symbol, double &pdh, double &pdl)
   {
      // iHigh/iLow with shift 1 = previous completed daily bar
      pdh = iHigh(symbol, PERIOD_D1, 1);
      pdl = iLow(symbol, PERIOD_D1, 1);

      return (pdh > 0 && pdl > 0 && pdh > pdl);
   }

   //--- Check if OB zone aligns with PDH or PDL
   bool CheckPDHPDLAlignment(const string symbol, const OrderBlock &ob,
                              ENUM_TRADE_DIRECTION direction)
   {
      double pdh = 0, pdl = 0;
      if(!GetPDHPDL(symbol, pdh, pdl))
         return false;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      // Tolerance: OB zone within 30 pips of PDH/PDL
      double tolerance = 30 * point * 10; // Convert to price for 5-digit brokers

      if(direction == TRADE_LONG)
      {
         // Long setup: OB near PDL (support)
         if(MathAbs(ob.midPrice - pdl) <= tolerance ||
            (pdl >= ob.lowPrice && pdl <= ob.highPrice))
            return true;
      }
      else if(direction == TRADE_SHORT)
      {
         // Short setup: OB near PDH (resistance)
         if(MathAbs(ob.midPrice - pdh) <= tolerance ||
            (pdh >= ob.lowPrice && pdh <= ob.highPrice))
            return true;
      }

      return false;
   }
};

#endif
