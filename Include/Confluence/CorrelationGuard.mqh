//+------------------------------------------------------------------+
//|                                            CorrelationGuard.mqh   |
//|                          Confluence Trading System                 |
//|                          Same-currency exposure limiter           |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_CORRELATIONGUARD_MQH
#define CONFLUENCE_CORRELATIONGUARD_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| Correlation Guard                                                 |
//| Prevents over-exposure to a single currency.                     |
//| Max 2 positions sharing the same base or quote currency.         |
//| EUR/USD long + GBP/USD long + AUD/USD long = triple USD short.  |
//+------------------------------------------------------------------+
class CCorrelationGuard
{
private:
   CLogger           m_log;

public:
   CCorrelationGuard() { m_log.SetPrefix("CorrGuard"); }

   //--- Check if opening a new position on this symbol would violate correlation limits
   bool IsAllowed(const string newSymbol,
                   const ManagedPosition &positions[], int posCount)
   {
      if(posCount == 0) return true;

      string newBase  = GetBaseCurrency(newSymbol);
      string newQuote = GetQuoteCurrency(newSymbol);

      int baseExposure  = 0;
      int quoteExposure = 0;

      for(int i = 0; i < posCount; i++)
      {
         string posBase  = GetBaseCurrency(positions[i].symbol);
         string posQuote = GetQuoteCurrency(positions[i].symbol);

         // Count how many existing positions share a currency with the new symbol
         if(posBase == newBase || posBase == newQuote)
            baseExposure++;
         if(posQuote == newBase || posQuote == newQuote)
            quoteExposure++;
      }

      bool allowed = (baseExposure < InpMaxSameCurrency &&
                      quoteExposure < InpMaxSameCurrency);

      if(!allowed)
      {
         m_log.Info(StringFormat("Correlation guard blocked %s: base_exp=%d, quote_exp=%d (max=%d)",
                    newSymbol, baseExposure, quoteExposure, InpMaxSameCurrency));
      }

      return allowed;
   }
};

#endif
