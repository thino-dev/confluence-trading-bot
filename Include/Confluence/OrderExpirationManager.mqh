//+------------------------------------------------------------------+
//|                                     OrderExpirationManager.mqh    |
//|                          Confluence Trading System                 |
//|                          Zone expiry + re-scoring                 |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_ORDEREXPIRATIONMANAGER_MQH
#define CONFLUENCE_ORDEREXPIRATIONMANAGER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "ScoringEngine.mqh"
#include "TradeInvalidator.mqh"

//+------------------------------------------------------------------+
//| Zone Expiration Manager                                           |
//| Counts candle closes since zone was stored.                      |
//| At expiry (3 candles), re-runs full scoring.                     |
//| If still valid, resets counter. If not, removes zone.            |
//+------------------------------------------------------------------+
class COrderExpirationManager
{
private:
   CScoringEngine*      m_scorer;
   CTradeInvalidator*   m_invalidator;
   CLogger              m_log;

public:
   COrderExpirationManager() : m_scorer(NULL), m_invalidator(NULL)
   { m_log.SetPrefix("ZoneExpiry"); }

   void Init(CScoringEngine *scorer, CTradeInvalidator *invalidator)
   {
      m_scorer = scorer;
      m_invalidator = invalidator;
   }

   //--- Check and manage zone expiration
   //    Called once per new bar per symbol
   void CheckExpiration(const string symbol,
                         PendingSetup &setups[], int &setupCount)
   {
      for(int i = setupCount - 1; i >= 0; i--)
      {
         if(setups[i].symbol != symbol || !setups[i].isActive)
            continue;

         // Increment candle counter
         setups[i].candlesSincePlaced++;

         if(setups[i].candlesSincePlaced >= setups[i].maxCandles)
         {
            // Re-score the setup
            ScoreCard newCard;
            newCard.Reset();

            bool gatePass = m_scorer.EvaluateLayer1(symbol, newCard);

            if(gatePass)
            {
               bool invalidated = m_invalidator.Check(newCard);

               if(!invalidated)
               {
                  m_scorer.EvaluateLayer2(symbol, newCard);
                  m_scorer.EvaluateLayer3(symbol, newCard);
                  m_scorer.EvaluateLayer4(symbol, newCard);
                  m_scorer.EvaluateContradictions(symbol, newCard);
                  m_scorer.CalculateFinalScore(newCard);

                  if(newCard.totalScore >= InpMinScoreToTrade)
                  {
                     // Setup still valid — reset counter, update zone
                     setups[i].candlesSincePlaced = 0;
                     setups[i].scoreAtPlacement   = newCard.totalScore;
                     setups[i].qualityAtPlacement = newCard.qualityLevel;
                     setups[i].entryPrice         = newCard.entryPrice;
                     setups[i].stopLoss           = newCard.stopLoss;
                     setups[i].takeProfit         = newCard.takeProfit1;
                     setups[i].obHighPrice        = newCard.activeOB.highPrice;
                     setups[i].obLowPrice         = newCard.activeOB.lowPrice;

                     m_log.Info(StringFormat("%s: zone renewed (score=%d, OB=[%.5f-%.5f])",
                                symbol, newCard.totalScore,
                                setups[i].obLowPrice, setups[i].obHighPrice));
                     continue;
                  }
               }
            }

            // Setup no longer qualifies — remove zone
            m_log.Info(StringFormat("%s: zone expired after %d candles (re-score failed)",
                       symbol, setups[i].candlesSincePlaced));

            setups[i].isActive = false;
            RemoveSetup(setups, setupCount, i);
         }
      }
   }

private:
   void RemoveSetup(PendingSetup &arr[], int &count, int idx)
   {
      for(int i = idx; i < count - 1; i++)
         arr[i] = arr[i + 1];
      count--;
   }
};

#endif
