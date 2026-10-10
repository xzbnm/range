#ifndef RC_RANGE_DRAWING_MODEL_MQH
#define RC_RANGE_DRAWING_MODEL_MQH

//+------------------------------------------------------------------+
enum ENUM_RC_TOOL
  {
   TOOL_CROSS = 0,
   TOOL_TREND,
   TOOL_RAY,
   TOOL_HLINE,
   TOOL_VLINE,
   TOOL_RECT,
   TOOL_FIB,
   TOOL_MEASURE,
   TOOL_TEXT,
   TOOL_NOTE,
   TOOL_LONG,
   TOOL_SHORT,
   TOOL_COUNT
  };

//--- A drawing is stored in chart coordinates, never screen pixels.
struct SDrawing
  {
   int      type;
   double   bar1,price1;
   double   bar2,price2;
   double   price3;
   color    clr;
   int      width;
   string   text;
   bool     alive;
  };

//--- Pixel projection for a single rendered frame.
struct SView
  {
   int      plot_r,plot_t,plot_b,plot_h;
   double   hi,lo,span;
   double   step,anchor_x;
   int      last_slot;
  };

double BarToX(const SView &v,const double bar)
  {
   return(v.anchor_x-(v.last_slot-bar)*v.step);
  }

double XToBar(const SView &v,const double x)
  {
   return(v.last_slot-(v.anchor_x-x)/v.step);
  }

double PriceToY(const SView &v,const double p)
  {
   return(v.plot_t+(v.hi-p)/v.span*v.plot_h);
  }

double YToPrice(const SView &v,const double y)
  {
   return(v.hi-(y-v.plot_t)/v.plot_h*v.span);
  }

const color RC_PALETTE[8]=
  {
   C'41,98,255',  C'38,166,154', C'239,83,80',  C'255,183,77',
   C'156,39,176', C'0,188,212',  C'209,212,220',C'120,123,134'
  };

#endif
