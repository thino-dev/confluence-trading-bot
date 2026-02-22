//+------------------------------------------------------------------+
//|                                                  Dashboard.mqh    |
//|                          Confluence Trading System                 |
//|                          On-chart info panel                     |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_DASHBOARD_MQH
#define CONFLUENCE_DASHBOARD_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//| Displays real-time system status on the chart.                   |
//| Shows all 12 pairs, scores, positions, P&L, streak.             |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   string            m_prefix;
   int               m_xStart;
   int               m_yStart;
   color             m_bgColor;
   color             m_textColor;
   color             m_headerColor;
   int               m_fontSize;

   // Cached display data per symbol
   struct SymbolDisplay
   {
      string symbol;
      string trend;
      int    bosCount;
      int    score;
      string quality;
      string position;
      color  qualityColor;
   };

   SymbolDisplay     m_displays[MAX_SYMBOLS];
   int               m_displayCount;

public:
   CDashboard() : m_prefix("CTS_"), m_xStart(10), m_yStart(30),
                   m_bgColor(C'20,20,30'), m_textColor(clrWhite),
                   m_headerColor(C'0,150,255'), m_fontSize(8),
                   m_displayCount(0) {}

   //--- Create the dashboard
   void Create()
   {
      if(!InpShowDashboard) return;

      // Background panel
      CreateRectLabel(m_prefix + "BG", m_xStart, m_yStart, 520, 340, m_bgColor);

      // Title
      CreateLabel(m_prefix + "TITLE", m_xStart + 10, m_yStart + 5,
                  "CONFLUENCE TRADING SYSTEM", m_headerColor, 10);

      // Header row
      int headerY = m_yStart + 28;
      CreateLabel(m_prefix + "H_SYM",   m_xStart + 10,  headerY, "Symbol",   m_headerColor, m_fontSize);
      CreateLabel(m_prefix + "H_TREND", m_xStart + 90,  headerY, "Trend",    m_headerColor, m_fontSize);
      CreateLabel(m_prefix + "H_BOS",   m_xStart + 145, headerY, "BOS",      m_headerColor, m_fontSize);
      CreateLabel(m_prefix + "H_SCORE", m_xStart + 185, headerY, "Score",    m_headerColor, m_fontSize);
      CreateLabel(m_prefix + "H_QUAL",  m_xStart + 235, headerY, "Quality",  m_headerColor, m_fontSize);
      CreateLabel(m_prefix + "H_POS",   m_xStart + 320, headerY, "Position", m_headerColor, m_fontSize);

      // Separator line
      CreateRectLabel(m_prefix + "SEP1", m_xStart + 5, headerY + 15, 510, 1, m_headerColor);

      // Symbol rows (will be updated in UpdateSymbolStatus)
      for(int i = 0; i < MAX_SYMBOLS; i++)
      {
         int rowY = m_yStart + 48 + i * 18;
         string idx = IntegerToString(i);
         CreateLabel(m_prefix + "S_" + idx, m_xStart + 10,  rowY, "---",  C'100,100,100', m_fontSize);
         CreateLabel(m_prefix + "T_" + idx, m_xStart + 90,  rowY, "---",  C'100,100,100', m_fontSize);
         CreateLabel(m_prefix + "B_" + idx, m_xStart + 145, rowY, "---",  C'100,100,100', m_fontSize);
         CreateLabel(m_prefix + "C_" + idx, m_xStart + 185, rowY, "---",  C'100,100,100', m_fontSize);
         CreateLabel(m_prefix + "Q_" + idx, m_xStart + 235, rowY, "---",  C'100,100,100', m_fontSize);
         CreateLabel(m_prefix + "P_" + idx, m_xStart + 320, rowY, "---",  C'100,100,100', m_fontSize);
      }

      // Footer area
      int footerY = m_yStart + 270;
      CreateRectLabel(m_prefix + "SEP2", m_xStart + 5, footerY, 510, 1, m_headerColor);
      CreateLabel(m_prefix + "PNL",     m_xStart + 10,  footerY + 5,  "P&L: $0.00",        m_textColor, m_fontSize);
      CreateLabel(m_prefix + "DAILY",   m_xStart + 140, footerY + 5,  "Daily: 0.0%",       m_textColor, m_fontSize);
      CreateLabel(m_prefix + "WEEKLY",  m_xStart + 270, footerY + 5,  "Weekly: 0.0%",      m_textColor, m_fontSize);
      CreateLabel(m_prefix + "POSCOUNT",m_xStart + 10,  footerY + 22, "Positions: 0/3",    m_textColor, m_fontSize);
      CreateLabel(m_prefix + "STREAK",  m_xStart + 140, footerY + 22, "Streak: W0 (Norm)", m_textColor, m_fontSize);
      CreateLabel(m_prefix + "STATUS",  m_xStart + 320, footerY + 22, "ACTIVE",            clrLime,     m_fontSize);

      ChartRedraw();
   }

   //--- Update a symbol row with score card data
   void UpdateSymbolStatus(int idx, const ScoreCard &card)
   {
      if(!InpShowDashboard || idx < 0 || idx >= MAX_SYMBOLS) return;

      string idxStr = IntegerToString(idx);

      // Symbol name
      UpdateLabel(m_prefix + "S_" + idxStr, card.symbol, m_textColor);

      // Trend
      color trendColor = (card.htfTrend == TREND_BULLISH) ? clrLime :
                          (card.htfTrend == TREND_BEARISH) ? clrRed : C'100,100,100';
      UpdateLabel(m_prefix + "T_" + idxStr, TrendToString(card.htfTrend), trendColor);

      // BOS count
      color bosColor = (card.bosCount >= InpMinBOSCount) ? clrLime : C'100,100,100';
      UpdateLabel(m_prefix + "B_" + idxStr, IntegerToString(card.bosCount), bosColor);

      // Score
      color scoreColor = GetScoreColor(card.totalScore);
      string scoreStr = card.gatePass ? IntegerToString(card.totalScore) : "--";
      UpdateLabel(m_prefix + "C_" + idxStr, scoreStr, scoreColor);

      // Quality
      color qualColor = GetQualityColor(card.qualityLevel);
      UpdateLabel(m_prefix + "Q_" + idxStr, QualityToString(card.qualityLevel), qualColor);

      // Position status (updated separately)
   }

   //--- Update position status for a symbol row
   void UpdatePositionStatus(int idx, const string status, color clr)
   {
      if(!InpShowDashboard || idx < 0 || idx >= MAX_SYMBOLS) return;
      UpdateLabel(m_prefix + "P_" + IntegerToString(idx), status, clr);
   }

   //--- Update footer stats
   void UpdateFooter(double pnl, double dailyDD, double weeklyDD,
                      int posCount, int maxPos,
                      int wins, int losses, ENUM_SIZE_MODE sizeMode,
                      bool isActive)
   {
      if(!InpShowDashboard) return;

      color pnlColor = (pnl >= 0) ? clrLime : clrRed;
      UpdateLabel(m_prefix + "PNL",
                  StringFormat("P&L: $%.2f", pnl), pnlColor);

      color dailyColor = (dailyDD < InpDailyLossLimit * 0.7) ? m_textColor :
                          (dailyDD < InpDailyLossLimit) ? clrYellow : clrRed;
      UpdateLabel(m_prefix + "DAILY",
                  StringFormat("Daily: -%.1f%%", MathMax(0, dailyDD)), dailyColor);

      color weeklyColor = (weeklyDD < InpWeeklyLossLimit * 0.7) ? m_textColor :
                           (weeklyDD < InpWeeklyLossLimit) ? clrYellow : clrRed;
      UpdateLabel(m_prefix + "WEEKLY",
                  StringFormat("Weekly: -%.1f%%", MathMax(0, weeklyDD)), weeklyColor);

      UpdateLabel(m_prefix + "POSCOUNT",
                  StringFormat("Positions: %d/%d", posCount, maxPos), m_textColor);

      string sizeModeStr = (sizeMode == SIZE_REDUCED) ? "Red" :
                           (sizeMode == SIZE_BOOSTED) ? "Boost" : "Norm";
      string streakStr = StringFormat("W%d L%d (%s)", wins, losses, sizeModeStr);
      UpdateLabel(m_prefix + "STREAK", "Streak: " + streakStr, m_textColor);

      UpdateLabel(m_prefix + "STATUS",
                  isActive ? "ACTIVE" : "PAUSED",
                  isActive ? clrLime : clrRed);

      ChartRedraw();
   }

   //--- Destroy dashboard objects
   void Destroy()
   {
      ObjectsDeleteAll(0, m_prefix);
      ChartRedraw();
   }

private:
   void CreateRectLabel(const string name, int x, int y, int w, int h, color bgClr)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'40,40,60');
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   void CreateLabel(const string name, int x, int y,
                     const string text, color clr, int fontSize)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   void UpdateLabel(const string name, const string text, color clr)
   {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   }

   color GetScoreColor(int score)
   {
      if(score >= SCORE_PRIORITY_MIN) return C'0,255,128';  // Bright green
      if(score >= SCORE_ENTER_MIN)    return clrLime;
      if(score >= SCORE_CONSIDER_MIN) return clrYellow;
      if(score > SCORE_REJECT_MAX)    return C'200,200,0';
      return C'100,100,100';
   }

   color GetQualityColor(ENUM_QUALITY_LEVEL q)
   {
      switch(q)
      {
         case QUALITY_PRIORITY: return C'0,255,128';
         case QUALITY_ENTER:    return clrLime;
         case QUALITY_CONSIDER: return clrYellow;
         case QUALITY_WATCH:    return C'200,200,0';
         default:               return C'100,100,100';
      }
   }
};

#endif
