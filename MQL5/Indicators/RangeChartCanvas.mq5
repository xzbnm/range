//+------------------------------------------------------------------+
//|                                            RangeChartCanvas.mq5 |
//|            TradingView-style range chart rendered on a CCanvas   |
//+------------------------------------------------------------------+
#property copyright "Range Chart"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#include <Canvas\Canvas.mqh>
#include <RangeChart\RangeAggregator.mqh>

//--- inputs
input int    InpRange     = 100;                  // Range (ticks)
input int    InpBarStep   = 8;                    // Bar spacing (px)
input bool   InpUseTicks  = true;                 // Seed from real ticks (else M1)
input color  InpBull      = C'38,166,154';        // Bullish
input color  InpBear      = C'239,83,80';         // Bearish
input color  InpBg        = C'19,23,34';          // Background
input color  InpGrid      = C'42,46,57';          // Grid
input color  InpText      = C'209,212,220';       // Text

//--- layout
#define CANVAS_NAME  "RCV_canvas"
#define EDIT_NAME    "RCV_edit"
#define BTN_NAME     "RCV_apply"
#define AXIS_W       70
#define PLOT_TOP     46
#define PLOT_BOT     20
#define PANEL_W      168
#define PANEL_H      38

//--- state
CCanvas          g_cv;
CRangeAggregator g_agg;

int      g_range_ticks = 100;
int      g_step        = 8;
int      g_scroll      = 0;        // bars hidden past the right edge
double   g_tick_size   = 0.0;
ulong    g_last_msc    = 0;
datetime g_seed_from   = 0;
int      g_w = 0, g_h = 0;
string   g_status      = "";
bool     g_dirty       = true;

//+------------------------------------------------------------------+
datetime StartOfWeek(const datetime now)
  {
   MqlDateTime dt;
   TimeToStruct(now,dt);
   const datetime midnight = now-(dt.hour*3600+dt.min*60+dt.sec);
   return(midnight-(datetime)dt.day_of_week*86400);
  }

//+------------------------------------------------------------------+
void CreatePanelObjects(void)
  {
   if(ObjectFind(0,EDIT_NAME)<0)
     {
      ObjectCreate(0,EDIT_NAME,OBJ_EDIT,0,0,0);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_XDISTANCE,64);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_YDISTANCE,14);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_XSIZE,52);
      ObjectSetInteger(0,EDIT_NAME,OBJPROP_YSIZE,18);
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
      ObjectSetInteger(0,BTN_NAME,OBJPROP_XDISTANCE,122);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_YDISTANCE,14);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_XSIZE,52);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_YSIZE,18);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_BGCOLOR,C'41,98,255');
      ObjectSetInteger(0,BTN_NAME,OBJPROP_BORDER_COLOR,C'41,98,255');
      ObjectSetInteger(0,BTN_NAME,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_ZORDER,10);
      ObjectSetInteger(0,BTN_NAME,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,BTN_NAME,OBJPROP_TEXT,"Apply");
     }
   ObjectSetInteger(0,BTN_NAME,OBJPROP_STATE,false);
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
//| Rebuild the whole series from the start of the current week.     |
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

   g_seed_from=StartOfWeek(TimeCurrent());
   const datetime to=TimeCurrent()+60;

   long   ticks_used=0;
   string src="ticks";

   if(InpUseTicks)
     {
      MqlTick buf[];
      const int CHUNK=6*3600;                       // 6h chunks, bounds memory

      for(datetime a=g_seed_from; a<to; a+=CHUNK)
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
      const int n=CopyRates(_Symbol,PERIOD_M1,g_seed_from,to,rates);
      for(int i=0;i<n;i++)
         g_agg.AddM1(rates[i]);
     }

   g_status=StringFormat("%s  R=%d (%.*f)  bars=%d  src=%s  %dms",
                         _Symbol,g_range_ticks,_Digits,g_range_ticks*g_tick_size,
                         g_agg.Total(),src,(int)(GetTickCount()-t0));
   g_dirty=true;
  }

//+------------------------------------------------------------------+
//| Feed only the ticks that arrived since the last call.            |
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
void Render(void)
  {
   if(g_w<80 || g_h<80)
      return;

   const int plot_r = g_w-AXIS_W;
   const int plot_t = PLOT_TOP;
   const int plot_b = g_h-PLOT_BOT;
   const int plot_h = plot_b-plot_t;
   if(plot_h<40 || plot_r<40)
      return;

   g_cv.Erase(ColorToARGB(InpBg,255));
   g_cv.FontSet("Tahoma",-100);

   //--- assemble the visible slice (completed bars + the forming one)
   const int done  = g_agg.Total();
   SRangeBar cur;
   const bool has_cur = g_agg.Current(cur);
   const int total = done+(has_cur?1:0);

   if(total<=0)
     {
      g_cv.TextOut(12,plot_t+20,"no data",ColorToARGB(InpText,255));
      g_cv.Update();
      return;
     }

   if(g_step<2)  g_step=2;
   int nvis=(plot_r-4)/g_step;
   if(nvis<1) nvis=1;

   if(g_scroll<0)             g_scroll=0;
   if(g_scroll>total-1)       g_scroll=total-1;

   const int last  = total-1-g_scroll;
   int       first = last-nvis+1;
   if(first<0) first=0;

   //--- price extent
   double lo=DBL_MAX, hi=-DBL_MAX;
   for(int i=first;i<=last;i++)
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

   const double pad=(hi-lo)*0.08+g_tick_size;
   hi+=pad; lo-=pad;
   const double span=hi-lo;

   //--- grid + price axis
   const double gstep=NiceStep(span/6.0);
   for(double p=MathCeil(lo/gstep)*gstep; p<=hi; p+=gstep)
     {
      const int y=plot_t+(int)((hi-p)/span*plot_h);
      g_cv.LineHorizontal(0,plot_r,y,ColorToARGB(InpGrid,255));
      g_cv.TextOut(plot_r+6,y-7,DoubleToString(p,_Digits),ColorToARGB(InpText,255));
     }
   g_cv.LineVertical(plot_r,plot_t-PLOT_TOP,g_h,ColorToARGB(InpGrid,255));

   //--- bars
   const int body=(g_step>=5? g_step-3 : 1);
   const int half=body/2;

   for(int i=first;i<=last;i++)
     {
      SRangeBar b;
      const bool forming=(i>=done);
      if(forming) b=cur;
      else if(!g_agg.Get(i,b)) continue;

      const int cx=plot_r-2-(last-i)*g_step-g_step/2;
      if(cx<0) continue;

      const int yh=plot_t+(int)((hi-b.high )/span*plot_h);
      const int yl=plot_t+(int)((hi-b.low  )/span*plot_h);
      const int yo=plot_t+(int)((hi-b.open )/span*plot_h);
      const int yc=plot_t+(int)((hi-b.close)/span*plot_h);

      const color  c   = (b.close>=b.open ? InpBull : InpBear);
      const uint   arg = ColorToARGB(c,255);

      g_cv.LineVertical(cx,yh,yl,arg);

      int y1=MathMin(yo,yc), y2=MathMax(yo,yc);
      if(y2-y1<1) y2=y1+1;
      g_cv.FillRectangle(cx-half,y1,cx+half,y2,arg);

      if(forming)                                   // outline the live bar
         g_cv.Rectangle(cx-half-1,y1-1,cx+half+1,y2+1,ColorToARGB(clrWhite,255));
     }

   //--- forming bar: close level + the two completion targets
   if(has_cur && g_scroll==0)
     {
      double up,dn;
      g_agg.PendingLevels(up,dn);

      const int yc=plot_t+(int)((hi-cur.close)/span*plot_h);
      if(yc>=plot_t && yc<=plot_b)
        {
         for(int x=0;x<plot_r;x+=6)
            g_cv.LineHorizontal(x,x+3,yc,ColorToARGB(InpText,255));

         const color cc=(cur.close>=cur.open?InpBull:InpBear);
         g_cv.FillRectangle(plot_r+1,yc-8,g_w,yc+8,ColorToARGB(cc,255));
         g_cv.TextOut(plot_r+6,yc-7,DoubleToString(cur.close,_Digits),
                      ColorToARGB(clrWhite,255));
        }

      const int yu=plot_t+(int)((hi-up)/span*plot_h);
      const int yd=plot_t+(int)((hi-dn)/span*plot_h);
      for(int x=0;x<plot_r;x+=10)
        {
         g_cv.LineHorizontal(x,x+4,yu,ColorToARGB(InpBull,255));
         g_cv.LineHorizontal(x,x+4,yd,ColorToARGB(InpBear,255));
        }
     }

   //--- header: OHLC of the bar at the right edge (TradingView style)
   SRangeBar hb;
   bool hb_ok=false;
   if(last>=done && has_cur)        { hb=cur; hb_ok=true; }
   else if(last>=0)                 { hb_ok=g_agg.Get(last,hb); }

   if(hb_ok)
     {
      const uint hc=ColorToARGB(hb.close>=hb.open?InpBull:InpBear,255);
      int x=PANEL_W+14;
      const string parts[4]={"O","H","L","C"};
      const double vals[4] ={hb.open,hb.high,hb.low,hb.close};

      for(int k=0;k<4;k++)
        {
         g_cv.TextOut(x,10,parts[k],ColorToARGB(InpText,255));
         x+=12;
         const string s=DoubleToString(vals[k],_Digits);
         g_cv.TextOut(x,10,s,hc);
         x+=(int)g_cv.TextWidth(s)+10;
        }
      g_cv.TextOut(x,10,StringFormat("Vol %I64d",hb.volume),ColorToARGB(InpText,255));
     }

   //--- panel chrome (the input box itself is a real OBJ_EDIT on top)
   g_cv.FillRectangle(6,6,6+PANEL_W,6+PANEL_H,ColorToARGB(C'30,34,45',255));
   g_cv.Rectangle(6,6,6+PANEL_W,6+PANEL_H,ColorToARGB(C'67,70,81',255));
   g_cv.TextOut(14,14,"Range",ColorToARGB(InpText,255));

   //--- status line
   g_cv.TextOut(8,g_h-16,g_status,ColorToARGB(C'120,123,134',255));
   g_cv.TextOut(plot_r-190,g_h-16,"wheel: scroll   ctrl+wheel: zoom",
                ColorToARGB(C'120,123,134',255));

   g_cv.Update();
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_range_ticks=(InpRange>0?InpRange:100);
   g_step       =(InpBarStep>1?InpBarStep:8);

   ChartSetInteger(0,CHART_EVENT_MOUSE_WHEEL,true);
   ChartSetInteger(0,CHART_FOREGROUND,false);

   if(!BuildCanvas())
      return(INIT_FAILED);

   CreatePanelObjects();
   Rebuild();
   Render();
   ChartRedraw();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_cv.Destroy();
   ObjectDelete(0,EDIT_NAME);
   ObjectDelete(0,BTN_NAME);
   ObjectDelete(0,CANVAS_NAME);
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

   if(g_dirty)
     {
      Render();
      ChartRedraw();
      g_dirty=false;
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
     {
      const int w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
      const int h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
      if(w!=g_w || h!=g_h)
        {
         BuildCanvas();
         g_dirty=true;
        }
      return;
     }

   if(id==CHARTEVENT_OBJECT_CLICK && sparam==BTN_NAME)
     {
      const int v=(int)StringToInteger(ObjectGetString(0,EDIT_NAME,OBJPROP_TEXT));
      if(v>0)
        {
         g_range_ticks=v;
         Rebuild();
        }
      ObjectSetInteger(0,BTN_NAME,OBJPROP_STATE,false);
      ObjectSetString(0,EDIT_NAME,OBJPROP_TEXT,IntegerToString(g_range_ticks));
      Render();
      ChartRedraw();
      return;
     }

   if(id==CHARTEVENT_OBJECT_ENDEDIT && sparam==EDIT_NAME)
     {
      const int v=(int)StringToInteger(ObjectGetString(0,EDIT_NAME,OBJPROP_TEXT));
      if(v>0)
        {
         g_range_ticks=v;
         Rebuild();
        }
      ObjectSetString(0,EDIT_NAME,OBJPROP_TEXT,IntegerToString(g_range_ticks));
      Render();
      ChartRedraw();
      return;
     }

   if(id==CHARTEVENT_MOUSE_WHEEL)
     {
      const int  delta = (int)(lparam>>16);
      const bool ctrl  = ((lparam&0x0008)!=0);

      if(ctrl)
        {
         g_step += (delta>0? 1 : -1);
         if(g_step<2)  g_step=2;
         if(g_step>40) g_step=40;
        }
      else
        {
         g_scroll += (delta>0? 5 : -5);
         if(g_scroll<0) g_scroll=0;
        }

      Render();
      ChartRedraw();
     }
  }
//+------------------------------------------------------------------+
