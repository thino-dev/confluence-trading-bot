//+------------------------------------------------------------------+
//|                                              TradeJournal.mqh     |
//|                          Confluence Trading System                 |
//|                          Detailed trade logging for learning      |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_TRADEJOURNAL_MQH
#define CONFLUENCE_TRADEJOURNAL_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| Trade Journal                                                     |
//| Records full ScoreCard snapshot at trade entry and outcome at     |
//| trade close. Persists to CSV for the AdaptiveOptimizer to read.  |
//| NEVER modifies Layer 1 gate or invalidator logic.                |
//+------------------------------------------------------------------+
class CTradeJournal
{
private:
   CLogger              m_log;
   string               m_filename;

   // Completed trade entries (loaded from + written to CSV)
   TradeJournalEntry    m_entries[];
   int                  m_entryCount;

   // Open trade snapshots (waiting for close to complete the entry)
   struct OpenSnapshot
   {
      ulong             ticket;
      bool              isUsed;
      string            symbol;
      ENUM_TRADE_DIRECTION direction;
      datetime          entryTime;
      int               scoreAtEntry;
      ENUM_QUALITY_LEVEL qualityAtEntry;
      bool              signals[ADAPTIVE_SIGNAL_COUNT];
      int               contradictionCount;
      int               bosCount;
      double            rrSpreadAdjusted;
      double            adxValue;
      double            entryPrice;
      double            stopLoss;
      double            takeProfit;
   };

   OpenSnapshot         m_snapshots[];
   int                  m_snapshotCount;

public:
   CTradeJournal() : m_entryCount(0), m_snapshotCount(0)
   {
      m_log.SetPrefix("Journal");
      ArrayResize(m_entries, 0, MAX_JOURNAL_ENTRIES);
      ArrayResize(m_snapshots, 0, 16);
   }

   void Init(const string filename)
   {
      m_filename = filename;
   }

   //--- Snapshot a trade at order fill (captures full signal state)
   void LogTradeOpen(ulong positionTicket, const ScoreCard &card)
   {
      // Check if we already have a snapshot for this ticket
      for(int i = 0; i < m_snapshotCount; i++)
         if(m_snapshots[i].isUsed && m_snapshots[i].ticket == positionTicket)
            return;

      // Add new snapshot
      int idx = m_snapshotCount;
      m_snapshotCount++;
      ArrayResize(m_snapshots, m_snapshotCount, 16);

      m_snapshots[idx].ticket            = positionTicket;
      m_snapshots[idx].isUsed            = true;
      m_snapshots[idx].symbol            = card.symbol;
      m_snapshots[idx].direction         = card.direction;
      m_snapshots[idx].entryTime         = card.analysisTime;
      m_snapshots[idx].scoreAtEntry      = card.totalScore;
      m_snapshots[idx].qualityAtEntry    = card.qualityLevel;
      m_snapshots[idx].contradictionCount= card.contradictionCount;
      m_snapshots[idx].bosCount          = card.bosCount;
      m_snapshots[idx].rrSpreadAdjusted  = card.rrSpreadAdjusted;
      m_snapshots[idx].adxValue          = card.adxValue;
      m_snapshots[idx].entryPrice        = card.entryPrice;
      m_snapshots[idx].stopLoss          = card.stopLoss;
      m_snapshots[idx].takeProfit        = card.takeProfit1;

      // Extract 14 Layer 2/3/4 signals
      ExtractSignals(card, m_snapshots[idx].signals);

      m_log.Info(StringFormat("Snapshot saved: %s %s ticket=%d score=%d",
                 card.symbol, DirectionToString(card.direction),
                 positionTicket, card.totalScore));
   }

   //--- Complete a journal entry when trade closes
   void LogTradeClose(ulong positionTicket, double exitPrice,
                       double profitPips, double profitMoney,
                       bool isWin, const string exitReason)
   {
      // Find matching snapshot
      int snapIdx = -1;
      for(int i = 0; i < m_snapshotCount; i++)
      {
         if(m_snapshots[i].isUsed && m_snapshots[i].ticket == positionTicket)
         {
            snapIdx = i;
            break;
         }
      }

      if(snapIdx < 0)
      {
         m_log.Warning(StringFormat("No snapshot found for ticket %d", positionTicket));
         return;
      }

      // Build complete journal entry
      TradeJournalEntry entry;
      entry.Reset();

      entry.symbol            = m_snapshots[snapIdx].symbol;
      entry.ticket            = positionTicket;
      entry.direction         = m_snapshots[snapIdx].direction;
      entry.entryTime         = m_snapshots[snapIdx].entryTime;
      entry.exitTime          = TimeCurrent();
      entry.scoreAtEntry      = m_snapshots[snapIdx].scoreAtEntry;
      entry.qualityAtEntry    = m_snapshots[snapIdx].qualityAtEntry;

      for(int i = 0; i < ADAPTIVE_SIGNAL_COUNT; i++)
         entry.signals[i] = m_snapshots[snapIdx].signals[i];

      entry.contradictionCount= m_snapshots[snapIdx].contradictionCount;
      entry.bosCount          = m_snapshots[snapIdx].bosCount;
      entry.rrSpreadAdjusted  = m_snapshots[snapIdx].rrSpreadAdjusted;
      entry.adxValue          = m_snapshots[snapIdx].adxValue;
      entry.entryPrice        = m_snapshots[snapIdx].entryPrice;
      entry.exitPrice         = exitPrice;
      entry.stopLoss          = m_snapshots[snapIdx].stopLoss;
      entry.takeProfit        = m_snapshots[snapIdx].takeProfit;
      entry.profitPips        = profitPips;
      entry.profitMoney       = profitMoney;
      entry.isWin             = isWin;
      entry.exitReason        = exitReason;

      // Duration in execution-TF bars
      if(entry.entryTime > 0 && entry.exitTime > entry.entryTime)
         entry.durationBars = (int)((entry.exitTime - entry.entryTime) / PeriodSeconds(InpExecutionTF));

      // Append to entries
      if(m_entryCount < MAX_JOURNAL_ENTRIES)
      {
         ArrayResize(m_entries, m_entryCount + 1, MAX_JOURNAL_ENTRIES);
         m_entries[m_entryCount] = entry;
         m_entryCount++;
      }
      else
      {
         // Circular: overwrite oldest
         for(int i = 0; i < m_entryCount - 1; i++)
            m_entries[i] = m_entries[i + 1];
         m_entries[m_entryCount - 1] = entry;
      }

      // Free snapshot slot
      m_snapshots[snapIdx].isUsed = false;
      CompactSnapshots();

      m_log.Info(StringFormat("Trade logged: %s %s P&L=%.2f (%s) [%s] score=%d",
                 entry.symbol, DirectionToString(entry.direction),
                 profitMoney, isWin ? "WIN" : "LOSS",
                 exitReason, entry.scoreAtEntry));
   }

   //--- Accessors for the optimizer
   int GetEntryCount() const { return m_entryCount; }

   bool GetEntry(int idx, TradeJournalEntry &entry) const
   {
      if(idx < 0 || idx >= m_entryCount) return false;
      entry = m_entries[idx];
      return true;
   }

   void GetAllEntries(TradeJournalEntry &entries[], int &count)
   {
      count = m_entryCount;
      ArrayResize(entries, m_entryCount);
      for(int i = 0; i < m_entryCount; i++)
         entries[i] = m_entries[i];
   }

   //--- CSV Persistence ---

   bool LoadFromFile(const string filename)
   {
      string fname = (filename != "") ? filename : m_filename;
      if(fname == "") return false;

      int handle = FileOpen(fname, FILE_READ | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
      {
         m_log.Info("No journal file found — starting fresh.");
         return false;
      }

      // Skip header
      if(!FileIsEnding(handle))
         FileReadString(handle); // Skip header line (just reads first field)
      // Actually, read the whole header line
      // CSV reader reads field by field, so skip the header row
      FileClose(handle);

      // Re-open and parse properly
      handle = FileOpen(fname, FILE_READ | FILE_TXT | FILE_ANSI);
      if(handle == INVALID_HANDLE) return false;

      m_entryCount = 0;
      ArrayResize(m_entries, 0, MAX_JOURNAL_ENTRIES);

      // Skip header line
      if(!FileIsEnding(handle))
         FileReadString(handle);

      while(!FileIsEnding(handle) && m_entryCount < MAX_JOURNAL_ENTRIES)
      {
         string line = FileReadString(handle);
         if(StringLen(line) < 10) continue;

         TradeJournalEntry entry;
         entry.Reset();

         if(ParseCSVLine(line, entry))
         {
            ArrayResize(m_entries, m_entryCount + 1, MAX_JOURNAL_ENTRIES);
            m_entries[m_entryCount] = entry;
            m_entryCount++;
         }
      }

      FileClose(handle);
      m_log.Info(StringFormat("Loaded %d journal entries from %s", m_entryCount, fname));
      return true;
   }

   bool SaveToFile(const string filename)
   {
      string fname = (filename != "") ? filename : m_filename;
      if(fname == "") return false;

      int handle = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(handle == INVALID_HANDLE)
      {
         m_log.Error(StringFormat("Cannot write journal: %s", fname));
         return false;
      }

      // Header
      FileWriteString(handle,
         "SYMBOL,TICKET,DIR,ENTRY_TIME,EXIT_TIME,SCORE,QUALITY,"
         "S0,S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,"
         "CONTRA,BOS,RR,ADX,ENTRY_PX,EXIT_PX,SL,TP,"
         "PROFIT_PIPS,PROFIT_MONEY,IS_WIN,EXIT_REASON,DURATION\n");

      for(int i = 0; i < m_entryCount; i++)
      {
         string line = FormatCSVLine(m_entries[i]);
         FileWriteString(handle, line + "\n");
      }

      FileClose(handle);
      m_log.Info(StringFormat("Saved %d journal entries to %s", m_entryCount, fname));
      return true;
   }

private:
   //--- Extract 14 signals from ScoreCard into bool array
   void ExtractSignals(const ScoreCard &card, bool &sigs[])
   {
      sigs[0]  = card.liquiditySweepAtOB;
      sigs[1]  = card.fvgOverlapOB;
      sigs[2]  = card.inducementTaken;
      sigs[3]  = card.microMSSConfirmed;
      sigs[4]  = card.rsiDivergence;
      sigs[5]  = card.emaConfluence;
      sigs[6]  = card.volumeSurge;
      sigs[7]  = card.lrcAtBound;
      sigs[8]  = card.atrCompression;
      sigs[9]  = card.vwapRetest;
      sigs[10] = card.pdhPdlAlignment;
      sigs[11] = card.sessionKillzone;
      sigs[12] = card.fibGoldenPocket;
      sigs[13] = card.winRateQualified;
   }

   //--- Compact snapshot array (remove freed slots)
   void CompactSnapshots()
   {
      int writeIdx = 0;
      for(int i = 0; i < m_snapshotCount; i++)
      {
         if(m_snapshots[i].isUsed)
         {
            if(writeIdx != i)
               m_snapshots[writeIdx] = m_snapshots[i];
            writeIdx++;
         }
      }
      m_snapshotCount = writeIdx;
      ArrayResize(m_snapshots, m_snapshotCount, 16);
   }

   //--- Format one entry to CSV
   string FormatCSVLine(const TradeJournalEntry &e)
   {
      string line = StringFormat("%s,%d,%d,%d,%d,%d,%d,",
         e.symbol, (long)e.ticket, (int)e.direction,
         (long)e.entryTime, (long)e.exitTime,
         e.scoreAtEntry, (int)e.qualityAtEntry);

      // 14 signals
      for(int i = 0; i < ADAPTIVE_SIGNAL_COUNT; i++)
         line += IntegerToString(e.signals[i] ? 1 : 0) + ",";

      line += StringFormat("%d,%d,%.4f,%.2f,%.5f,%.5f,%.5f,%.5f,%.1f,%.2f,%d,%s,%d",
         e.contradictionCount, e.bosCount, e.rrSpreadAdjusted, e.adxValue,
         e.entryPrice, e.exitPrice, e.stopLoss, e.takeProfit,
         e.profitPips, e.profitMoney, e.isWin ? 1 : 0,
         e.exitReason, e.durationBars);

      return line;
   }

   //--- Parse one CSV line into entry
   bool ParseCSVLine(const string line, TradeJournalEntry &e)
   {
      string fields[];
      int count = StringSplit(line, ',', fields);
      if(count < 33) return false;

      e.symbol         = fields[0];
      e.ticket         = (ulong)StringToInteger(fields[1]);
      e.direction      = (ENUM_TRADE_DIRECTION)StringToInteger(fields[2]);
      e.entryTime      = (datetime)StringToInteger(fields[3]);
      e.exitTime       = (datetime)StringToInteger(fields[4]);
      e.scoreAtEntry   = (int)StringToInteger(fields[5]);
      e.qualityAtEntry = (ENUM_QUALITY_LEVEL)StringToInteger(fields[6]);

      for(int i = 0; i < ADAPTIVE_SIGNAL_COUNT; i++)
         e.signals[i] = (StringToInteger(fields[7 + i]) != 0);

      int off = 7 + ADAPTIVE_SIGNAL_COUNT; // 21
      e.contradictionCount = (int)StringToInteger(fields[off]);
      e.bosCount           = (int)StringToInteger(fields[off + 1]);
      e.rrSpreadAdjusted   = StringToDouble(fields[off + 2]);
      e.adxValue           = StringToDouble(fields[off + 3]);
      e.entryPrice         = StringToDouble(fields[off + 4]);
      e.exitPrice          = StringToDouble(fields[off + 5]);
      e.stopLoss           = StringToDouble(fields[off + 6]);
      e.takeProfit         = StringToDouble(fields[off + 7]);
      e.profitPips         = StringToDouble(fields[off + 8]);
      e.profitMoney        = StringToDouble(fields[off + 9]);
      e.isWin              = (StringToInteger(fields[off + 10]) != 0);
      e.exitReason         = fields[off + 11];
      e.durationBars       = (int)StringToInteger(fields[off + 12]);

      return true;
   }
};

#endif
