//+------------------------------------------------------------------+
//|                                                ZoneAnalysis.mqh   |
//|                          Confluence Trading System                 |
//|                          Premium/Discount + Fibonacci Analysis    |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_ZONEANALYSIS_MQH
#define CONFLUENCE_ZONEANALYSIS_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Utilities.mqh"
#include "SwingDetector.mqh"

//+------------------------------------------------------------------+
//| Zone Analysis                                                     |
//| Classifies OB into premium/discount zones.                       |
//| Checks Fibonacci golden pocket (61.8%-78.6%).                    |
//+------------------------------------------------------------------+
class CZoneAnalysis
{
private:
   CLogger           m_log;

public:
   CZoneAnalysis() { m_log.SetPrefix("Zone"); }

   //--- Classify an OB as premium, discount, or equilibrium
   ENUM_ZONE_TYPE ClassifyOBZone(const OrderBlock &ob,
                                  double rangeHigh, double rangeLow)
   {
      if(rangeHigh <= rangeLow)
         return ZONE_EQUILIBRIUM;

      double midpoint = (rangeHigh + rangeLow) / 2.0;

      if(ob.midPrice < midpoint)
         return ZONE_DISCOUNT;
      else if(ob.midPrice > midpoint)
         return ZONE_PREMIUM;

      return ZONE_EQUILIBRIUM;
   }

   //--- Check if OB is in the correct zone for the trade direction
   bool IsOBInCorrectZone(const OrderBlock &ob, ENUM_TRADE_DIRECTION direction,
                           double rangeHigh, double rangeLow)
   {
      ENUM_ZONE_TYPE zone = ClassifyOBZone(ob, rangeHigh, rangeLow);

      if(direction == TRADE_LONG && zone == ZONE_DISCOUNT)
         return true;
      if(direction == TRADE_SHORT && zone == ZONE_PREMIUM)
         return true;

      return false;
   }

   //--- Check if OB falls inside the Fibonacci golden pocket (61.8%-78.6%)
   bool IsInGoldenPocket(const OrderBlock &ob, ENUM_TRADE_DIRECTION direction,
                          double swingHigh, double swingLow)
   {
      if(swingHigh <= swingLow)
         return false;

      double range = swingHigh - swingLow;

      if(direction == TRADE_LONG)
      {
         // Golden pocket for longs: 61.8% to 78.6% retracement from high
         double fib618 = swingHigh - range * 0.618;
         double fib786 = swingHigh - range * 0.786;

         // OB should overlap with the golden pocket zone
         double overlapHigh = MathMin(ob.highPrice, fib618);
         double overlapLow  = MathMax(ob.lowPrice, fib786);

         return (overlapHigh > overlapLow);
      }
      else if(direction == TRADE_SHORT)
      {
         // Golden pocket for shorts: 61.8% to 78.6% retracement from low
         double fib618 = swingLow + range * 0.618;
         double fib786 = swingLow + range * 0.786;

         double overlapHigh = MathMin(ob.highPrice, fib786);
         double overlapLow  = MathMax(ob.lowPrice, fib618);

         return (overlapHigh > overlapLow);
      }

      return false;
   }

   //--- Calculate Fibonacci levels for a swing range
   void CalculateFibLevels(double swingHigh, double swingLow,
                            ENUM_TRADE_DIRECTION direction,
                            double &fib382, double &fib500,
                            double &fib618, double &fib786)
   {
      double range = swingHigh - swingLow;

      if(direction == TRADE_LONG)
      {
         // Retracement from high to low
         fib382 = swingHigh - range * 0.382;
         fib500 = swingHigh - range * 0.500;
         fib618 = swingHigh - range * 0.618;
         fib786 = swingHigh - range * 0.786;
      }
      else
      {
         // Retracement from low to high
         fib382 = swingLow + range * 0.382;
         fib500 = swingLow + range * 0.500;
         fib618 = swingLow + range * 0.618;
         fib786 = swingLow + range * 0.786;
      }
   }

   //--- Calculate spread-adjusted risk:reward ratio
   double CalculateRR(const string symbol, double entry, double sl, double tp,
                       ENUM_TRADE_DIRECTION direction)
   {
      double spread = GetSpreadAsPrice(symbol);

      double risk, reward;

      if(direction == TRADE_LONG)
      {
         double adjustedEntry = entry + spread; // Buying at ask
         risk   = adjustedEntry - sl;
         reward = tp - adjustedEntry;
      }
      else
      {
         double adjustedEntry = entry; // Selling at bid
         risk   = sl - adjustedEntry;
         reward = adjustedEntry - tp - spread;
      }

      if(risk <= 0) return 0;
      return reward / risk;
   }

   //--- Calculate entry, SL, TP from the order block
   //    housingSwing = the swing low (for longs) or swing high (for shorts)
   //    that contains the OB. SL goes beyond this swing, not the OB edge.
   void CalculateTradeParams(const OrderBlock &ob,
                              ENUM_TRADE_DIRECTION direction,
                              const SwingPoint &targetSwing,
                              const SwingPoint &housingSwing,
                              double &entry, double &sl, double &tp,
                              const string symbol = "")
   {
      // Small buffer beyond housing swing: 2x spread or 10% of OB height
      double obHeight = MathAbs(ob.highPrice - ob.lowPrice);
      double spreadBuf = (symbol != "") ? GetSpreadAsPrice(symbol) * 2.0 : obHeight * 0.10;
      double buffer   = MathMax(obHeight * 0.10, spreadBuf);

      if(direction == TRADE_LONG)
      {
         entry = ob.highPrice;              // Entry at top of OB
         sl    = housingSwing.price - buffer; // SL below the swing low housing the OB
         tp    = targetSwing.price;         // Previous swing high
      }
      else
      {
         entry = ob.lowPrice;              // Entry at bottom of OB
         sl    = housingSwing.price + buffer; // SL above the swing high housing the OB
         tp    = targetSwing.price;        // Previous swing low
      }
   }
};

#endif
