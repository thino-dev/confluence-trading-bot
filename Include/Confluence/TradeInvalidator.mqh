//+------------------------------------------------------------------+
//|                                           TradeInvalidator.mqh    |
//|                          Confluence Trading System                 |
//|                          Instant-kill checks (5 invalidators)    |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_TRADEINVALIDATOR_MQH
#define CONFLUENCE_TRADEINVALIDATOR_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "NewsFilter.mqh"

//+------------------------------------------------------------------+
//| Trade Invalidator                                                 |
//| Any single invalidator = trade is dead, regardless of score.     |
//| 1) HTF trend opposite to trade direction                        |
//| 2) Fewer than 3 consecutive BOS                                 |
//| 3) RR below 1:1.5 (spread-adjusted)                             |
//| 4) OB in wrong premium/discount zone                             |
//| 5) Major news within 4 hours                                    |
//+------------------------------------------------------------------+
class CTradeInvalidator
{
private:
   CNewsFilter*      m_newsFilter;
   CLogger           m_log;

public:
   CTradeInvalidator() : m_newsFilter(NULL) { m_log.SetPrefix("Invalidator"); }

   void Init(CNewsFilter *news) { m_newsFilter = news; }

   //--- Run all invalidation checks. Returns true if trade is KILLED.
   bool Check(ScoreCard &card)
   {
      card.hasInvalidator = false;

      // 1. HTF trend vs trade direction
      card.wrongHTFDirection = false;
      if(card.direction == TRADE_LONG && card.htfTrend != TREND_BULLISH)
         card.wrongHTFDirection = true;
      if(card.direction == TRADE_SHORT && card.htfTrend != TREND_BEARISH)
         card.wrongHTFDirection = true;

      // 2. Insufficient BOS
      card.insufficientBOS = (card.bosCount < InpMinBOSCount);

      // 3. RR below minimum (spread-adjusted)
      card.rrBelowMinimum = (card.rrSpreadAdjusted < InpMinRR);

      // 4. OB in wrong zone
      card.wrongZone = !card.obInCorrectZone;

      // 5. News within buffer window
      card.newsWithin4Hours = false;
      if(m_newsFilter != NULL)
         card.newsWithin4Hours = m_newsFilter.IsNewsUpcoming(card.symbol);

      // Any single invalidator kills the trade
      card.hasInvalidator = (card.wrongHTFDirection ||
                              card.insufficientBOS ||
                              card.rrBelowMinimum ||
                              card.wrongZone ||
                              card.newsWithin4Hours);

      if(card.hasInvalidator)
      {
         card.totalScore = 0;
         card.qualityLevel = QUALITY_REJECT;
      }

      return card.hasInvalidator;
   }
};

#endif
