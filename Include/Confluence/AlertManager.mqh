//+------------------------------------------------------------------+
//|                                              AlertManager.mqh     |
//|                          Confluence Trading System                 |
//|                          Push notifications + on-screen alerts   |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_ALERTMANAGER_MQH
#define CONFLUENCE_ALERTMANAGER_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| Alert Manager                                                     |
//| Sends push notifications and on-screen alerts for key events.    |
//+------------------------------------------------------------------+
class CAlertManager
{
private:
   CLogger           m_log;
   datetime          m_lastAlertTime;
   int               m_minAlertIntervalSec;

public:
   CAlertManager() : m_lastAlertTime(0), m_minAlertIntervalSec(5)
   { m_log.SetPrefix("Alert"); }

   //--- Send an alert
   void Send(ENUM_ALERT_TYPE type, const string message)
   {
      if(!InpEnableAlerts) return;

      // Throttle: don't spam alerts
      if(TimeCurrent() - m_lastAlertTime < m_minAlertIntervalSec)
         return;

      string prefix = GetAlertPrefix(type);
      string fullMsg = StringFormat("[CTS] %s: %s", prefix, message);

      // On-screen alert
      Alert(fullMsg);

      // Push notification (requires MT5 push notifications configured)
      if(!IsTesting())
         SendNotification(fullMsg);

      m_lastAlertTime = TimeCurrent();
      m_log.Info(fullMsg);
   }

   //--- Send setup found alert with full score breakdown
   void SendSetupAlert(const ScoreCard &card)
   {
      if(!InpEnableAlerts) return;

      string msg = StringFormat(
         "%s %s | Score: %d (%s) | RR: %.1f\n"
         "L2[Sweep:%s FVG:%s IDM:%s MSS:%s] "
         "L3[RSI:%s EMA:%s Vol:%s LRC:%s ATR:%s] "
         "L4[VWAP:%s PDL:%s Sess:%s Fib:%s WR:%s] "
         "Contra: %d",
         card.symbol,
         DirectionToString(card.direction),
         card.totalScore,
         QualityToString(card.qualityLevel),
         card.rrSpreadAdjusted,
         BoolStr(card.liquiditySweepAtOB),
         BoolStr(card.fvgOverlapOB),
         BoolStr(card.inducementTaken),
         BoolStr(card.microMSSConfirmed),
         BoolStr(card.rsiDivergence),
         BoolStr(card.emaConfluence),
         BoolStr(card.volumeSurge),
         BoolStr(card.lrcAtBound),
         BoolStr(card.atrCompression),
         BoolStr(card.vwapRetest),
         BoolStr(card.pdhPdlAlignment),
         BoolStr(card.sessionKillzone),
         BoolStr(card.fibGoldenPocket),
         BoolStr(card.winRateQualified),
         card.contradictionCount);

      Send(ALERT_NEW_SETUP, msg);
   }

private:
   string GetAlertPrefix(ENUM_ALERT_TYPE type)
   {
      switch(type)
      {
         case ALERT_NEW_SETUP:       return "NEW SETUP";
         case ALERT_ORDER_PLACED:    return "ORDER PLACED";
         case ALERT_ORDER_TRIGGERED: return "ORDER TRIGGERED";
         case ALERT_PARTIAL_CLOSE:   return "PARTIAL CLOSE";
         case ALERT_TRADE_CLOSED:    return "TRADE CLOSED";
         case ALERT_LOSS_LIMIT_WARN: return "LOSS LIMIT";
      }
      return "INFO";
   }

   string BoolStr(bool val) { return val ? "Y" : "N"; }
};

#endif
