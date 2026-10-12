#ifndef RC_RANGE_CHART_RENDERER_MQH
#define RC_RANGE_CHART_RENDERER_MQH

#include <Canvas\Canvas.mqh>
#include "RangeAggregator.mqh"
#include "RangeDrawingModel.mqh"

enum ENUM_RC_STYLE
  {
   RC_BARS    = 0,
   RC_CANDLES = 1
  };

//+------------------------------------------------------------------+
class CRangeChartRenderer
  {
private:
   double NiceStep(const double raw,const double tick_size);
   void   StrokeV(CCanvas *cv,const int x,const int y1,const int y2,
                  const int width,const uint clr);
   void   StrokeH(CCanvas *cv,const int x1,const int x2,const int y,
                  const int width,const uint clr);
   void   DashedH(CCanvas *cv,const int x1,const int x2,const int y,
                  const uint clr,const int on=4,const int off=4);
   void   PriceTag(CCanvas *cv,const SView &view,const int canvas_width,
                   const int y,const string text,const uint bg,const uint fg);

public:
   void DrawGrid(CCanvas *cv,const SView &view,const int canvas_height,
                 const int digits,const double tick_size,
                 const color grid,const color text);
   void DrawBars(CCanvas *cv,CRangeAggregator *agg,const SView &view,
                 const int completed,const bool has_current,const SRangeBar &current,
                 const int first,const int last_real,const ENUM_RC_STYLE style,
                 const color bull,const color bear);
   void DrawCurrentClose(CCanvas *cv,const SView &view,const int canvas_width,
                         const bool visible,const SRangeBar &current,
                         const color bull,const color bear,
                         const color text,const int digits);
   void DrawPriceTag(CCanvas *cv,const SView &view,const int canvas_width,
                     const int y,const string text,const uint bg,const uint fg)
     { PriceTag(cv,view,canvas_width,y,text,bg,fg); }
  };

//+------------------------------------------------------------------+
double CRangeChartRenderer::NiceStep(const double raw,const double tick_size)
  {
   if(raw<=0.0)
      return(tick_size>0.0?tick_size:1.0);

   const double mag=MathPow(10,MathFloor(MathLog10(raw)));
   const double n  =raw/mag;

   if(n<1.5) return(1.0*mag);
   if(n<3.0) return(2.0*mag);
   if(n<7.0) return(5.0*mag);
   return(10.0*mag);
  }

//+------------------------------------------------------------------+
void CRangeChartRenderer::StrokeV(CCanvas *cv,const int x,const int y1,
                                  const int y2,const int width,const uint clr)
  {
   if(width<=1) { cv.LineVertical(x,y1,y2,clr); return; }
   cv.FillRectangle(x-(width-1)/2,y1,x+width/2,y2,clr);
  }

//+------------------------------------------------------------------+
void CRangeChartRenderer::StrokeH(CCanvas *cv,const int x1,const int x2,
                                  const int y,const int width,const uint clr)
  {
   if(width<=1) { cv.LineHorizontal(x1,x2,y,clr); return; }
   cv.FillRectangle(x1,y-(width-1)/2,x2,y+width/2,clr);
  }

//+------------------------------------------------------------------+
void CRangeChartRenderer::DashedH(CCanvas *cv,const int x1,const int x2,
                                  const int y,const uint clr,
                                  const int on,const int off)
  {
   for(int x=x1;x<x2;x+=on+off)
      cv.LineHorizontal(x,(int)MathMin(x+on,x2),y,clr);
  }

//+------------------------------------------------------------------+
void CRangeChartRenderer::PriceTag(CCanvas *cv,const SView &view,
                                   const int canvas_width,const int y,
                                   const string text,const uint bg,const uint fg)
  {
   if(y<view.plot_t-10 || y>view.plot_b+10)
      return;
   cv.FillRectangle(view.plot_r+1,y-9,canvas_width,y+9,bg);
   cv.TextOut(view.plot_r+6,y-7,text,fg);
  }

//+------------------------------------------------------------------+
void CRangeChartRenderer::DrawGrid(CCanvas *cv,const SView &view,
                                   const int canvas_height,const int digits,
                                   const double tick_size,
                                   const color grid,const color text)
  {
   const double step=NiceStep(view.span/6.0,tick_size);
   for(double price=MathCeil(view.lo/step)*step;price<=view.hi;price+=step)
     {
      const int y=view.plot_t+(int)((view.hi-price)/view.span*view.plot_h);
      cv.LineHorizontal(0,view.plot_r,y,ColorToARGB(grid,255));
      cv.TextOut(view.plot_r+6,y-7,DoubleToString(price,digits),ColorToARGB(text,255));
     }
   cv.LineVertical(view.plot_r,0,canvas_height,ColorToARGB(grid,255));
  }

//+------------------------------------------------------------------+
void CRangeChartRenderer::DrawBars(CCanvas *cv,CRangeAggregator *agg,
                                  const SView &view,
                                  const int completed,const bool has_current,
                                  const SRangeBar &current,const int first,
                                  const int last_real,const ENUM_RC_STYLE style,
                                  const color bull,const color bear)
  {
   const int line_width=(view.step>=14.0?2:1);
   const int tick_width=(int)MathMax(1.0,MathRound(view.step*0.5)-1.0);
   const int body_half=(int)MathMax(1.0,MathRound(view.step)-3.0)/2;

   for(int i=first;i<=last_real;i++)
     {
      SRangeBar bar;
      const bool forming=(i>=completed);
      if(forming)
        {
         if(!has_current) continue;
         bar=current;
        }
      else if(!agg.Get(i,bar))
         continue;

      const int cx=(int)MathRound(view.anchor_x-(view.last_slot-i)*view.step);
      if(cx<0 || cx>view.plot_r)
         continue;

      const int high_y=view.plot_t+(int)((view.hi-bar.high)/view.span*view.plot_h);
      const int low_y =view.plot_t+(int)((view.hi-bar.low )/view.span*view.plot_h);
      const int open_y=view.plot_t+(int)((view.hi-bar.open)/view.span*view.plot_h);
      const int close_y=view.plot_t+(int)((view.hi-bar.close)/view.span*view.plot_h);
      const uint clr=ColorToARGB(bar.close>=bar.open?bull:bear,255);

      if(style==RC_BARS)
        {
         StrokeV(cv,cx,high_y,low_y,line_width,clr);
         StrokeH(cv,cx-tick_width,cx,open_y,line_width,clr);
         StrokeH(cv,cx,cx+tick_width+1,close_y,line_width,clr);
        }
      else
        {
         cv.LineVertical(cx,high_y,low_y,clr);
         int y1=MathMin(open_y,close_y),y2=MathMax(open_y,close_y);
         if(y2-y1<1) y2=y1+1;
         if(body_half>0) cv.FillRectangle(cx-body_half,y1,cx+body_half,y2,clr);
        }
     }
  }

//+------------------------------------------------------------------+
void CRangeChartRenderer::DrawCurrentClose(CCanvas *cv,const SView &view,
                                          const int canvas_width,
                                          const bool visible,
                                          const SRangeBar &current,
                                          const color bull,const color bear,
                                          const color text,
                                          const int digits)
  {
   if(!visible)
      return;

   const int y=view.plot_t+(int)((view.hi-current.close)/view.span*view.plot_h);
   if(y<=view.plot_t || y>=view.plot_b)
      return;

   DashedH(cv,0,view.plot_r,y,ColorToARGB(text,255),3,4);
   PriceTag(cv,view,canvas_width,y,DoubleToString(current.close,digits),
            ColorToARGB(current.close>=current.open?bull:bear,255),
            ColorToARGB(clrWhite,255));
  }

#endif
