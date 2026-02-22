//+------------------------------------------------------------------+
//|                                              TradeExecutor.mqh    |
//|                          Confluence Trading System                 |
//|                          Market execution at OB zones             |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_TRADEEXECUTOR_MQH
#define CONFLUENCE_TRADEEXECUTOR_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "RiskManager.mqh"
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Trade Executor                                                    |
//| Monitors OB zones and executes market orders when price arrives. |
//| No pending limit orders — real-time execution with final checks. |
//+------------------------------------------------------------------+
class CTradeExecutor
{
private:
   CTrade            m_trade;
   CRiskManager*     m_riskMgr;
   CLogger           m_log;

public:
   CTradeExecutor() : m_riskMgr(NULL) { m_log.SetPrefix("Executor"); }

   void Init(CRiskManager *riskMgr, int magicNumber)
   {
      m_riskMgr = riskMgr;
      m_trade.SetExpertMagicNumber(magicNumber);
      m_trade.SetDeviationInPoints(20); // 2 pips slippage tolerance
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   }

   //--- Prepare a watched zone (no broker order, just internal tracking)
   bool PrepareZone(const ScoreCard &card, PendingSetup &setup)
   {
      setup.Reset();

      if(card.direction == TRADE_NONE || card.entryPrice <= 0)
         return false;

      // Calculate lot size
      double lots = m_riskMgr.CalculateLotSize(card.symbol, card.entryPrice, card.stopLoss);
      if(lots <= 0)
      {
         m_log.Warning(StringFormat("%s: lot size calculated as 0", card.symbol));
         return false;
      }

      setup.symbol             = card.symbol;
      setup.direction          = card.direction;
      setup.entryPrice         = NormalizeToTick(card.symbol, card.entryPrice);
      setup.obHighPrice        = card.activeOB.highPrice;
      setup.obLowPrice         = card.activeOB.lowPrice;
      setup.stopLoss           = NormalizeToTick(card.symbol, card.stopLoss);
      setup.takeProfit         = NormalizeToTick(card.symbol, card.takeProfit1);
      setup.lotSize            = lots;
      setup.scoreAtPlacement   = card.totalScore;
      setup.qualityAtPlacement = card.qualityLevel;
      setup.placedTime         = TimeCurrent();
      setup.candlesSincePlaced = 0;
      setup.maxCandles         = InpOrderExpiryCandles;
      setup.isActive           = true;

      m_log.Info(StringFormat("Zone stored: %s %s %.2f lots | OB=[%.5f-%.5f] SL=%.5f TP=%.5f [Score:%d %s]",
                 card.symbol, DirectionToString(card.direction),
                 lots, setup.obLowPrice, setup.obHighPrice,
                 setup.stopLoss, setup.takeProfit,
                 card.totalScore, QualityToString(card.qualityLevel)));

      return true;
   }

   //--- Check if price has entered the OB zone
   bool IsPriceInZone(const PendingSetup &setup)
   {
      if(!setup.isActive) return false;

      double bid = SymbolInfoDouble(setup.symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(setup.symbol, SYMBOL_ASK);

      if(bid <= 0 || ask <= 0) return false;

      if(setup.direction == TRADE_LONG)
      {
         // For longs: price must drop INTO or BELOW the OB zone top
         return (ask <= setup.obHighPrice);
      }
      else
      {
         // For shorts: price must rise INTO or ABOVE the OB zone bottom
         return (bid >= setup.obLowPrice);
      }
   }

   //--- Execute market order immediately (called when price is in zone)
   bool ExecuteMarketOrder(const PendingSetup &setup, ManagedPosition &pos)
   {
      pos.Reset();

      double sl = setup.stopLoss;
      double tp = setup.takeProfit;

      string comment = StringFormat("CTS|%s|S%d",
         QualityToString(setup.qualityAtPlacement), setup.scoreAtPlacement);

      bool result = false;

      if(setup.direction == TRADE_LONG)
         result = m_trade.Buy(setup.lotSize, setup.symbol, 0, sl, tp, comment);
      else
         result = m_trade.Sell(setup.lotSize, setup.symbol, 0, sl, tp, comment);

      if(result)
      {
         ulong dealTicket = m_trade.ResultDeal();
         double fillPrice = m_trade.ResultPrice();

         // Get position ticket from the deal
         if(dealTicket > 0)
         {
            HistorySelect(0, TimeCurrent());
            if(HistoryDealSelect(dealTicket))
               pos.ticket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         }

         // Fallback: find position by symbol + magic
         if(pos.ticket == 0)
         {
            int total = PositionsTotal();
            for(int i = total - 1; i >= 0; i--)
            {
               ulong ticket = PositionGetTicket(i);
               if(ticket == 0) continue;
               if(PositionSelectByTicket(ticket) &&
                  PositionGetString(POSITION_SYMBOL) == setup.symbol &&
                  PositionGetInteger(POSITION_MAGIC) == m_trade.RequestMagic())
               {
                  pos.ticket = ticket;
                  break;
               }
            }
         }

         pos.symbol         = setup.symbol;
         pos.direction      = setup.direction;
         pos.entryPrice     = (fillPrice > 0) ? fillPrice : SymbolInfoDouble(setup.symbol,
                              setup.direction == TRADE_LONG ? SYMBOL_ASK : SYMBOL_BID);
         pos.originalVolume = setup.lotSize;
         pos.currentVolume  = setup.lotSize;
         pos.entryTime      = TimeCurrent();

         m_log.Info(StringFormat("MARKET ORDER FILLED: %s %s %.2f lots @ %.5f SL=%.5f TP=%.5f [Score:%d]",
                    setup.symbol, DirectionToString(setup.direction),
                    setup.lotSize, pos.entryPrice, sl, tp, setup.scoreAtPlacement));
      }
      else
      {
         m_log.Error(StringFormat("Market order FAILED for %s: %d - %s",
                     setup.symbol, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
      }

      return result;
   }
};

#endif
