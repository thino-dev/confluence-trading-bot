//+------------------------------------------------------------------+
//|                                              TradeManager.mqh     |
//|                          Confluence Trading System                 |
//|                          SL/TP mgmt, partial close, trailing     |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_TRADEMANAGER_MQH
#define CONFLUENCE_TRADEMANAGER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "MarketData.mqh"
#include "StructureAnalyzer.mqh"
#include "ATRAnalyzer.mqh"
#include "StreakManager.mqh"
#include "WinRateTracker.mqh"
#include "TradeJournal.mqh"
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Trade Manager                                                     |
//| Manages open positions: BE move, partial close, trailing, CHoCH. |
//| 1) CHoCH on execution TF = immediate full close                 |
//| 2) After 1:1 = SL to breakeven                                  |
//| 3) TP1 hit = close 50%, start trailing remainder                 |
//| 4) Trail using ATR multiplier. Never move SL against position.  |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   CTrade               m_trade;
   CMarketData*         m_data;
   CStructureAnalyzer*  m_structure;
   CATRAnalyzer*        m_atr;
   CStreakManager*      m_streak;
   CWinRateTracker*     m_winRate;
   CTradeJournal*       m_journal;
   CLogger              m_log;

public:
   CTradeManager() : m_data(NULL), m_structure(NULL), m_atr(NULL),
                      m_streak(NULL), m_winRate(NULL), m_journal(NULL)
   { m_log.SetPrefix("TradeMgr"); }

   void Init(CMarketData *data, CStructureAnalyzer *structure,
             CATRAnalyzer *atr, CStreakManager *streak,
             CWinRateTracker *winRate, CTradeJournal *journal,
             int magicNumber)
   {
      m_data = data;
      m_structure = structure;
      m_atr = atr;
      m_streak = streak;
      m_winRate = winRate;
      m_journal = journal;
      m_trade.SetExpertMagicNumber(magicNumber);
      m_trade.SetDeviationInPoints(20);
   }

   //--- Manage all open positions (called every tick)
   void ManageAllPositions(ManagedPosition &positions[], int &posCount)
   {
      for(int i = posCount - 1; i >= 0; i--)
      {
         // Verify position still exists
         if(!PositionSelectByTicket(positions[i].ticket))
         {
            // Position closed (by SL, TP, or externally)
            RecordClosedTrade(positions[i]);
            RemovePosition(positions, posCount, i);
            continue;
         }

         // Update current volume (may have changed from partial close)
         positions[i].currentVolume = PositionGetDouble(POSITION_VOLUME);

         ManageSinglePosition(positions[i]);

         // Re-check if position still exists after management
         if(!PositionSelectByTicket(positions[i].ticket))
         {
            RecordClosedTrade(positions[i]);
            RemovePosition(positions, posCount, i);
         }
      }
   }

   //--- Recover open positions after EA restart
   void RecoverOpenPositions(int magicNumber,
                              ManagedPosition &positions[], int &posCount)
   {
      posCount = 0;
      int total = PositionsTotal();

      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         if(PositionGetInteger(POSITION_MAGIC) != magicNumber)
            continue;

         if(posCount >= MAX_POSITIONS) break;

         ManagedPosition pos;
         pos.Reset();
         pos.ticket         = ticket;
         pos.symbol         = PositionGetString(POSITION_SYMBOL);
         pos.entryPrice     = PositionGetDouble(POSITION_PRICE_OPEN);
         pos.currentSL      = PositionGetDouble(POSITION_SL);
         pos.originalSL     = pos.currentSL;
         pos.takeProfit1    = PositionGetDouble(POSITION_TP);
         pos.currentVolume  = PositionGetDouble(POSITION_VOLUME);
         pos.originalVolume = pos.currentVolume;
         pos.entryTime      = (datetime)PositionGetInteger(POSITION_TIME);

         long posType = PositionGetInteger(POSITION_TYPE);
         pos.direction = (posType == POSITION_TYPE_BUY) ? TRADE_LONG : TRADE_SHORT;

         // Infer state from SL position
         pos.slMovedToBE = false;
         if(pos.direction == TRADE_LONG && pos.currentSL >= pos.entryPrice)
            pos.slMovedToBE = true;
         if(pos.direction == TRADE_SHORT && pos.currentSL > 0 && pos.currentSL <= pos.entryPrice)
            pos.slMovedToBE = true;

         pos.tp1Hit = false; // Conservative: assume not hit
         pos.lastCheckTime = TimeCurrent();

         positions[posCount] = pos;
         posCount++;

         m_log.Info(StringFormat("Recovered position: %s %s @ %.5f",
                    pos.symbol, DirectionToString(pos.direction), pos.entryPrice));
      }
   }

private:
   void ManageSinglePosition(ManagedPosition &pos)
   {
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

      // === CHECK 1: CHoCH on execution TF = immediate close ===
      if(m_structure != NULL &&
         TimeCurrent() - pos.lastCheckTime >= PeriodSeconds(InpExecutionTF) / 2)
      {
         if(m_structure.DetectCHoCHSince(pos.symbol, InpExecutionTF,
            pos.direction, pos.entryTime))
         {
            pos.exitReason = "CHoCH";
            m_trade.PositionClose(pos.ticket);
            m_log.Info(StringFormat("%s CLOSED: CHoCH on %s", pos.symbol,
                       EnumToString(InpExecutionTF)));
            return;
         }
         pos.lastCheckTime = TimeCurrent();
      }

      // === CHECK 2: Move SL to breakeven after 1:1 ===
      if(!pos.slMovedToBE)
      {
         double distanceToEntry = 0;
         double riskDistance = MathAbs(pos.entryPrice - pos.originalSL);

         if(pos.direction == TRADE_LONG)
            distanceToEntry = currentPrice - pos.entryPrice;
         else
            distanceToEntry = pos.entryPrice - currentPrice;

         if(distanceToEntry >= riskDistance * InpBreakevenTriggerRR)
         {
            double point = SymbolInfoDouble(pos.symbol, SYMBOL_POINT);
            double buffer = InpBEBufferPips * point * 10; // Convert pips to price

            double newSL;
            if(pos.direction == TRADE_LONG)
               newSL = pos.entryPrice + buffer;
            else
               newSL = pos.entryPrice - buffer;

            newSL = NormalizeToTick(pos.symbol, newSL);

            if(m_trade.PositionModify(pos.ticket, newSL, PositionGetDouble(POSITION_TP)))
            {
               pos.currentSL = newSL;
               pos.slMovedToBE = true;
               m_log.Info(StringFormat("%s SL moved to breakeven @ %.5f",
                          pos.symbol, newSL));
            }
         }
      }

      // === CHECK 3: Partial close at TP1 ===
      if(!pos.tp1Hit && pos.takeProfit1 > 0)
      {
         bool tp1Reached = false;

         if(pos.direction == TRADE_LONG)
            tp1Reached = (currentPrice >= pos.takeProfit1);
         else
            tp1Reached = (currentPrice <= pos.takeProfit1);

         if(tp1Reached)
         {
            double volumeToClose = NormalizeDouble(
               pos.originalVolume * InpPartialClosePct / 100.0,
               GetVolumePrecision(pos.symbol));

            double minLot = SymbolInfoDouble(pos.symbol, SYMBOL_VOLUME_MIN);
            double remaining = pos.currentVolume - volumeToClose;

            // If remainder would be below minimum, close everything
            if(remaining < minLot)
               volumeToClose = pos.currentVolume;

            if(volumeToClose > 0)
            {
               if(m_trade.PositionClosePartial(pos.ticket, volumeToClose))
               {
                  pos.tp1Hit = true;
                  pos.currentVolume -= volumeToClose;

                  // Remove TP so remainder can trail freely
                  m_trade.PositionModify(pos.ticket, pos.currentSL, 0);

                  m_log.Info(StringFormat("%s: %.0f%% closed at TP1 (%.5f). Trailing %.2f lots.",
                             pos.symbol, InpPartialClosePct,
                             pos.takeProfit1, pos.currentVolume));
               }
            }
         }
      }

      // === CHECK 4: Trail SL on remaining position ===
      if(pos.tp1Hit && pos.currentVolume > 0)
      {
         SymbolHandles handles;
         if(!m_data.GetHandles(pos.symbol, handles)) return;

         double atrValue = m_atr.GetCurrentATR(pos.symbol, handles);
         if(atrValue <= 0) return;

         double trailDistance = atrValue * InpTrailingATRMult;
         double newTrailSL;

         if(pos.direction == TRADE_LONG)
         {
            newTrailSL = currentPrice - trailDistance;
            newTrailSL = NormalizeToTick(pos.symbol, newTrailSL);

            // NEVER move SL against position (never lower a long's SL)
            if(newTrailSL > pos.currentSL)
            {
               if(m_trade.PositionModify(pos.ticket, newTrailSL, 0))
                  pos.currentSL = newTrailSL;
            }
         }
         else
         {
            newTrailSL = currentPrice + trailDistance;
            newTrailSL = NormalizeToTick(pos.symbol, newTrailSL);

            // NEVER move SL against position (never raise a short's SL)
            if(newTrailSL < pos.currentSL || pos.currentSL <= 0)
            {
               if(m_trade.PositionModify(pos.ticket, newTrailSL, 0))
                  pos.currentSL = newTrailSL;
            }
         }
      }
   }

   //--- Record trade result for streak + win-rate + journal tracking
   void RecordClosedTrade(const ManagedPosition &pos)
   {
      // Check deal history for this position
      HistorySelect(pos.entryTime, TimeCurrent());
      int totalDeals = HistoryDealsTotal();

      double totalProfit = 0;
      double exitPrice = 0;
      for(int i = 0; i < totalDeals; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0) continue;

         if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == (long)pos.ticket)
         {
            long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY)
            {
               totalProfit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               exitPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            }
         }
      }

      bool isWin = (totalProfit > 0);
      double pips = PointsToPips(pos.symbol, MathAbs(totalProfit));

      // Determine exit reason if not already set (CHoCH sets it before close)
      string reason = pos.exitReason;
      if(reason == "")
         reason = InferExitReason(pos, exitPrice);

      // Update streak manager
      if(m_streak != NULL)
         m_streak.RecordResult(isWin, pos.qualityAtEntry);

      // Update win-rate tracker
      if(m_winRate != NULL)
         m_winRate.RecordTrade(pos.symbol, isWin, pips);

      // Log to trade journal for adaptive learning
      if(m_journal != NULL)
         m_journal.LogTradeClose(pos.ticket, exitPrice, pips, totalProfit, isWin, reason);

      m_log.Info(StringFormat("Trade closed: %s %s P&L=%.2f (%s) [%s]",
                 pos.symbol, DirectionToString(pos.direction),
                 totalProfit, isWin ? "WIN" : "LOSS", reason));
   }

   //--- Infer exit reason from close price vs SL/TP levels
   string InferExitReason(const ManagedPosition &pos, double exitPrice)
   {
      if(exitPrice <= 0) return "UNKNOWN";

      double point = SymbolInfoDouble(pos.symbol, SYMBOL_POINT);
      double tolerance = point * 30; // 3 pip tolerance for slippage

      // Check if hit stop loss
      if(pos.currentSL > 0 && MathAbs(exitPrice - pos.currentSL) <= tolerance)
      {
         if(pos.tp1Hit)
            return "TRAILING";  // SL was trailing after TP1
         return "SL";
      }

      // Check if hit take profit
      if(pos.takeProfit1 > 0 && !pos.tp1Hit &&
         MathAbs(exitPrice - pos.takeProfit1) <= tolerance)
         return "TP";

      // If TP1 was already hit and position closed profitably, it was trailing
      if(pos.tp1Hit)
         return "TRAILING";

      return "SL";  // Default: most closes without TP are stops
   }

   //--- Remove position from array
   void RemovePosition(ManagedPosition &arr[], int &count, int idx)
   {
      for(int i = idx; i < count - 1; i++)
         arr[i] = arr[i + 1];
      count--;
   }
};

#endif
