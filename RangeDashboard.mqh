#ifndef RC_RANGE_DASHBOARD_MQH
#define RC_RANGE_DASHBOARD_MQH

//+------------------------------------------------------------------+
//|                                               RangeDashboard.mqh |
//|      Canvas rendering for the hook strategy: position overlays    |
//|      and the performance panel.                                   |
//+------------------------------------------------------------------+
//
// The Pine indicator draws with box/line/label objects and a table.
// None of those exist on a CCanvas overlay, so both are repainted
// from strategy state on every frame instead. Anchors are (bar index,
// price) and go through the same SView projection the drawing tools
// use, so the overlays stay welded to their range bars through
// scroll, zoom and price scaling.
//
#property copyright "Range Chart"

#include <Canvas\Canvas.mqh>
#include "RangeDrawings.mqh"
#include "RangeStrategy.mqh"

//--- how far to the right a position box extends, in bars
#define HK_BOX_BARS   30

//--- dashboard geometry
#define DASH_W        246
#define DASH_ROW      17
#define DASH_HDR      22
#define DASH_PAD      8

//+------------------------------------------------------------------+
//| The canvas has no alpha, so translucency is mixed by hand.       |
//| t = 1 keeps `a` untouched, t = 0 returns `b`.                    |
//+------------------------------------------------------------------+
uint RcBlend(const color a,const color b,const double t)
  {
   const uint A=(uint)a, B=(uint)b;
   const double k=(t<0.0?0.0:(t>1.0?1.0:t));

   const int r =(int)(( A      &0xFF)*k+( B      &0xFF)*(1.0-k));
   const int g =(int)((( A>>8 )&0xFF)*k+(( B>>8 )&0xFF)*(1.0-k));
   const int bl=(int)((( A>>16)&0xFF)*k+(( B>>16)&0xFF)*(1.0-k));

   return(ColorToARGB((color)(r|(g<<8)|(bl<<16)),255));
  }

//+------------------------------------------------------------------+
//| Clipped primitives. Everything the strategy draws can run far     |
//| off-screen once the view is scrolled, so each one bails out       |
//| rather than handing CCanvas wild coordinates.                     |
//+------------------------------------------------------------------+
void HkFill(CCanvas *cv,const SView &v,int x1,int y1,int x2,int y2,const uint clr)
  {
   if(x1>x2) { const int t=x1; x1=x2; x2=t; }
   if(y1>y2) { const int t=y1; y1=y2; y2=t; }

   if(x2<0 || x1>v.plot_r || y2<v.plot_t || y1>v.plot_b)
      return;

   if(x1<0)        x1=0;
   if(x2>v.plot_r) x2=v.plot_r;
   if(y1<v.plot_t) y1=v.plot_t;
   if(y2>v.plot_b) y2=v.plot_b;

   cv.FillRectangle(x1,y1,x2,y2,clr);
  }

//+------------------------------------------------------------------+
void HkLineH(CCanvas *cv,const SView &v,int x1,int x2,const int y,
             const int w,const uint clr)
  {
   if(x1>x2) { const int t=x1; x1=x2; x2=t; }

   if(y<v.plot_t || y>v.plot_b || x2<0 || x1>v.plot_r)
      return;

   if(x1<0)        x1=0;
   if(x2>v.plot_r) x2=v.plot_r;

   if(w<=1) cv.LineHorizontal(x1,x2,y,clr);
   else     cv.FillRectangle(x1,y-(w-1)/2,x2,y+w/2,clr);
  }

//+------------------------------------------------------------------+
void HkDashH(CCanvas *cv,const SView &v,int x1,int x2,const int y,
             const uint clr,const int on=5,const int off=4)
  {
   if(x1>x2) { const int t=x1; x1=x2; x2=t; }

   if(y<v.plot_t || y>v.plot_b || x2<0 || x1>v.plot_r)
      return;

   if(x1<0)        x1=0;
   if(x2>v.plot_r) x2=v.plot_r;

   for(int x=x1;x<x2;x+=on+off)
      cv.LineHorizontal(x,(int)MathMin(x+on,x2),y,clr);
  }

//+------------------------------------------------------------------+
void HkRect(CCanvas *cv,const SView &v,int x1,int y1,int x2,int y2,const uint clr)
  {
   if(x1>x2) { const int t=x1; x1=x2; x2=t; }
   if(y1>y2) { const int t=y1; y1=y2; y2=t; }

   if(x2<0 || x1>v.plot_r || y2<v.plot_t || y1>v.plot_b)
      return;

   //--- only the edges that actually fall inside the plot get stroked
   if(y1>=v.plot_t) HkLineH(cv,v,x1,x2,y1,1,clr);
   if(y2<=v.plot_b) HkLineH(cv,v,x1,x2,y2,1,clr);

   const int cy1=(int)MathMax(y1,v.plot_t);
   const int cy2=(int)MathMin(y2,v.plot_b);
   if(cy1>cy2)
      return;

   if(x1>=0 && x1<=v.plot_r) cv.LineVertical(x1,cy1,cy2,clr);
   if(x2>=0 && x2<=v.plot_r) cv.LineVertical(x2,cy1,cy2,clr);
  }

//+------------------------------------------------------------------+
//| One hook: the risk box, the entry / stop / target levels and the  |
//| TP-SL-RF tag a finished trade leaves behind.                      |
//+------------------------------------------------------------------+
void HkRenderOne(CCanvas *cv,const SView &v,CHook *h,const int digits,
                 const color bg,const color txt)
  {
   if(h==NULL || !h.isDrawn)
      return;

   const int x1=(int)MathRound(BarToX(v,h.indexPeak));
   const int x2=(int)MathRound(BarToX(v,h.indexPeak+HK_BOX_BARS));
   if(x2<0 || x1>v.plot_r)
      return;

   const int ye=(int)MathRound(PriceToY(v,h.pricePeak));
   const int ys=(int)MathRound(PriceToY(v,h.priceStopLoss));
   const int yt=(int)MathRound(PriceToY(v,h.priceTakeProfit));

   //--- risk band, entry to stop
   HkFill(cv,v,x1,ye,x2,ys,RcBlend(clrRed,bg,0.12));
   HkRect(cv,v,x1,ye,x2,ys,RcBlend(clrRed,bg,0.40));

   //--- a live position gets a solid entry line, a pending order a dashed one
   if(h.isConfirmed && !h.isFinish)
      HkLineH(cv,v,x1,x2,ye,2,ColorToARGB(clrWhite,255));
   else
      HkDashH(cv,v,x1,x2,ye,ColorToARGB(C'200,204,216',255),6,4);

   HkDashH(cv,v,x1,x2,ys,ColorToARGB(clrRed,255),5,4);
   HkDashH(cv,v,x1,x2,yt,ColorToARGB(C'0,230,118',255),5,4);

   //--- result tag, placed where the Pine label sits
   if(h.resultKind!=HK_RESULT_NONE)
     {
      string s="";
      uint   c=ColorToARGB(txt,255);

      if(h.resultKind==HK_RESULT_TP)      { s="TP "+IntegerToString(h.resultNum); c=ColorToARGB(C'0,230,118',255); }
      else if(h.resultKind==HK_RESULT_SL) { s="SL "+IntegerToString(h.resultNum); c=ColorToARGB(C'255,82,82',255); }
      else                                { s="RF "+IntegerToString(h.resultNum); c=ColorToARGB(C'0,229,255',255); }

      const int ly=(int)MathRound(PriceToY(v,h.resultPrice));
      if(ly>=v.plot_t && ly<=v.plot_b && x1>=0 && x1<=v.plot_r-30)
         cv.TextOut(x1,ly-7,s,c);
     }
  }

//+------------------------------------------------------------------+
void HkRenderAll(CCanvas *cv,const SView &v,CHookStrategy *st,const int digits,
                 const color bg,const color txt)
  {
   if(st==NULL)
      return;

   //--- finished trades first so live ones stay readable on top
   const int n=st.HookCount();
   for(int pass=0;pass<2;pass++)
      for(int i=0;i<n;i++)
        {
         CHook *h=st.HookAt(i);
         if(h==NULL)
            continue;

         const bool live=(h.isConfirmed && !h.isFinish);
         if((pass==0) == live)
            continue;

         HkRenderOne(cv,v,h,digits,bg,txt);
        }
  }

//+------------------------------------------------------------------+
//| The stats table, redrawn as a canvas panel.                      |
//|                                                                   |
//| Labels default to English because CCanvas renders text without    |
//| complex-script shaping, so Persian comes out unjoined on most     |
//| terminals. Flip `fa` to try it anyway.                            |
//+------------------------------------------------------------------+
void DashRender(CCanvas *cv,const SView &v,CHookStrategy *st,
                const int digits,const double tick_size,const double last_close,
                const bool fa,const color txt,const color grid)
  {
   if(st==NULL)
      return;

   SHookSettings s=st.Settings();

   const int    totalTrades=st.CountTP()+st.CountSL()+st.CountRF();
   const double winRate    =(totalTrades>0 ? (double)st.CountTP()/totalTrades*100.0 : 0.0);
   const double netPnl     =st.Equity()-s.initial_capital;
   const double returnPct  =(s.initial_capital>0.0 ? netPnl/s.initial_capital*100.0 : 0.0);
   const double pf         =(st.TotalLoss()>0.0 ? st.TotalProfit()/st.TotalLoss()
                                                : (st.TotalProfit()>0.0 ? 999.0 : 0.0));
   const double avgMin     =(totalTrades>0 ? (double)st.TotalDuration()/totalTrades : 0.0);

   //--- f_suggested_spread, one basis point of price with a one-tick floor
   const double rawSpread=MathMax(last_close*0.0001,tick_size);
   const double sugSpread=(tick_size>0.0 ? MathRound(rawSpread/tick_size)*tick_size : rawSpread);

   const uint cGood=ColorToARGB(C'0,230,118',255);
   const uint cBad =ColorToARGB(C'255,82,82',255);
   const uint cWarn=ColorToARGB(C'255,167,38',255);
   const uint cInfo=ColorToARGB(C'0,229,255',255);
   const uint cDim =ColorToARGB(C'150,154,168',255);
   const uint cVal =ColorToARGB(txt,255);

   string keys[17];
   string vals[17];
   uint   clrs[17];

   if(fa)
     {
      keys[0]="سرمایه اولیه";      keys[1]="سرمایه فعلی";
      keys[2]="سود/زیان خالص";     keys[3]="بازدهی %";
      keys[4]="بیشترین افت";       keys[5]="نرخ برد";
      keys[6]="فاکتور سود";        keys[7]="نسبت R:R";
      keys[8]="کل معاملات";        keys[9]="تعداد TP";
      keys[10]="تعداد SL";         keys[11]="ریسک فری";
      keys[12]="تعداد Buy";        keys[13]="تعداد Sell";
      keys[14]="میانگین مدت";      keys[15]="باز / در انتظار";
      keys[16]="اسپرد پیشنهادی";
     }
   else
     {
      keys[0]="Initial capital";   keys[1]="Current capital";
      keys[2]="Net P/L";           keys[3]="Return";
      keys[4]="Max drawdown";      keys[5]="Win rate";
      keys[6]="Profit factor";     keys[7]="Risk : reward";
      keys[8]="Total trades";      keys[9]="TP count";
      keys[10]="SL count";         keys[11]="Risk-free count";
      keys[12]="Buy count";        keys[13]="Sell count";
      keys[14]="Avg duration";     keys[15]="Open / pending";
      keys[16]="Suggested spread";
     }

   vals[0] ="$"+DoubleToString(s.initial_capital,2);
   vals[1] ="$"+DoubleToString(st.Equity(),2);
   vals[2] =(netPnl>=0.0?"+":"-")+"$"+DoubleToString(MathAbs(netPnl),2);
   vals[3] =(returnPct>=0.0?"+":"")+DoubleToString(returnPct,2)+"%";
   vals[4] =DoubleToString(st.MaxDrawdown(),2)+"%";
   vals[5] =DoubleToString(winRate,2)+"%";
   vals[6] =DoubleToString(pf,2);
   vals[7] ="1 : "+DoubleToString(s.risk_reward,2);
   vals[8] =IntegerToString(totalTrades);
   vals[9] =IntegerToString(st.CountTP());
   vals[10]=IntegerToString(st.CountSL());
   vals[11]=IntegerToString(st.CountRF());
   vals[12]=IntegerToString(st.CountBuy());
   vals[13]=IntegerToString(st.CountSell());
   vals[14]=DoubleToString(avgMin,1)+"m";
   vals[15]=IntegerToString(st.OpenCount())+" / "+IntegerToString(st.PendingCount());
   vals[16]="$"+DoubleToString(sugSpread,digits);

   clrs[0] =cDim;
   clrs[1] =cVal;
   clrs[2] =(netPnl>=0.0?cGood:cBad);
   clrs[3] =(returnPct>=0.0?cGood:cBad);
   clrs[4] =(st.MaxDrawdown()<10.0?cGood:(st.MaxDrawdown()<25.0?cWarn:cBad));
   clrs[5] =(winRate>=50.0?cGood:cWarn);
   clrs[6] =(pf>=1.0?cGood:cBad);
   clrs[7] =cInfo;
   clrs[8] =cDim;
   clrs[9] =cGood;
   clrs[10]=cBad;
   clrs[11]=cInfo;
   clrs[12]=cDim;
   clrs[13]=cDim;
   clrs[14]=cDim;
   clrs[15]=cInfo;
   clrs[16]=ColorToARGB(C'255,235,59',255);

   //--- one extra row under the table for the pending signal
   const bool   hasSig =(st.LastEntry()>0.0);
   const int    rows   =17;
   const int    sig_h  =(hasSig?DASH_ROW+6:0);
   const int    h      =DASH_HDR+rows*DASH_ROW+DASH_PAD+sig_h;

   int x2=v.plot_r-8;
   int x1=x2-DASH_W;
   int y1=v.plot_t+8;
   int y2=y1+h;

   if(x1<4 || y2>v.plot_b)                       // no room, skip it entirely
      return;

   cv.FillRectangle(x1,y1,x2,y2,RcBlend(C'30,34,45',C'19,23,34',0.92));
   cv.Rectangle(x1,y1,x2,y2,ColorToARGB(grid,255));

   //--- header
   cv.FillRectangle(x1+1,y1+1,x2-1,y1+DASH_HDR,RcBlend(C'41,98,255',C'19,23,34',0.55));
   cv.TextOut(x1+DASH_PAD,y1+5,"HOOK PERFORMANCE",ColorToARGB(clrWhite,255));

   const int rx=x1+DASH_W-DASH_PAD;
   for(int r=0;r<rows;r++)
     {
      const int ry=y1+DASH_HDR+r*DASH_ROW;

      if(r%2==1)
         cv.FillRectangle(x1+1,ry,x2-1,ry+DASH_ROW-1,RcBlend(clrBlack,C'30,34,45',0.18));

      cv.TextOut(x1+DASH_PAD,ry+2,keys[r],cDim);

      const int w=(int)cv.TextWidth(vals[r]);
      cv.TextOut(rx-w,ry+2,vals[r],clrs[r]);
     }

   //--- last signal emitted by sendSignal()
   if(hasSig)
     {
      const int ry=y1+DASH_HDR+rows*DASH_ROW+3;
      const bool buy=(st.LastSignalType()=="buy");

      cv.LineHorizontal(x1+1,x2-1,ry-2,ColorToARGB(grid,255));
      cv.TextOut(x1+DASH_PAD,ry+3,(buy?"SIGNAL BUY":"SIGNAL SELL"),
                 (buy?cGood:cBad));

      const string sv=DoubleToString(st.LastEntry(),digits)+
                      "  SL "+DoubleToString(st.LastSL(),digits);
      const int    w =(int)cv.TextWidth(sv);
      cv.TextOut(rx-w,ry+3,sv,cVal);
     }
  }
//+------------------------------------------------------------------+
#endif // RC_RANGE_DASHBOARD_MQH
