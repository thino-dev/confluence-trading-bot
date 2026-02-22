//+------------------------------------------------------------------+
//|                                             SessionManager.mqh    |
//|                          Confluence Trading System                 |
//|                          Trading session / killzone detection     |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_SESSIONMANAGER_MQH
#define CONFLUENCE_SESSIONMANAGER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| Session Manager                                                   |
//| Identifies current trading session and killzones.                |
//| London/NY opens are highest-probability windows.                 |
//+------------------------------------------------------------------+
class CSessionManager
{
private:
   CLogger           m_log;

public:
   CSessionManager() { m_log.SetPrefix("Session"); }

   //--- Get the current session type
   ENUM_SESSION_TYPE GetCurrentSession()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      // Check London/NY overlap first (highest priority)
      if(hour >= InpNYStartHour && hour < InpLondonEndHour)
         return SESSION_OVERLAP;

      // London session
      if(hour >= InpLondonStartHour && hour < InpLondonEndHour)
         return SESSION_LONDON;

      // New York session
      if(hour >= InpNYStartHour && hour < InpNYEndHour)
         return SESSION_NEW_YORK;

      // Asian session
      if(hour >= InpAsianStartHour && hour < InpAsianEndHour)
         return SESSION_ASIAN;

      return SESSION_OFF_HOURS;
   }

   //--- Check if we are in a killzone (London open or NY open)
   //    Killzones = the first 3 hours of London or NY session
   bool IsInKillzone()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      // London open killzone: first 3 hours
      if(hour >= InpLondonStartHour && hour < InpLondonStartHour + 3)
         return true;

      // NY open killzone: first 3 hours
      if(hour >= InpNYStartHour && hour < InpNYStartHour + 3)
         return true;

      return false;
   }

   //--- Check if we are in NY lunch (avoid zone)
   bool IsNYLunch()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // NY Lunch roughly corresponds to 17-18 broker time (12-1 PM EST)
      // This depends on broker timezone offset
      // Using a simple window around mid-NY session
      int lunchStart = InpNYStartHour + 4;  // ~4 hours into NY
      int lunchEnd   = lunchStart + 1;

      return (dt.hour >= lunchStart && dt.hour < lunchEnd);
   }

   //--- Check if current time falls within forex market hours
   bool IsForexMarketOpen()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Forex is closed Saturday and most of Sunday
      if(dt.day_of_week == 0 || dt.day_of_week == 6)
         return false;

      return true;
   }

   //--- Get session name for logging
   string GetSessionName(ENUM_SESSION_TYPE session)
   {
      switch(session)
      {
         case SESSION_ASIAN:     return "ASIAN";
         case SESSION_LONDON:    return "LONDON";
         case SESSION_NEW_YORK:  return "NEW_YORK";
         case SESSION_OVERLAP:   return "LDN/NY_OVERLAP";
         case SESSION_OFF_HOURS: return "OFF_HOURS";
      }
      return "UNKNOWN";
   }
};

#endif
