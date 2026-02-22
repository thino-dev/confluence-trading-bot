//+------------------------------------------------------------------+
//|                                                  NewsFilter.mqh   |
//|                          Confluence Trading System                 |
//|                          MT5 Economic Calendar integration       |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_NEWSFILTER_MQH
#define CONFLUENCE_NEWSFILTER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| News Filter                                                       |
//| Uses MT5's built-in CalendarValueHistory to detect upcoming      |
//| high-impact news events. Trade invalidator if within 4 hours.    |
//| NOTE: Does NOT work in Strategy Tester — returns false there.    |
//+------------------------------------------------------------------+
class CNewsFilter
{
private:
   CLogger           m_log;

public:
   CNewsFilter() { m_log.SetPrefix("News"); }

   //--- Check if high-impact news is within the buffer window for this pair
   bool IsNewsUpcoming(const string symbol)
   {
      if(!InpEnableNewsFilter) return false;

      // CalendarValueHistory not available in Strategy Tester
      if(IsTesting()) return false;

      string baseCurrency  = GetBaseCurrency(symbol);
      string quoteCurrency = GetQuoteCurrency(symbol);

      datetime from = TimeCurrent();
      datetime to   = from + InpNewsBufferMinutes * 60;

      MqlCalendarValue values[];
      int count = CalendarValueHistory(values, from, to);

      if(count <= 0) return false;

      for(int i = 0; i < count; i++)
      {
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event))
            continue;

         // Filter by impact level
         if(InpFilterHighImpactOnly && event.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;

         // Get the country/currency for this event
         MqlCalendarCountry country;
         if(!CalendarCountryById(event.country_id, country))
            continue;

         // Check if event currency matches either side of the pair
         string eventCurrency = country.currency;

         if(eventCurrency == baseCurrency || eventCurrency == quoteCurrency)
         {
            m_log.Info(StringFormat("News filter: %s has high-impact event for %s within %d min",
                       symbol, eventCurrency, InpNewsBufferMinutes));
            return true;
         }
      }

      return false;
   }
};

#endif
