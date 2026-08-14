//+------------------------------------------------------------------+
//|                                            RangeChartCanvas.mq5 |
//|            TradingView-style range chart rendered on a CCanvas   |
//+------------------------------------------------------------------+
#property copyright "Range Chart"
#property version   "1.10"
#property indicator_chart_window
#property indicator_plots 0

#include <Canvas\Canvas.mqh>
#include "RangeAggregator.mqh"     // sit next to this file, no Include subfolder
#include "RangeDrawings.mqh"
#include "RangeStrategy.mqh"
#include "RangeDashboard.mqh"

//--- chart style, matching TradingView's two range-chart renderings
enum ENUM_RC_STYLE
  {
   RC_BARS    = 0,   // Bars (OHLC)
   RC_CANDLES = 1    // Candles
  };

//--- inputs
input ENUM_RC_STYLE InpStyle = RC_BARS;           // Chart style
input int    InpRange     = 100;                  // Range (ticks)
input int    InpBarStep   = 8;                    // Bar spacing (px)
input int    InpRightShift= 10;                   // Right shift (bars of empty space)
input bool   InpUseTicks  = true;                 // Seed from real ticks (else M1)
input color  InpBull      = C'38,166,154';        // Bullish
input color  InpBear      = C'239,83,80';         // Bearish
input color  InpBg        = C'19,23,34';          // Background
input color  InpGrid      = C'42,46,57';          // Grid
input color  InpText      = C'209,212,220';       // Text

//--- Hook Sharp v7.1, ported from the TradingView indicator. Every input
//--- below maps one-to-one onto the Pine input of the same meaning.
input group "Hook strategy"
input bool   InpHookOn        = true;   // Run the hook strategy
input bool   InpHookDraw      = true;   // Draw entries, stops and targets
input bool   InpHookDash      = true;   // Show the performance dashboard
input bool   InpHookDashFa    = false;  // Dashboard labels in Persian

input group "Hook / detection"
input double InpMaxDollarHook = 100.0;  // Max hook size ($)
input double InpMinPullback   = 10.0;   // Min hook pullback (%)
input int    InpMinHookBars   = 5;      // Min hook bars (unused by the Pine logic)
input int    InpMaxHookBars   = 15;     // Max hook bars
input int    InpLookBackLen   = 0;      // Look-back bars (reverse)
input int    InpMinSizeSharp  = 1;      // Min sharp bars
input bool   InpJustNode1     = true;   // Node 1 only

input group "Hook / money management"
input double InpInitialCapital= 100.0;  // Initial capital ($)
input double InpRiskPercent   = 10.0;   // Risk per trade (%)
input double InpRiskReward    = 2.0;    // Risk : reward
input double InpSpread        = 2.0;    // Spread ($)
input bool   InpEnableSlReduce= false;  // Shrink SL/TP distance
input double InpSlReducePct   = 20.0;   // Shrink by (%)
input bool   InpEnableRiskFree= false;  // Enable risk-free (break-even)
input double InpRiskFreeTrig  = 1.0;    // Risk-free trigger (R)

input group "Hook / window and timing"
input bool   InpDynamicStart  = true;   // Start at the beginning of the day
input int    InpDayStartHour  = 1;      // Day start hour
input int    InpDayStartMin   = 30;     // Day start minute
input int    InpDayTzShiftMin = 0;      // Day timezone shift from broker time (min)
input int    InpStartMainBar  = 4990;   // Start at bar (when dynamic start is off)
input int    InpEndMainBar    = 0;      // Stop N bars before the newest
input int    InpMinMinutes    = 10;     // Min minutes between trades
input bool   InpAllowMulti    = false;  // Allow concurrent trades

//--- object names
#define CANVAS_NAME  "RCV_canvas"
#define EDIT_NAME    "RCV_edit"
#define BTN_NAME     "RCV_apply"
#define BTN_HOME     "RCV_home"
#define BTN_STYLE    "RCV_style"

//--- layout
#define AXIS_W       74
#define PLOT_TOP     48
#define PLOT_BOT     22
#define PANEL_W      248
#define PANEL_H      38

//--- mouse flags
#define MK_LBUTTON   0x0001
#define MK_SHIFT     0x0004
#define MK_CONTROL   0x0008

//--- keys
#define VK_ESCAPE    27
#define VK_DELETE    46
#define VK_END       35
#define VK_HOME      36
#define VK_LEFT      37
#define VK_UP        38
#define VK_RIGHT     39
#define VK_DOWN      40
#define VK_D         68

//--- state
CCanvas          g_cv;
CRangeAggregator g_agg;
CHookStrategy    g_strat;
bool             g_show_dash = true;

int      g_range_ticks = 100;
ENUM_RC_STYLE g_style  = RC_BARS;
double   g_step        = 8.0;     // px per bar, fractional so zoom is smooth
double   g_shift_bars  = 10.0;    // empty space kept to the right of the last bar
int      g_scroll      = 0;       // bars hidden past the right edge
double   g_tick_size   = 0.0;
ulong    g_last_msc    = 0;
int      g_w = 0, g_h = 0;
string   g_status      = "";
bool     g_dirty       = true;

//--- vertical scale
bool     g_auto_scale  = true;
double   g_pzoom       = 1.0;     // 1.0 = fit
double   g_pshift      = 0.0;     // price offset from the fitted centre

//--- pointer
int      g_mx = -1, g_my = -1;
bool     g_cross       = false;

//--- drag
bool     g_drag        = false;
int      g_drag_zone   = 0;       // 1 = plot, 2 = price axis
int      g_drag_x0, g_drag_y0;
int      g_drag_scroll0;
double   g_drag_shift0, g_drag_zoom0;

//--- last fitted extent, needed to convert pixels back to price while dragging
double   g_vis_lo = 0.0, g_vis_hi = 0.0;
uint     g_last_paint = 0;

//--- drawing layer
CDrawings g_draw;
SView     g_view;
int      g_tool       = TOOL_CROSS;   // active toolbar cell
int      g_sel        = -1;           // selected drawing
int      g_hover      = -1;           // drawing under the cursor
int      g_tb_hover   = -1;           // toolbar cell under the cursor
int      g_tbx = 300, g_tby = 56;     // toolbar position
bool     g_tb_drag    = false;
int      g_tb_dx, g_tb_dy;
int      g_pal        = 0;            // palette index for new drawings

//--- in-progress edit
bool     g_placing    = false;        // laying down a new drawing
SDrawing g_ghost;                     // the one being laid down
int      g_edit_item  = -1;           // drawing being moved or reshaped
int      g_edit_handle= -1;           // -1 = whole body, else handle index
double   g_edit_bar0, g_edit_price0;
bool     g_lbtn_prev  = false;

//+------------------------------------------------------------------+
int   PlotR(void) { return(g_w-AXIS_W); }
int   PlotT(void) { return(PLOT_TOP);   }
int   PlotB(void) { return(g_h-PLOT_BOT); }
int   PlotH(void) { return(PlotB()-PlotT()); }
int   BarCount(void) { return(g_agg.Total()+(g_agg.HasCurrent()?1:0)); }

//--- centre x of the rightmost visible bar; everything else hangs off this,
//--- so the shift, the crosshair and the zoom anchor cannot drift apart
double AnchorX(void) { return(PlotR()-2-g_shift_bars*g_step-g_step*0.5); }

//+------------------------------------------------------------------+
datetime StartOfWeek(const datetime now)
  {
   MqlDateTime dt;
   TimeToStruct(now,dt);
   const datetime midnight = now-(dt.hour*3600+dt.min*60+dt.sec);
   return(midnight-(datetime)dt.day_of_week*86400);
  }

//+------------------------------------------------------------------+
void ClampView(void)
  {
   if(g_step<1.0)  g_step=1.0;
   if(g_step>60.0) g_step=60.0;

   if(g_pzoom<0.15) g_pzoom=0.15;
   if(g_pzoom>25.0) g_pzoom=25.0;

   if(g_shift_bars<0.0)  g_shift_bars=0.0;
   if(g_shift_bars>80.0) g_shift_bars=80.0;

   //--- the shift and any drag past the right edge share one budget, so the
   //--- last bar can never be pushed off the left of the plot
   const double max_off=MathMax(0.0,(PlotR()-40.0)/MathMax(g_step,1.0));
   if(g_shift_bars>max_off)
      g_shift_bars=max_off;

   const int total=BarCount();
   const int extra=(int)(max_off-g_shift_bars);
   if(g_scroll<-extra)  g_scroll=-extra;
   if(g_scroll>total-1) g_scroll=(total>0?total-1:0);
  }

//+------------------------------------------------------------------+
//| index of the bar drawn under pixel x (may be out of range)       |
//+------------------------------------------------------------------+
int BarAtX(const int x)
  {
   const double k=(AnchorX()-x)/g_step;          // bars left of the last one
   const int    last=BarCount()-1-g_scroll;
   return(last-(int)MathRound(k));
  }

//+------------------------------------------------------------------+
void CreatePanelObjects(void)
  {
   if(ObjectFind(0,EDIT_NAME)<0)
     {
      ObjectCreate(0,EDIT_NAME,OBJ_EDIT,0,0,0);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_XDISTANCE,66);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_YDISTANCE,14);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_XSIZE,54);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_YSIZE,20);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_BGCOLOR,C'30,34,45');
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_BORDER_COLOR,C'67,70,81');
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_COLOR,InpText);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_ALIGN,ALIGN_CENTER);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_ZORDER,10);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_SELECTABLE,false);
     }
   ObjectSetString(0,EDIT_NAME,OBJPROP_TEXT,IntegerToString(g_range_ticks));

   if(ObjectFind(0,BTN_NAME)<0)
     {
      ObjectCreate(0,BTN_NAME,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_XDISTANCE,126);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_YDISTANCE,14);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_XSIZE,54);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_YSIZE,20);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_BGCOLOR,C'41,98,255');
      ObjectSetInteger(0,BTN_NAME,OBJPROP_BORDER_COLOR,C'41,98,255');
      ObjectSetInteger(0,BTN_NAME,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_ZORDER,10);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,BTN_NAME,OBJPROP_TEXT,"Apply");
     }
   ObjectSetInteger(0,BTN_NAME,OBJPROP_STATE,false);

   //--- style toggle, Bars <-> Candles
   if(ObjectFind(0,BTN_STYLE)<0)
     {
      ObjectCreate(0,BTN_STYLE,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_XDISTANCE,186);
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_YDISTANCE,14);
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_XSIZE,60);
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_YSIZE,20);
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_BGCOLOR,C'30,34,45');
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_BORDER_COLOR,C'67,70,81');
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_COLOR,InpText);
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_ZORDER,10);
      ObjectSetInteger(0,BTN_STYLE,OBJPROP_SELECTABLE,false);
     }
   ObjectSetInteger(0,BTN_STYLE,OBJPROP_STATE,false);
   ObjectSetString(0,BTN_STYLE,OBJPROP_TEXT,g_style==RC_BARS?"Bars":"Candles");

   //--- "back to realtime", shown only when the view is scrolled back
   if(ObjectFind(0,BTN_HOME)<0)
     {
      ObjectCreate(0,BTN_HOME,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,BTN_HOME,OBJPROP_CORNER,CORNER_RIGHT_LOWER);
      ObjectSetInteger(0,BTN_HOME,OBJPROP_XDISTANCE,AXIS_W+34);
      ObjectSetInteger(0,BTN_HOME,OBJPROP_YDISTANCE,34);
      ObjectSetInteger(0,BTN_HOME,OBJPROP_XSIZE,26);
      ObjectSetInteger(0,BTN_HOME,OBJPROP_YSIZE,22);
      ObjectSetInteger(0,BTN_HOME,OBJPROP_BGCOLOR,C'30,34,45');
      ObjectSetInteger(0,BTN_HOME,OBJPROP_BORDER_COLOR,C'67,70,81');
      ObjectSetInteger(0,BTN_HOME,OBJPROP_COLOR,InpText);
      ObjectSetInteger(0,BTN_HOME,OBJPROP_FONTSIZE,10);
      ObjectSetInteger(0,BTN_HOME,OBJPROP_ZORDER,10);
      ObjectSetInteger(0,BTN_HOME,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,BTN_HOME,OBJPROP_TEXT,">|");
     }
   ObjectSetInteger(0,BTN_HOME,OBJPROP_STATE,false);
  }

//+------------------------------------------------------------------+
void SyncHomeButton(void)
  {
   const bool show=(g_scroll!=0 || !g_auto_scale);
   ObjectSetInteger(0,BTN_HOME,OBJPROP_TIMEFRAMES,show?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
  }

//+------------------------------------------------------------------+
bool BuildCanvas(void)
  {
   g_w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   g_h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(g_w<80 || g_h<80)
      return(false);

   g_cv.Destroy();
   if(!g_cv.CreateBitmapLabel(0,0,CANVAS_NAME,0,0,g_w,g_h,COLOR_FORMAT_XRGB_NOALPHA))
      return(false);

   ObjectSetInteger(0,CANVAS_NAME,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,CANVAS_NAME,OBJPROP_ZORDER,0);
   ObjectSetInteger(0,CANVAS_NAME,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,CANVAS_NAME,OBJPROP_BACK,false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Copies the inputs into the strategy. Called before every rebuild  |
//| so a re-attach with new settings takes effect immediately.        |
//+------------------------------------------------------------------+
void ConfigureStrategy(void)
  {
   SHookSettings s;
   HookSettingsDefaults(s);

   s.max_dollar_hook      = InpMaxDollarHook;
   s.max_pullback_hook    = InpMinPullback;
   s.min_hook_bars        = InpMinHookBars;
   s.max_hook_bars        = InpMaxHookBars;
   s.look_back_len        = InpLookBackLen;
   s.min_size_sharp       = InpMinSizeSharp;
   s.just_node_1          = InpJustNode1;

   s.initial_capital      = InpInitialCapital;
   s.risk_percent         = InpRiskPercent;
   s.risk_reward          = InpRiskReward;
   s.spread               = InpSpread;
   s.enable_sl_reduce     = InpEnableSlReduce;
   s.sl_reduce_percent    = InpSlReducePct;
   s.enable_risk_free     = InpEnableRiskFree;
   s.risk_free_trigger    = InpRiskFreeTrig;

   s.enable_dynamic_start = InpDynamicStart;
   s.day_start_hour       = InpDayStartHour;
   s.day_start_minute     = InpDayStartMin;
   s.day_tz_shift_min     = InpDayTzShiftMin;
   s.start_main_candle    = InpStartMainBar;
   s.end_main_candle      = InpEndMainBar;
   s.min_minutes          = InpMinMinutes;
   s.allow_multi_trade    = InpAllowMulti;

   g_strat.Configure(s);
  }

//+------------------------------------------------------------------+
void Rebuild(void)
  {
   const uint t0=GetTickCount();

   g_tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(g_tick_size<=0.0)
      g_tick_size=_Point;

   g_agg.Init(g_range_ticks*g_tick_size,g_tick_size);
   g_scroll=0;
   g_last_msc=0;
   g_auto_scale=true;
   g_pzoom=1.0;
   g_pshift=0.0;

   const datetime from=StartOfWeek(TimeCurrent());
   const datetime to  =TimeCurrent()+60;

   long   ticks_used=0;
   string src="ticks";

   if(InpUseTicks)
     {
      MqlTick buf[];
      const int CHUNK=6*3600;                       // 6h chunks, bounds memory

      for(datetime a=from; a<to; a+=CHUNK)
        {
         const datetime b=(datetime)MathMin((long)a+CHUNK,(long)to);
         const int n=CopyTicksRange(_Symbol,buf,COPY_TICKS_INFO,
                                    (ulong)a*1000,(ulong)b*1000);
         for(int i=0;i<n;i++)
           {
            const double p=buf[i].bid;
            if(p>0.0)
              {
               g_agg.AddTick(p,buf[i].time,1);
               g_last_msc=buf[i].time_msc;
               ticks_used++;
              }
           }
        }
     }

   if(ticks_used==0)                                 // no tick history -> M1 path guess
     {
      src="M1";
      MqlRates rates[];
      const int n=CopyRates(_Symbol,PERIOD_M1,from,to,rates);
      for(int i=0;i<n;i++)
         g_agg.AddM1(rates[i]);
     }

   g_draw.SetFile(_Symbol,g_range_ticks);
   g_draw.Load();
   g_sel=-1;

   //--- replay the whole history through the strategy in one pass
   string hook="off";
   if(InpHookOn)
     {
      ConfigureStrategy();
      g_strat.Reset();
      g_strat.ProcessNew();
      hook=StringFormat("trades=%d",
                        g_strat.CountTP()+g_strat.CountSL()+g_strat.CountRF());
     }

   g_status=StringFormat("%s  R=%d (%.*f)  bars=%d  src=%s  hook %s  %dms",
                         _Symbol,g_range_ticks,_Digits,g_range_ticks*g_tick_size,
                         g_agg.Total(),src,hook,(int)(GetTickCount()-t0));
   g_dirty=true;
  }

//+------------------------------------------------------------------+
void PumpLive(void)
  {
   if(g_last_msc==0)
     {
      MqlTick t;
      if(SymbolInfoTick(_Symbol,t) && t.bid>0.0)
        {
         g_agg.AddTick(t.bid,t.time,1);
         g_last_msc=t.time_msc;
         g_dirty=true;
        }
      return;
     }

   MqlTick buf[];
   const int n=CopyTicksRange(_Symbol,buf,COPY_TICKS_INFO,g_last_msc+1,0);
   for(int i=0;i<n;i++)
     {
      if(buf[i].bid>0.0)
        {
         g_agg.AddTick(buf[i].bid,buf[i].time,1);
         g_dirty=true;
        }
      g_last_msc=buf[i].time_msc;
     }
  }

//+------------------------------------------------------------------+
double NiceStep(const double raw)
  {
   if(raw<=0.0)
      return(g_tick_size>0.0?g_tick_size:1.0);

   const double mag=MathPow(10,MathFloor(MathLog10(raw)));
   const double n  =raw/mag;

   if(n<1.5) return(1.0*mag);
   if(n<3.0) return(2.0*mag);
   if(n<7.0) return(5.0*mag);
   return(10.0*mag);
  }

//+------------------------------------------------------------------+
void DashH(const int x1,const int x2,const int y,const uint clr,const int on=4,const int off=4)
  {
   for(int x=x1;x<x2;x+=on+off)
      g_cv.LineHorizontal(x,(int)MathMin(x+on,x2),y,clr);
  }

//+------------------------------------------------------------------+
void DashV(const int y1,const int y2,const int x,const uint clr,const int on=4,const int off=4)
  {
   for(int y=y1;y<y2;y+=on+off)
      g_cv.LineVertical(x,y,(int)MathMin(y+on,y2),clr);
  }

//+------------------------------------------------------------------+
//| Strokes with a width, since CCanvas lines are always 1px.        |
//+------------------------------------------------------------------+
void VLine(const int x,const int y1,const int y2,const int w,const uint clr)
  {
   if(w<=1) { g_cv.LineVertical(x,y1,y2,clr); return; }
   g_cv.FillRectangle(x-(w-1)/2,y1,x+w/2,y2,clr);
  }

//+------------------------------------------------------------------+
void HLine(const int x1,const int x2,const int y,const int w,const uint clr)
  {
   if(w<=1) { g_cv.LineHorizontal(x1,x2,y,clr); return; }
   g_cv.FillRectangle(x1,y-(w-1)/2,x2,y+w/2,clr);
  }

//+------------------------------------------------------------------+
void PriceTag(const int y,const string txt,const uint bg,const uint fg)
  {
   if(y<PlotT()-10 || y>PlotB()+10)
      return;

   g_cv.FillRectangle(PlotR()+1,y-9,g_w,y+9,bg);
   g_cv.TextOut(PlotR()+6,y-7,txt,fg);
  }

//+------------------------------------------------------------------+
void Render(void)
  {
   if(g_w<80 || g_h<80)
      return;

   ClampView();

   const int plot_r=PlotR(), plot_t=PlotT(), plot_b=PlotB(), plot_h=PlotH();
   if(plot_h<40 || plot_r<40)
      return;

   g_cv.Erase(ColorToARGB(InpBg,255));
   g_cv.FontSet("Tahoma",-100);

   const int done  = g_agg.Total();
   SRangeBar cur;
   const bool has_cur = g_agg.Current(cur);
   const int  total   = done+(has_cur?1:0);

   if(total<=0)
     {
      g_cv.TextOut(12,plot_t+20,"no data",ColorToARGB(InpText,255));
      g_cv.Update();
      return;
     }

   int nvis=(int)MathCeil(AnchorX()/g_step)+2;    // enough to reach the left edge
   if(nvis<1) nvis=1;

   //--- last is a slot index and may sit past the newest bar when the view is
   //--- dragged beyond the right edge; last_real is what actually has data
   const int last      = total-1-g_scroll;
   const int last_real = MathMin(last,total-1);
   int       first     = last-nvis+1;
   if(first<0) first=0;

   //--- fitted price extent
   double lo=DBL_MAX, hi=-DBL_MAX;
   for(int i=first;i<=last_real;i++)
     {
      SRangeBar b;
      if(i<done) { if(!g_agg.Get(i,b)) continue; }
      else       { b=cur; }

      if(b.high>hi) hi=b.high;
      if(b.low <lo) lo=b.low;
     }
   if(lo>hi)
     {
      g_cv.Update();
      return;
     }

   double pad=(hi-lo)*0.08+g_tick_size;
   double c  =(hi+lo)*0.5+g_pshift;
   double half=((hi-lo)*0.5+pad)/g_pzoom;
   hi=c+half; lo=c-half;

   g_vis_hi=hi; g_vis_lo=lo;
   const double span=hi-lo;
   if(span<=0.0)
     {
      g_cv.Update();
      return;
     }

   //--- the mapping every overlay is projected through. Fixed here, before
   //--- anything is painted, because the strategy tints go under the bars.
   g_view.plot_r   = plot_r;
   g_view.plot_t   = plot_t;
   g_view.plot_b   = plot_b;
   g_view.plot_h   = plot_h;
   g_view.hi       = hi;
   g_view.lo       = lo;
   g_view.span     = span;
   g_view.step     = g_step;
   g_view.anchor_x = AnchorX();
   g_view.last_slot= last;

   //--- grid + price axis
   const double gstep=NiceStep(span/6.0);
   for(double p=MathCeil(lo/gstep)*gstep; p<=hi; p+=gstep)
     {
      const int y=plot_t+(int)((hi-p)/span*plot_h);
      g_cv.LineHorizontal(0,plot_r,y,ColorToARGB(InpGrid,255));
      g_cv.TextOut(plot_r+6,y-7,DoubleToString(p,_Digits),ColorToARGB(InpText,255));
     }
   g_cv.LineVertical(plot_r,0,g_h,ColorToARGB(InpGrid,255));

   //--- risk bands go down first, so the bars paint over them and the price
   //--- action inside a position stays visible
   if(InpHookOn && InpHookDraw)
      HkRenderFills(GetPointer(g_cv),g_view,GetPointer(g_strat),InpBg);

   //--- bars
   const int lw    =(g_step>=14.0 ? 2 : 1);                    // stroke width
   const int tick_w=(int)MathMax(1.0,MathRound(g_step*0.5)-1.0); // open/close nub
   const int half_w=(int)MathMax(1.0,MathRound(g_step)-3.0)/2;   // candle body

   for(int i=first;i<=last_real;i++)
     {
      SRangeBar b;
      const bool forming=(i>=done);
      if(forming) b=cur;
      else if(!g_agg.Get(i,b)) continue;

      const int cx=(int)MathRound(AnchorX()-(last-i)*g_step);
      if(cx<0 || cx>plot_r) continue;

      const int yh=plot_t+(int)((hi-b.high )/span*plot_h);
      const int yl=plot_t+(int)((hi-b.low  )/span*plot_h);
      const int yo=plot_t+(int)((hi-b.open )/span*plot_h);
      const int yc=plot_t+(int)((hi-b.close)/span*plot_h);

      const uint arg=ColorToARGB(b.close>=b.open?InpBull:InpBear,255);

      if(g_style==RC_BARS)
        {
         //--- high-low stem, open nub to the left, close nub to the right
         VLine(cx,yh,yl,lw,arg);
         HLine(cx-tick_w,cx,yo,lw,arg);
         HLine(cx,cx+tick_w+1,yc,lw,arg);

         if(forming)
            g_cv.Rectangle(cx-tick_w-2,yh-2,cx+tick_w+3,yl+2,
                           ColorToARGB(clrWhite,255));
        }
      else
        {
         g_cv.LineVertical(cx,yh,yl,arg);

         int y1=MathMin(yo,yc), y2=MathMax(yo,yc);
         if(y2-y1<1) y2=y1+1;
         if(half_w>0) g_cv.FillRectangle(cx-half_w,y1,cx+half_w,y2,arg);

         if(forming)
            g_cv.Rectangle(cx-half_w-1,y1-1,cx+half_w+1,y2+1,
                           ColorToARGB(clrWhite,255));
        }
     }

   //--- forming bar: current close level
   if(has_cur && g_scroll<=0)
     {
      const int yc=plot_t+(int)((hi-cur.close)/span*plot_h);
      if(yc>plot_t && yc<plot_b)
        {
         DashH(0,plot_r,yc,ColorToARGB(InpText,255),3,4);
         PriceTag(yc,DoubleToString(cur.close,_Digits),
                  ColorToARGB(cur.close>=cur.open?InpBull:InpBear,255),
                  ColorToARGB(clrWhite,255));
        }
     }

   //--- entry, stop and target ride above the bars, under the user's drawings
   if(InpHookOn && InpHookDraw)
      HkRenderAll(GetPointer(g_cv),g_view,GetPointer(g_strat),_Digits,InpBg,InpText);

   g_draw.RenderAll(g_view,g_sel,_Digits);

   if(g_hover>=0 && g_hover!=g_sel)                // handles hint that it is grabbable
      g_draw.RenderOne(g_view,g_hover,true,_Digits);

   if(g_placing)                                   // live preview of the new shape
     {
      const int gi=g_draw.Add(g_ghost);
      g_draw.RenderOne(g_view,gi,false,_Digits);
      g_draw.Remove(gi);
     }

   //--- crosshair
   SRangeBar hb;
   ZeroMemory(hb);
   bool hb_ok=false;
   int  hover=-1;

   if(g_cross && g_mx>=0 && g_mx<plot_r && g_my>plot_t && g_my<plot_b)
     {
      DashV(plot_t,plot_b,g_mx,ColorToARGB(C'110,115,130',255),4,4);
      DashH(0,plot_r,g_my,ColorToARGB(C'110,115,130',255),4,4);

      const double pc=hi-(double)(g_my-plot_t)/plot_h*span;
      PriceTag(g_my,DoubleToString(pc,_Digits),
               ColorToARGB(C'80,86,102',255),ColorToARGB(clrWhite,255));

      hover=BarAtX(g_mx);
      if(hover>=0 && hover<total)
        {
         if(hover>=done && has_cur) { hb=cur;   hb_ok=true; }
         else                       { hb_ok=g_agg.Get(hover,hb); }
        }
     }

   if(!hb_ok)                                        // fall back to the rightmost bar
     {
      if(last_real>=done && has_cur) { hb=cur; hb_ok=true; }
      else if(last_real>=0)          { hb_ok=g_agg.Get(last_real,hb); }
     }

   //--- header, TradingView style
   if(hb_ok)
     {
      const uint hc=ColorToARGB(hb.close>=hb.open?InpBull:InpBear,255);
      int x=PANEL_W+16;
      const string keys[4]={"O","H","L","C"};
      const double vals[4]={hb.open,hb.high,hb.low,hb.close};

      for(int k=0;k<4;k++)
        {
         g_cv.TextOut(x,10,keys[k],ColorToARGB(InpText,255));
         x+=12;
         const string s=DoubleToString(vals[k],_Digits);
         g_cv.TextOut(x,10,s,hc);
         x+=(int)g_cv.TextWidth(s)+10;
        }

      g_cv.TextOut(x,10,StringFormat("Vol %I64d",hb.volume),ColorToARGB(InpText,255));
      x+=76;
      g_cv.TextOut(x,10,TimeToString(hb.time_close,TIME_DATE|TIME_MINUTES),
                   ColorToARGB(C'120,123,134',255));
     }

   //--- time label under the crosshair
   if(hover>=0 && hover<total)
     {
      SRangeBar tb;
      ZeroMemory(tb);
      bool ok;
      if(hover>=done && has_cur) { tb=cur; ok=true; }
      else                       { ok=g_agg.Get(hover,tb); }

      if(ok)
        {
         const string ts=TimeToString(tb.time_close,TIME_MINUTES|TIME_SECONDS);
         const int    tw=(int)g_cv.TextWidth(ts);
         g_cv.FillRectangle(g_mx-tw/2-6,g_h-20,g_mx+tw/2+6,g_h-2,
                            ColorToARGB(C'80,86,102',255));
         g_cv.TextOut(g_mx-tw/2,g_h-18,ts,ColorToARGB(clrWhite,255));
        }
     }

   //--- panel chrome (the input box is a real OBJ_EDIT on top)
   g_cv.FillRectangle(6,6,6+PANEL_W,6+PANEL_H,ColorToARGB(C'30,34,45',255));
   g_cv.Rectangle(6,6,6+PANEL_W,6+PANEL_H,ColorToARGB(C'67,70,81',255));
   g_cv.TextOut(14,16,"Range",ColorToARGB(InpText,255));

   //--- toolbar, on top of the plot
   TbRender(GetPointer(g_cv),g_tbx,g_tby,g_tool==TOOL_CROSS?0:-1,g_tb_hover);
   if(g_tool!=TOOL_CROSS)
     {
      for(int i=0;i<=TB_N;i++)
         if(TB_TOOLS[i]==g_tool)
           {
            const int cx=g_tbx+TB_GRIP+TB_PAD+i*TB_CELL+TB_CELL/2;
            const int cy=g_tby+TB_PAD+TB_CELL/2;
            g_cv.Rectangle(cx-12,cy-12,cx+12,cy+12,ColorToARGB(C'41,98,255',255));
            break;
           }
     }

   //--- properties strip for the selected drawing
   if(g_sel>=0)
     {
      SDrawing sd;
      if(g_draw.Get(g_sel,sd))
        {
         const int sx=g_tbx, sy=g_tby+TbHeight()+4;
         g_cv.FillRectangle(sx,sy,sx+108,sy+24,ColorToARGB(C'30,34,45',255));
         g_cv.Rectangle(sx,sy,sx+108,sy+24,ColorToARGB(C'67,70,81',255));
         g_cv.FillRectangle(sx+6,sy+6,sx+24,sy+18,ColorToARGB(sd.clr,255));          // colour swatch
         g_cv.TextOut(sx+32,sy+5,StringFormat("w%d",sd.width),
                      ColorToARGB(InpText,255));
         TbGlyph(GetPointer(g_cv),-1,sx+86,sy+12,ColorToARGB(C'239,83,80',255));
        }
     }

   //--- status
   g_cv.TextOut(8,g_h-16,g_status,ColorToARGB(C'120,123,134',255));

   const string hint=(g_auto_scale?"auto":"manual");
   g_cv.TextOut(plot_r-150,g_h-16,
                StringFormat("zoom %.1fpx  scale %s",g_step,hint),
                ColorToARGB(C'120,123,134',255));

   //--- dashboard last, so it sits above everything else
   if(InpHookOn && g_show_dash)
     {
      const double lastc=(has_cur?cur.close:(hb_ok?hb.close:0.0));
      DashRender(GetPointer(g_cv),g_view,GetPointer(g_strat),
                 _Digits,g_tick_size,lastc,InpHookDashFa,InpText,InpGrid);
     }

   g_cv.Update();
   g_last_paint=GetTickCount();
  }

//+------------------------------------------------------------------+
void Repaint(void)
  {
   Render();
   SyncHomeButton();
   ChartRedraw();
   g_dirty=false;
  }

//+------------------------------------------------------------------+
void ResetView(void)
  {
   g_scroll=0;
   g_auto_scale=true;
   g_pzoom=1.0;
   g_pshift=0.0;
   g_shift_bars=(InpRightShift>=0?(double)InpRightShift:10.0);
  }

//+------------------------------------------------------------------+
//| How many clicks-worth of geometry a tool needs.                  |
//+------------------------------------------------------------------+
bool ToolIsTwoPoint(const int t)
  {
   return(t==TOOL_TREND || t==TOOL_RAY  || t==TOOL_RECT ||
          t==TOOL_FIB   || t==TOOL_MEASURE ||
          t==TOOL_LONG  || t==TOOL_SHORT);
  }

//+------------------------------------------------------------------+
bool InPanel(const int x,const int y)
  {
   return(x>=6 && x<=6+PANEL_W && y>=6 && y<=6+PANEL_H);
  }

//+------------------------------------------------------------------+
bool InToolbar(const int x,const int y)
  {
   return(x>=g_tbx && x<=g_tbx+TbWidth() && y>=g_tby && y<=g_tby+TbHeight());
  }

//+------------------------------------------------------------------+
//| Seed a new drawing from the press point.                         |
//+------------------------------------------------------------------+
void BeginPlacing(const double bar,const double price)
  {
   g_ghost.type  =g_tool;
   g_ghost.bar1  =bar;   g_ghost.price1=price;
   g_ghost.bar2  =bar;   g_ghost.price2=price;
   g_ghost.price3=price;
   g_ghost.clr   =RC_PALETTE[g_pal];
   g_ghost.width =2;
   g_ghost.text  =(g_tool==TOOL_TEXT||g_tool==TOOL_NOTE)?"Text":"";
   g_ghost.alive =true;
   g_placing     =true;
  }

//+------------------------------------------------------------------+
//| Finish a placement, discarding degenerate one-pixel shapes.      |
//+------------------------------------------------------------------+
void EndPlacing(void)
  {
   if(!g_placing)
      return;

   g_placing=false;

   if(ToolIsTwoPoint(g_ghost.type))
     {
      const bool tiny=(MathAbs(g_ghost.bar2-g_ghost.bar1)<0.5 &&
                       MathAbs(g_ghost.price2-g_ghost.price1)<g_tick_size);
      if(tiny)
        {
         //--- a plain click, not a drag: give it a usable default size
         g_ghost.bar2  =g_ghost.bar1+12;
         g_ghost.price2=g_ghost.price1+(g_vis_hi-g_vis_lo)*0.15;
        }

      if(g_ghost.type==TOOL_LONG || g_ghost.type==TOOL_SHORT)
        {
         const double r=MathAbs(g_ghost.price2-g_ghost.price1);
         const double d=(g_ghost.type==TOOL_LONG?1.0:-1.0);
         g_ghost.price2=g_ghost.price1+d*r*2.0;    // target
         g_ghost.price3=g_ghost.price1-d*r;        // stop
        }
     }

   g_sel=g_draw.Add(g_ghost);
   g_draw.Save();
   g_tool=TOOL_CROSS;                              // one shape per pick, like TV
  }

//+------------------------------------------------------------------+
void DeleteSelected(void)
  {
   if(g_sel<0)
      return;

   g_draw.Remove(g_sel);
   g_draw.Save();
   g_sel=-1;
  }

//+------------------------------------------------------------------+
//| Horizontal zoom that keeps the bar under the cursor in place.    |
//+------------------------------------------------------------------+
void ZoomAt(const int px,const double factor)
  {
   const int    x  = (px>=0 && px<PlotR()) ? px : (int)AnchorX();
   const double k0 = (AnchorX()-x)/g_step;

   g_step*=factor;
   ClampView();

   const double k1=(AnchorX()-x)/g_step;
   g_scroll+=(int)MathRound(k0-k1);
   ClampView();
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_range_ticks=(InpRange>0?InpRange:100);
   g_step       =(InpBarStep>1?(double)InpBarStep:8.0);
   g_shift_bars =(InpRightShift>=0?(double)InpRightShift:10.0);
   g_style      =InpStyle;

   ChartSetInteger(0,CHART_EVENT_MOUSE_WHEEL,true);
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
   ChartSetInteger(0,CHART_MOUSE_SCROLL,false);      // stop the chart underneath from moving
   ChartSetInteger(0,CHART_FOREGROUND,false);

   if(!BuildCanvas())
      return(INIT_FAILED);

   g_draw.Attach(GetPointer(g_cv));
   g_strat.Attach(GetPointer(g_agg));
   g_show_dash=InpHookDash;

   CreatePanelObjects();
   Rebuild();
   Repaint();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_draw.Save();
   g_cv.Destroy();
   ObjectDelete(0,EDIT_NAME);
   ObjectDelete(0,BTN_NAME);
   ObjectDelete(0,BTN_HOME);
   ObjectDelete(0,BTN_STYLE);
   ObjectDelete(0,CANVAS_NAME);
   ChartSetInteger(0,CHART_MOUSE_SCROLL,true);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   PumpLive();

   //--- every range bar that just closed is stepped through the strategy,
   //--- in order, exactly once - the forming bar is never evaluated
   if(InpHookOn && g_strat.ProcessNew())
      g_dirty=true;

   if(g_dirty && GetTickCount()-g_last_paint>=25)     // cap live repaints at ~40fps
      Repaint();

   return(rates_total);
  }

//+------------------------------------------------------------------+
void ApplyRangeFromEdit(void)
  {
   const int v=(int)StringToInteger(ObjectGetString(0,EDIT_NAME,OBJPROP_TEXT));
   if(v>0 && v!=g_range_ticks)
     {
      g_range_ticks=v;
      Rebuild();
     }
   ObjectSetString(0,EDIT_NAME,OBJPROP_TEXT,IntegerToString(g_range_ticks));
   Repaint();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   switch(id)
     {
      case CHARTEVENT_CHART_CHANGE:
        {
         const int w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
         const int h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
         if(w!=g_w || h!=g_h)
           {
            BuildCanvas();
            g_draw.Attach(GetPointer(g_cv));
            Repaint();
           }
         return;
        }

      case CHARTEVENT_OBJECT_CLICK:
        {
         if(sparam==BTN_NAME)
           {
            ObjectSetInteger(0,BTN_NAME,OBJPROP_STATE,false);
            ApplyRangeFromEdit();
           }
         else if(sparam==BTN_HOME)
           {
            ObjectSetInteger(0,BTN_HOME,OBJPROP_STATE,false);
            ResetView();
            Repaint();
           }
         else if(sparam==BTN_STYLE)
           {
            ObjectSetInteger(0,BTN_STYLE,OBJPROP_STATE,false);
            g_style=(g_style==RC_BARS?RC_CANDLES:RC_BARS);
            ObjectSetString(0,BTN_STYLE,OBJPROP_TEXT,g_style==RC_BARS?"Bars":"Candles");
            Repaint();
           }
         return;
        }

      case CHARTEVENT_OBJECT_ENDEDIT:
        {
         if(sparam==EDIT_NAME)
            ApplyRangeFromEdit();
         return;
        }

      //--- lparam packs coords and modifier flags, dparam carries the delta
      case CHARTEVENT_MOUSE_WHEEL:
        {
         const int x     = (int)(short)lparam;
         const int flags = (int)(lparam>>32);
         const int delta = (int)dparam;
         if(delta==0)
            return;

         const bool ctrl  = ((flags&MK_CONTROL)!=0);
         const bool shift = ((flags&MK_SHIFT)!=0);

         if(ctrl)                                     // vertical zoom
           {
            g_auto_scale=false;
            g_pzoom*=(delta>0?1.15:1.0/1.15);
           }
         else if(shift)                               // horizontal pan
           {
            const int stepbars=(int)MathMax(1,MathRound(4.0*40.0/g_step));
            g_scroll+=(delta>0?stepbars:-stepbars);
           }
         else                                         // horizontal zoom at cursor
            ZoomAt(x,(delta>0?1.2:1.0/1.2));

         Repaint();
         return;
        }

      //--- lparam = X, dparam = Y, sparam = button flags
      case CHARTEVENT_MOUSE_MOVE:
        {
         const int x     = (int)lparam;
         const int y     = (int)dparam;
         const int flags = (int)StringToInteger(sparam);
         const bool down = ((flags&MK_LBUTTON)!=0);
         const bool press  = ( down && !g_lbtn_prev);
         const bool release= (!down &&  g_lbtn_prev);
         g_lbtn_prev=down;

         g_mx=x; g_my=y;
         g_cross=(x>=0 && x<g_w && y>=0 && y<g_h);

         const double mbar  =XToBar  (g_view,x);
         const double mprice=YToPrice(g_view,y);

         g_tb_hover=-1;
         const int cell=TbCellAt(g_tbx,g_tby,x,y);
         if(cell>=0)
            g_tb_hover=cell;

         //--- 1. toolbar
         if(press && cell!=-1)
           {
            if(cell==-2)                                  // grip: start dragging it
              {
               g_tb_drag=true;
               g_tb_dx=x-g_tbx; g_tb_dy=y-g_tby;
              }
            else if(TB_TOOLS[cell]<0)                     // trash cell
               DeleteSelected();
            else
              {
               g_tool=TB_TOOLS[cell];
               g_sel=-1;
              }
            Repaint();
            return;
           }

         if(g_tb_drag)
           {
            if(down)
              {
               g_tbx=x-g_tb_dx; g_tby=y-g_tb_dy;
               if(g_tbx<0) g_tbx=0;
               if(g_tby<0) g_tby=0;
               if(g_tbx>g_w-TbWidth())  g_tbx=g_w-TbWidth();
               if(g_tby>g_h-TbHeight()) g_tby=g_h-TbHeight();
               Repaint();
              }
            else
               g_tb_drag=false;
            return;
           }

         //--- 2. properties strip of the selected drawing
         if(press && g_sel>=0)
           {
            const int sx=g_tbx, sy=g_tby+TbHeight()+4;
            if(x>=sx && x<=sx+108 && y>=sy && y<=sy+24)
              {
               SDrawing sd;
               if(g_draw.Get(g_sel,sd))
                 {
                  if(x<=sx+24)                             // cycle colour
                    {
                     g_pal=(g_pal+1)%8;
                     sd.clr=RC_PALETTE[g_pal];
                    }
                  else if(x<=sx+70)                        // cycle width
                     sd.width=(sd.width%4)+1;
                  else                                     // delete
                    {
                     DeleteSelected();
                     Repaint();
                     return;
                    }
                  g_draw.Set(g_sel,sd);
                  g_draw.Save();
                 }
               Repaint();
               return;
              }
           }

         const bool in_plot=(y>PlotT() && y<PlotB() && x<PlotR() &&
                             !InPanel(x,y) && !InToolbar(x,y));

         //--- 3. laying down a new drawing
         if(g_placing)
           {
            if(ToolIsTwoPoint(g_ghost.type))
              {
               g_ghost.bar2=mbar; g_ghost.price2=mprice;
              }
            if(release)
               EndPlacing();
            Repaint();
            return;
           }

         if(press && in_plot && g_tool!=TOOL_CROSS)
           {
            BeginPlacing(mbar,mprice);
            if(!ToolIsTwoPoint(g_tool))                    // single-click tools
               EndPlacing();
            Repaint();
            return;
           }

         //--- 4. editing an existing drawing
         if(g_edit_item>=0)
           {
            if(down)
              {
               if(g_edit_handle>=0)
                  g_draw.MoveHandle(g_edit_item,g_edit_handle,mbar,mprice);
               else
                  g_draw.MoveBy(g_edit_item,mbar-g_edit_bar0,mprice-g_edit_price0);

               g_edit_bar0=mbar; g_edit_price0=mprice;
               Repaint();
              }
            else
              {
               g_edit_item=-1; g_edit_handle=-1;
               g_draw.Save();
              }
            return;
           }

         if(press && in_plot && g_tool==TOOL_CROSS)
           {
            //--- a handle of the current selection wins over everything
            int h=(g_sel>=0)?g_draw.HitHandle(g_view,g_sel,x,y):-1;
            if(h>=0)
              {
               g_edit_item=g_sel; g_edit_handle=h;
               g_edit_bar0=mbar;  g_edit_price0=mprice;
               return;
              }

            const int hit=g_draw.HitTest(g_view,x,y);
            if(hit>=0)
              {
               g_sel=hit;
               g_edit_item=hit; g_edit_handle=-1;
               g_edit_bar0=mbar; g_edit_price0=mprice;
               Repaint();
               return;
              }

            g_sel=-1;                                      // clicked empty space
           }

         g_hover=(g_tool==TOOL_CROSS && in_plot)? g_draw.HitTest(g_view,x,y) : -1;

         //--- 5. nothing drawing-related: fall through to panning the chart
         if(down && !g_drag && in_plot)
           {
            g_drag=true; g_drag_zone=1;
            g_drag_x0=x; g_drag_y0=y;
            g_drag_scroll0=g_scroll;
            g_drag_shift0 =g_pshift;
            g_drag_zoom0  =g_pzoom;
           }
         else if(down && !g_drag && x>=PlotR())
           {
            g_drag=true; g_drag_zone=2;
            g_drag_x0=x; g_drag_y0=y;
            g_drag_scroll0=g_scroll;
            g_drag_shift0 =g_pshift;
            g_drag_zoom0  =g_pzoom;
           }
         else if(!down && g_drag)
           {
            g_drag=false;
            g_drag_zone=0;
           }

         if(g_drag && g_drag_zone==1)
           {
            g_scroll=g_drag_scroll0+(int)MathRound((x-g_drag_x0)/g_step);

            const int dy=y-g_drag_y0;
            if(MathAbs(dy)>2 && PlotH()>0)
              {
               g_auto_scale=false;
               g_pshift=g_drag_shift0+(double)dy/PlotH()*(g_vis_hi-g_vis_lo);
              }
           }
         else if(g_drag && g_drag_zone==2)
           {
            g_auto_scale=false;
            g_pzoom=g_drag_zoom0*MathExp((g_drag_y0-y)/140.0);
           }

         if(GetTickCount()-g_last_paint>=16)
            Repaint();
         return;
        }

      case CHARTEVENT_KEYDOWN:
        {
         const int total=BarCount();
         switch((int)lparam)
           {
            case VK_LEFT:  g_scroll+=(int)MathMax(1,MathRound(40.0/g_step)); break;
            case VK_RIGHT: g_scroll-=(int)MathMax(1,MathRound(40.0/g_step)); break;
            case VK_HOME:  g_scroll=total-1;                                 break;
            case VK_END:   ResetView();                                      break;
            case VK_UP:    g_auto_scale=false; g_pzoom*=1.15;                break;
            case VK_DOWN:  g_auto_scale=false; g_pzoom/=1.15;                break;
            case VK_DELETE: DeleteSelected();                                break;
            case VK_ESCAPE: g_placing=false; g_sel=-1; g_tool=TOOL_CROSS;    break;
            case VK_D:     g_show_dash=!g_show_dash;                         break;
            default: return;
           }
         Repaint();
         return;
        }
     }
  }
//+------------------------------------------------------------------+
