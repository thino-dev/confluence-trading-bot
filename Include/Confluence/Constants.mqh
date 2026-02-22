//+------------------------------------------------------------------+
//|                                                   Constants.mqh   |
//|                          Confluence Trading System                 |
//|                          Foundation: Enums, Defines, Constants     |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_CONSTANTS_MQH
#define CONFLUENCE_CONSTANTS_MQH

//--- System limits
#define MAX_SYMBOLS           12
#define MAX_POSITIONS         3
#define MAX_SWING_POINTS      100
#define MAX_OB_ZONES          20
#define MAX_FVG_ZONES         30
#define MAX_BOS_EVENTS        50
#define MAX_PENDING_SETUPS    10
#define MAGIC_NUMBER_DEFAULT  20260219

//--- Scoring thresholds
#define SCORE_REJECT_MAX      5
#define SCORE_WATCH_MAX       7
#define SCORE_CONSIDER_MIN    8
#define SCORE_ENTER_MIN       11
#define SCORE_PRIORITY_MIN    14

//--- Trend Direction
enum ENUM_TREND_DIRECTION
{
   TREND_BULLISH  =  1,    // Higher Highs + Higher Lows
   TREND_BEARISH  = -1,    // Lower Highs + Lower Lows
   TREND_NEUTRAL  =  0     // Unclear / Ranging
};

//--- Break of Structure
enum ENUM_BOS_TYPE
{
   BOS_BULLISH = 1,        // Price broke above previous swing high
   BOS_BEARISH = -1,       // Price broke below previous swing low
   BOS_NONE    = 0
};

//--- Change of Character
enum ENUM_CHOCH_TYPE
{
   CHOCH_BULLISH  = 1,     // Potential reversal to upside
   CHOCH_BEARISH  = -1,    // Potential reversal to downside
   CHOCH_NONE     = 0
};

//--- Order Block Type
enum ENUM_OB_TYPE
{
   OB_BULLISH = 1,         // Last bearish candle before bullish impulse (buy zone)
   OB_BEARISH = -1,        // Last bullish candle before bearish impulse (sell zone)
   OB_NONE    = 0
};

//--- Premium / Discount Zone
enum ENUM_ZONE_TYPE
{
   ZONE_DISCOUNT    =  1,  // Below 50% — buy zone
   ZONE_PREMIUM     = -1,  // Above 50% — sell zone
   ZONE_EQUILIBRIUM =  0   // At 50% — avoid
};

//--- Setup Quality Level
enum ENUM_QUALITY_LEVEL
{
   QUALITY_REJECT   = 0,   // 0-5 pts: Invalid
   QUALITY_WATCH    = 1,   // 6-7 pts: Monitor only
   QUALITY_CONSIDER = 2,   // 8-10 pts: Valid, review before entering
   QUALITY_ENTER    = 3,   // 11-13 pts: Strong confluence
   QUALITY_PRIORITY = 4    // 14+ pts: Exceptional, max size
};

//--- Trade Direction
enum ENUM_TRADE_DIRECTION
{
   TRADE_LONG  =  1,
   TRADE_SHORT = -1,
   TRADE_NONE  =  0
};

//--- Session Type
enum ENUM_SESSION_TYPE
{
   SESSION_ASIAN      = 0,
   SESSION_LONDON     = 1,
   SESSION_NEW_YORK   = 2,
   SESSION_OVERLAP    = 3, // London/NY overlap
   SESSION_OFF_HOURS  = 4
};

//--- Alert Type
enum ENUM_ALERT_TYPE
{
   ALERT_NEW_SETUP         = 0,
   ALERT_ORDER_PLACED      = 1,
   ALERT_ORDER_TRIGGERED   = 2,
   ALERT_PARTIAL_CLOSE     = 3,
   ALERT_TRADE_CLOSED      = 4,
   ALERT_LOSS_LIMIT_WARN   = 5
};

//--- Position Size Mode (streak-based)
enum ENUM_SIZE_MODE
{
   SIZE_NORMAL  = 0,       // Standard 2% equity
   SIZE_REDUCED = 1,       // 50% after 3 consecutive losses
   SIZE_BOOSTED = 2        // 150% after 5 consecutive wins on PRIORITY
};

//--- Log Level
enum ENUM_LOG_LEVEL
{
   LOG_DEBUG   = 0,
   LOG_INFO    = 1,
   LOG_WARNING = 2,
   LOG_ERROR   = 3
};

//--- Adaptive Learning
#define ADAPTIVE_SIGNAL_COUNT  14
#define MAX_JOURNAL_ENTRIES    2000

#endif
