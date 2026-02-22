//+------------------------------------------------------------------+
//|                                    LinearRegressionChannel.mqh    |
//|                          Confluence Trading System                 |
//|                          LRC: replaces trendline confirmation     |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_LINEARREGRESSIONCHANNEL_MQH
#define CONFLUENCE_LINEARREGRESSIONCHANNEL_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"

//+------------------------------------------------------------------+
//| Linear Regression Channel                                         |
//| Replaces trendline detection (which is unreliable to automate).  |
//| Uses least-squares regression + standard deviation bands.        |
//| Price at lower band in uptrend (or upper in downtrend) = +1.    |
//+------------------------------------------------------------------+
class CLinearRegressionChannel
{
private:
   CMarketData*      m_data;
   CLogger           m_log;

public:
   CLinearRegressionChannel() : m_data(NULL) { m_log.SetPrefix("LRC"); }

   void Init(CMarketData *data) { m_data = data; }

   //--- Check if price is at the channel boundary in favor of trade direction
   bool CheckLRCConfluence(const string symbol, ENUM_TIMEFRAMES tf,
                            ENUM_TRADE_DIRECTION direction)
   {
      double regValue, upperBand, lowerBand, slope;
      if(!Calculate(symbol, tf, InpLRCPeriod, regValue, upperBand, lowerBand, slope))
         return false;

      double bid = m_data.GetBid(symbol);
      double bandWidth = upperBand - lowerBand;
      if(bandWidth <= 0) return false;

      // How close is price to the band? Within 20% of band width from the edge
      double edgeThreshold = bandWidth * 0.20;

      if(direction == TRADE_LONG)
      {
         // Price at or below lower band in an upward-sloping channel
         return (slope > 0 && bid <= lowerBand + edgeThreshold);
      }
      else if(direction == TRADE_SHORT)
      {
         // Price at or above upper band in a downward-sloping channel
         return (slope < 0 && bid >= upperBand - edgeThreshold);
      }

      return false;
   }

   //--- Full calculation returning all values
   bool Calculate(const string symbol, ENUM_TIMEFRAMES tf, int period,
                   double &regValue, double &upperBand, double &lowerBand,
                   double &slope)
   {
      double closes[];
      int copied = m_data.GetClose(symbol, tf, 0, period, closes);
      if(copied < period) return false;

      // Least-squares linear regression: y = a + b*x
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      int n = period;

      // closes[0] = current bar, closes[period-1] = oldest
      // Map: x=0 for oldest, x=n-1 for current
      for(int i = 0; i < n; i++)
      {
         double x = (double)(n - 1 - i); // oldest=0, newest=n-1
         double y = closes[i];
         sumX  += x;
         sumY  += y;
         sumXY += x * y;
         sumX2 += x * x;
      }

      double denom = n * sumX2 - sumX * sumX;
      if(MathAbs(denom) < 1e-10) return false;

      double b = (n * sumXY - sumX * sumY) / denom;
      double a = (sumY - b * sumX) / n;

      // Slope (positive = uptrend)
      slope = b;

      // Current regression value (at x = n-1)
      regValue = a + b * (n - 1);

      // Standard deviation of residuals
      double sumResidualSq = 0;
      for(int i = 0; i < n; i++)
      {
         double x = (double)(n - 1 - i);
         double predicted = a + b * x;
         double residual = closes[i] - predicted;
         sumResidualSq += residual * residual;
      }
      double stdDev = MathSqrt(sumResidualSq / n);

      // 2 standard deviation bands
      upperBand = regValue + 2.0 * stdDev;
      lowerBand = regValue - 2.0 * stdDev;

      return true;
   }
};

#endif
