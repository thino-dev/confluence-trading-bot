//+------------------------------------------------------------------+
//|                                                   Utilities.mqh   |
//|                          Confluence Trading System                 |
//|                          Helpers: arrays, math, logging, parsing  |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_UTILITIES_MQH
#define CONFLUENCE_UTILITIES_MQH

#include "Constants.mqh"
#include "Types.mqh"

//+------------------------------------------------------------------+
//| Logging                                                           |
//+------------------------------------------------------------------+
class CLogger
{
private:
   ENUM_LOG_LEVEL    m_minLevel;
   string            m_prefix;

public:
   CLogger() : m_minLevel(LOG_INFO), m_prefix("CTS") {}

   void SetLevel(ENUM_LOG_LEVEL level)  { m_minLevel = level; }
   void SetPrefix(const string pfx)     { m_prefix = pfx; }

   void Debug(const string msg)
   {
      if(m_minLevel <= LOG_DEBUG)
         PrintFormat("[%s][DEBUG] %s", m_prefix, msg);
   }

   void Info(const string msg)
   {
      if(m_minLevel <= LOG_INFO)
         PrintFormat("[%s][INFO] %s", m_prefix, msg);
   }

   void Warning(const string msg)
   {
      if(m_minLevel <= LOG_WARNING)
         PrintFormat("[%s][WARN] %s", m_prefix, msg);
   }

   void Error(const string msg)
   {
      if(m_minLevel <= LOG_ERROR)
         PrintFormat("[%s][ERROR] %s", m_prefix, msg);
   }
};

//+------------------------------------------------------------------+
//| Symbol List Parsing                                               |
//+------------------------------------------------------------------+
int ParseSymbolList(const string csv, const string suffix, string &result[])
{
   string parts[];
   int count = StringSplit(csv, ',', parts);
   int valid = 0;

   ArrayResize(result, count);

   for(int i = 0; i < count; i++)
   {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);

      if(StringLen(sym) == 0)
         continue;

      // Append broker suffix if provided
      if(StringLen(suffix) > 0)
         sym += suffix;

      result[valid] = sym;
      valid++;
   }

   ArrayResize(result, valid);
   return valid;
}

//+------------------------------------------------------------------+
//| Currency extraction from pair names                               |
//+------------------------------------------------------------------+
string GetBaseCurrency(const string symbol)
{
   // Standard forex: first 3 chars (EURUSD -> EUR)
   // Strip any suffix first
   string clean = symbol;
   // Handle common suffixes
   int len = StringLen(clean);
   if(len > 6)
   {
      // Check for known suffixes and strip them
      string last3 = StringSubstr(clean, len - 3);
      string last2 = StringSubstr(clean, len - 2);
      string last1 = StringSubstr(clean, len - 1);
      if(last3 == "pro" || last2 == ".m" || last1 == "m" || last1 == ".")
      {
         // Try to find the 6-char pair name
         if(len > 6)
            clean = StringSubstr(clean, 0, 6);
      }
   }

   if(StringLen(clean) >= 3)
      return StringSubstr(clean, 0, 3);

   return clean;
}

string GetQuoteCurrency(const string symbol)
{
   string clean = symbol;
   int len = StringLen(clean);
   if(len > 6)
      clean = StringSubstr(clean, 0, 6);

   if(StringLen(clean) >= 6)
      return StringSubstr(clean, 3, 3);

   return "";
}

//+------------------------------------------------------------------+
//| Normalize a price to the symbol's tick size                       |
//+------------------------------------------------------------------+
double NormalizeToTick(const string symbol, double price)
{
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| Convert point distance to pips                                    |
//+------------------------------------------------------------------+
double PointsToPips(const string symbol, double points)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
      return points / (10.0 * SymbolInfoDouble(symbol, SYMBOL_POINT));
   return points / SymbolInfoDouble(symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Get the spread in price terms                                     |
//+------------------------------------------------------------------+
double GetSpreadAsPrice(const string symbol)
{
   double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   return spread * SymbolInfoDouble(symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Get volume precision (decimal places for lot sizing)              |
//+------------------------------------------------------------------+
int GetVolumePrecision(const string symbol)
{
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step >= 1.0) return 0;
   if(step >= 0.1) return 1;
   if(step >= 0.01) return 2;
   if(step >= 0.001) return 3;
   return 2; // safe default
}

//+------------------------------------------------------------------+
//| Normalize lot size to symbol constraints                          |
//+------------------------------------------------------------------+
double NormalizeLots(const string symbol, double lots)
{
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(lotStep <= 0) lotStep = 0.01;

   lots = MathMax(minLot, lots);
   lots = MathMin(maxLot, lots);
   lots = MathFloor(lots / lotStep) * lotStep;

   return NormalizeDouble(lots, GetVolumePrecision(symbol));
}

//+------------------------------------------------------------------+
//| Quality level to readable string                                  |
//+------------------------------------------------------------------+
string QualityToString(ENUM_QUALITY_LEVEL q)
{
   switch(q)
   {
      case QUALITY_REJECT:   return "REJECT";
      case QUALITY_WATCH:    return "WATCH";
      case QUALITY_CONSIDER: return "CONSIDER";
      case QUALITY_ENTER:    return "ENTER";
      case QUALITY_PRIORITY: return "PRIORITY";
   }
   return "UNKNOWN";
}

//+------------------------------------------------------------------+
//| Trend direction to readable string                                |
//+------------------------------------------------------------------+
string TrendToString(ENUM_TREND_DIRECTION t)
{
   switch(t)
   {
      case TREND_BULLISH: return "BULL";
      case TREND_BEARISH: return "BEAR";
      case TREND_NEUTRAL: return "NEUT";
   }
   return "???";
}

//+------------------------------------------------------------------+
//| Trade direction to readable string                                |
//+------------------------------------------------------------------+
string DirectionToString(ENUM_TRADE_DIRECTION d)
{
   switch(d)
   {
      case TRADE_LONG:  return "LONG";
      case TRADE_SHORT: return "SHORT";
      case TRADE_NONE:  return "NONE";
   }
   return "???";
}

//+------------------------------------------------------------------+
//| Check if currently in Strategy Tester                             |
//+------------------------------------------------------------------+
bool IsTesting()
{
   return (bool)MQLInfoInteger(MQL_TESTER);
}

//+------------------------------------------------------------------+
//| Get start of current day (server time)                            |
//+------------------------------------------------------------------+
datetime StartOfDay(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Get start of current week (Monday)                                |
//+------------------------------------------------------------------+
datetime StartOfWeek(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   // day_of_week: 0=Sunday, 1=Monday, ...
   int daysSinceMonday = dt.day_of_week == 0 ? 6 : dt.day_of_week - 1;
   datetime dayStart = StartOfDay(t);
   return dayStart - daysSinceMonday * 86400;
}

//+------------------------------------------------------------------+
//| Simple array append for SwingPoint                                |
//+------------------------------------------------------------------+
void AppendSwing(SwingPoint &arr[], const SwingPoint &item, int &count)
{
   if(count >= ArraySize(arr))
      ArrayResize(arr, count + 20);
   arr[count] = item;
   count++;
}

//+------------------------------------------------------------------+
//| Simple array append for BOSEvent                                  |
//+------------------------------------------------------------------+
void AppendBOS(BOSEvent &arr[], const BOSEvent &item, int &count)
{
   if(count >= ArraySize(arr))
      ArrayResize(arr, count + 10);
   arr[count] = item;
   count++;
}

//+------------------------------------------------------------------+
//| Simple array append for CHoCHEvent                                |
//+------------------------------------------------------------------+
void AppendCHoCH(CHoCHEvent &arr[], const CHoCHEvent &item, int &count)
{
   if(count >= ArraySize(arr))
      ArrayResize(arr, count + 10);
   arr[count] = item;
   count++;
}

//+------------------------------------------------------------------+
//| Simple array append for FairValueGap                              |
//+------------------------------------------------------------------+
void AppendFVG(FairValueGap &arr[], const FairValueGap &item, int &count)
{
   if(count >= ArraySize(arr))
      ArrayResize(arr, count + 10);
   arr[count] = item;
   count++;
}

#endif
