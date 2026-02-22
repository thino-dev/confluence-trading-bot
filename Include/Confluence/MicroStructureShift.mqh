//+------------------------------------------------------------------+
//|                                          MicroStructureShift.mqh  |
//|                          Confluence Trading System                 |
//|                          5M/15M MSS at OB zone for precision     |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_MICROSTRUCTURESHIFT_MQH
#define CONFLUENCE_MICROSTRUCTURESHIFT_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"
#include "SwingDetector.mqh"

//+------------------------------------------------------------------+
//| Micro Market Structure Shift Detector                             |
//| When price reaches the OB zone, drop to 5M/15M and look for a  |
//| CHoCH in the trade direction. This is the highest-precision      |
//| confirmation that smart money is absorbing at this level.        |
//+------------------------------------------------------------------+
class CMicroStructureShift
{
private:
   CMarketData*      m_data;
   CSwingDetector*   m_swingDetector;
   CLogger           m_log;

public:
   CMicroStructureShift() : m_data(NULL), m_swingDetector(NULL)
   { m_log.SetPrefix("MicroMSS"); }

   void Init(CMarketData *data, CSwingDetector *swing)
   {
      m_data = data;
      m_swingDetector = swing;
   }

   //--- Check for micro MSS at the OB zone
   //    Price must be currently near the OB zone, and a micro CHoCH
   //    in the trade direction must have occurred on 5M or 15M.
   bool DetectMSSAtOB(const string symbol, const OrderBlock &ob,
                       ENUM_TRADE_DIRECTION direction)
   {
      // First, check if current price is near the OB zone
      double bid = m_data.GetBid(symbol);
      double tolerance = (ob.highPrice - ob.lowPrice) * 1.5;

      bool nearOB = (bid >= ob.lowPrice - tolerance && bid <= ob.highPrice + tolerance);
      if(!nearOB)
         return false;

      // Check both micro timeframes
      ENUM_TIMEFRAMES microTFs[2];
      microTFs[0] = InpMicroTF1;
      microTFs[1] = InpMicroTF2;

      for(int t = 0; t < 2; t++)
      {
         if(CheckMSSOnTimeframe(symbol, microTFs[t], ob, direction))
            return true;
      }

      return false;
   }

private:
   bool CheckMSSOnTimeframe(const string symbol, ENUM_TIMEFRAMES tf,
                              const OrderBlock &ob,
                              ENUM_TRADE_DIRECTION direction)
   {
      // Detect micro swings with tighter parameters
      SwingPoint microHighs[], microLows[];
      int highCount = 0, lowCount = 0;

      if(!m_swingDetector.DetectSwings(symbol, tf, 50, 2, 2,
         microHighs, highCount, microLows, lowCount))
         return false;

      if(direction == TRADE_LONG)
      {
         // Bullish MSS: on micro TF, a higher high breaks above a previous
         // swing high while price is at the OB zone.
         // This is a CHoCH from bearish to bullish on micro level.
         if(highCount >= 2)
         {
            // Most recent swing high breaks above the previous one
            if(microHighs[0].price > microHighs[1].price)
            {
               // Confirm this happened near/at the OB zone
               // The swing low between these highs should be near OB
               for(int i = 0; i < lowCount; i++)
               {
                  if(microLows[i].time > microHighs[1].time &&
                     microLows[i].time < microHighs[0].time)
                  {
                     // This swing low formed while price was at OB
                     if(microLows[i].price >= ob.lowPrice - (ob.highPrice - ob.lowPrice) &&
                        microLows[i].price <= ob.highPrice + (ob.highPrice - ob.lowPrice))
                     {
                        return true;
                     }
                  }
               }

               // Fallback: just check if the micro structure shift
               // happened recently and price is near OB
               if(microHighs[0].time > TimeCurrent() - PeriodSeconds(tf) * 10)
                  return true;
            }
         }
      }
      else if(direction == TRADE_SHORT)
      {
         // Bearish MSS: lower low breaks below previous swing low
         if(lowCount >= 2)
         {
            if(microLows[0].price < microLows[1].price)
            {
               for(int i = 0; i < highCount; i++)
               {
                  if(microHighs[i].time > microLows[1].time &&
                     microHighs[i].time < microLows[0].time)
                  {
                     if(microHighs[i].price >= ob.lowPrice - (ob.highPrice - ob.lowPrice) &&
                        microHighs[i].price <= ob.highPrice + (ob.highPrice - ob.lowPrice))
                     {
                        return true;
                     }
                  }
               }

               if(microLows[0].time > TimeCurrent() - PeriodSeconds(tf) * 10)
                  return true;
            }
         }
      }

      return false;
   }
};

#endif
