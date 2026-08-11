//+------------------------------------------------------------------+
//|                                                RangeDrawings.mqh |
//|         Drawing tools, toolbar and editing for the range chart   |
//+------------------------------------------------------------------+
//
// Every drawing is anchored in (bar index, price) space, never pixels, so
// shapes stay stuck to the chart through scroll, zoom and price scaling.
// Bar indices are stable because the aggregator only ever appends.
//
#property copyright "Range Chart"

#include <Canvas\Canvas.mqh>

//+------------------------------------------------------------------+
enum ENUM_RC_TOOL
  {
   TOOL_CROSS = 0,   // crosshair, draws nothing
   TOOL_TREND,       // trend line
   TOOL_RAY,         // ray, extends to the right
   TOOL_HLINE,       // horizontal line
   TOOL_VLINE,       // vertical line
   TOOL_RECT,        // rectangle
   TOOL_FIB,         // fib retracement
   TOOL_MEASURE,     // price/bar ruler
   TOOL_TEXT,        // text label
   TOOL_NOTE,        // callout
   TOOL_LONG,        // long position
   TOOL_SHORT,       // short position
   TOOL_COUNT
  };

//--- one drawing. bar/price pairs are the anchors; p3 is the third price
//--- used by the position tools (entry, target, stop)
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

//--- the pixel <-> data mapping for the frame being drawn
struct SView
  {
   int      plot_r,plot_t,plot_b,plot_h;
   double   hi,lo,span;
   double   step,anchor_x;
   int      last_slot;
  };

//+------------------------------------------------------------------+
double BarToX  (const SView &v,const double bar) { return(v.anchor_x-(v.last_slot-bar)*v.step); }
double XToBar  (const SView &v,const double x)   { return(v.last_slot-(v.anchor_x-x)/v.step);   }
double PriceToY(const SView &v,const double p)   { return(v.plot_t+(v.hi-p)/v.span*v.plot_h);   }
double YToPrice(const SView &v,const double y)   { return(v.hi-(y-v.plot_t)/v.plot_h*v.span);   }

//--- palette cycled by the colour swatch in the properties strip
const color RC_PALETTE[8]=
  {
   C'41,98,255',  C'38,166,154', C'239,83,80',  C'255,183,77',
   C'156,39,176', C'0,188,212',  C'209,212,220',C'120,123,134'
  };

//+------------------------------------------------------------------+
//| Drawing store: hit testing, editing, rendering, persistence.     |
//+------------------------------------------------------------------+
class CDrawings
  {
private:
   SDrawing          m_items[];
   int               m_count;
   CCanvas          *m_cv;
   string            m_file;

   void              Stroke(const int x1,const int y1,const int x2,const int y2,
                            const int w,const uint clr);
   void              Handle(const int x,const int y,const bool hot);
   void              Box(const int x1,const int y1,const int x2,const int y2,
                         const uint clr,const int w);
   double            DistToSeg(const double px,const double py,
                               const double x1,const double y1,
                               const double x2,const double y2) const;

public:
                     CDrawings(void): m_count(0),m_cv(NULL) {}

   void              Attach(CCanvas *cv) { m_cv=cv; }
   int               Total(void) const   { return(m_count); }
   bool              Get(const int i,SDrawing &out) const;
   bool              Set(const int i,const SDrawing &in);
   int               Add(const SDrawing &d);
   void              Remove(const int i);
   void              Clear(void);

   //--- geometry
   int               HandleCount(const int i) const;
   bool              HandlePos(const SView &v,const int i,const int h,int &x,int &y) const;
   int               HitTest(const SView &v,const int mx,const int my) const;
   int               HitHandle(const SView &v,const int i,const int mx,const int my) const;
   void              MoveBy(const int i,const double dbar,const double dprice);
   void              MoveHandle(const int i,const int h,const double bar,const double price);

   //--- rendering
   void              RenderOne(const SView &v,const int i,const bool selected,
                               const int digits);
   void              RenderAll(const SView &v,const int selected,const int digits);

   //--- persistence, one file per symbol and range size
   void              SetFile(const string sym,const int range) { m_file=StringFormat("RC_%s_%d.csv",sym,range); }
   bool              Save(void);
   bool              Load(void);
  };

//+------------------------------------------------------------------+
bool CDrawings::Get(const int i,SDrawing &out) const
  {
   if(i<0 || i>=m_count || !m_items[i].alive)
      return(false);
   out=m_items[i];
   return(true);
  }

//+------------------------------------------------------------------+
bool CDrawings::Set(const int i,const SDrawing &in)
  {
   if(i<0 || i>=m_count)
      return(false);
   m_items[i]=in;
   return(true);
  }

//+------------------------------------------------------------------+
int CDrawings::Add(const SDrawing &d)
  {
   for(int i=0;i<m_count;i++)                    // reuse a deleted slot
      if(!m_items[i].alive)
        {
         m_items[i]=d;
         m_items[i].alive=true;
         return(i);
        }

   ArrayResize(m_items,m_count+1,64);
   m_items[m_count]=d;
   m_items[m_count].alive=true;
   m_count++;
   return(m_count-1);
  }

//+------------------------------------------------------------------+
void CDrawings::Remove(const int i)
  {
   if(i>=0 && i<m_count)
      m_items[i].alive=false;
  }

//+------------------------------------------------------------------+
void CDrawings::Clear(void)
  {
   ArrayResize(m_items,0,64);
   m_count=0;
  }

//+------------------------------------------------------------------+
void CDrawings::Stroke(const int x1,const int y1,const int x2,const int y2,
                       const int w,const uint clr)
  {
   if(m_cv==NULL)
      return;

   m_cv.LineAA(x1,y1,x2,y2,clr);
   for(int k=1;k<w;k++)                          // thicken by offsetting copies
     {
      if(MathAbs(x2-x1)>MathAbs(y2-y1)) m_cv.LineAA(x1,y1+k,x2,y2+k,clr);
      else                              m_cv.LineAA(x1+k,y1,x2+k,y2,clr);
     }
  }

//+------------------------------------------------------------------+
void CDrawings::Box(const int x1,const int y1,const int x2,const int y2,
                    const uint clr,const int w)
  {
   Stroke(x1,y1,x2,y1,w,clr);
   Stroke(x2,y1,x2,y2,w,clr);
   Stroke(x2,y2,x1,y2,w,clr);
   Stroke(x1,y2,x1,y1,w,clr);
  }

//+------------------------------------------------------------------+
void CDrawings::Handle(const int x,const int y,const bool hot)
  {
   if(m_cv==NULL)
      return;

   const uint fill=hot?ColorToARGB(clrWhite,255):ColorToARGB(C'41,98,255',255);
   m_cv.FillRectangle(x-4,y-4,x+4,y+4,fill);
   m_cv.Rectangle(x-4,y-4,x+4,y+4,ColorToARGB(clrWhite,255));
  }

//+------------------------------------------------------------------+
//| Perpendicular distance from a point to a segment, in pixels.     |
//+------------------------------------------------------------------+
double CDrawings::DistToSeg(const double px,const double py,
                            const double x1,const double y1,
                            const double x2,const double y2) const
  {
   const double dx=x2-x1, dy=y2-y1;
   const double len2=dx*dx+dy*dy;

   double t=0.0;
   if(len2>0.0)
     {
      t=((px-x1)*dx+(py-y1)*dy)/len2;
      if(t<0.0) t=0.0;
      if(t>1.0) t=1.0;
     }

   const double ex=x1+t*dx-px, ey=y1+t*dy-py;
   return(MathSqrt(ex*ex+ey*ey));
  }

//+------------------------------------------------------------------+
int CDrawings::HandleCount(const int i) const
  {
   if(i<0 || i>=m_count)
      return(0);

   switch(m_items[i].type)
     {
      case TOOL_HLINE:
      case TOOL_VLINE:
      case TOOL_TEXT:
      case TOOL_NOTE:   return(1);
      case TOOL_LONG:
      case TOOL_SHORT:  return(4);
      default:          return(2);
     }
  }

//+------------------------------------------------------------------+
bool CDrawings::HandlePos(const SView &v,const int i,const int h,int &x,int &y) const
  {
   if(i<0 || i>=m_count || !m_items[i].alive)
      return(false);

   const SDrawing d=m_items[i];

   switch(d.type)
     {
      case TOOL_HLINE:
         x=(int)BarToX(v,d.bar1); y=(int)PriceToY(v,d.price1); return(true);

      case TOOL_VLINE:
         x=(int)BarToX(v,d.bar1); y=(v.plot_t+v.plot_b)/2;     return(true);

      case TOOL_TEXT:
      case TOOL_NOTE:
         x=(int)BarToX(v,d.bar1); y=(int)PriceToY(v,d.price1); return(true);

      case TOOL_LONG:
      case TOOL_SHORT:
         switch(h)
           {
            case 0: x=(int)BarToX(v,d.bar1); y=(int)PriceToY(v,d.price1); return(true); // entry
            case 1: x=(int)BarToX(v,d.bar2); y=(int)PriceToY(v,d.price2); return(true); // target
            case 2: x=(int)BarToX(v,d.bar2); y=(int)PriceToY(v,d.price3); return(true); // stop
            case 3: x=(int)BarToX(v,d.bar2); y=(int)PriceToY(v,d.price1); return(true); // right edge
           }
         return(false);

      default:
         if(h==0) { x=(int)BarToX(v,d.bar1); y=(int)PriceToY(v,d.price1); return(true); }
         x=(int)BarToX(v,d.bar2); y=(int)PriceToY(v,d.price2); return(true);
     }
  }

//+------------------------------------------------------------------+
int CDrawings::HitHandle(const SView &v,const int i,const int mx,const int my) const
  {
   const int n=HandleCount(i);
   for(int h=0;h<n;h++)
     {
      int hx,hy;
      if(HandlePos(v,i,h,hx,hy) && MathAbs(mx-hx)<=5 && MathAbs(my-hy)<=5)
         return(h);
     }
   return(-1);
  }

//+------------------------------------------------------------------+
//| Topmost drawing within grab distance of the cursor, or -1.       |
//+------------------------------------------------------------------+
int CDrawings::HitTest(const SView &v,const int mx,const int my) const
  {
   const double GRAB=6.0;

   for(int i=m_count-1;i>=0;i--)                 // newest first, they draw on top
     {
      if(!m_items[i].alive)
         continue;

      const SDrawing d=m_items[i];
      const double x1=BarToX(v,d.bar1), y1=PriceToY(v,d.price1);
      const double x2=BarToX(v,d.bar2), y2=PriceToY(v,d.price2);

      switch(d.type)
        {
         case TOOL_HLINE:
            if(MathAbs(my-y1)<=GRAB) return(i);
            break;

         case TOOL_VLINE:
            if(MathAbs(mx-x1)<=GRAB) return(i);
            break;

         case TOOL_TEXT:
         case TOOL_NOTE:
            if(mx>=x1-6 && mx<=x1+120 && my>=y1-14 && my<=y1+10) return(i);
            break;

         case TOOL_RAY:
           {
            const double ex=(x2>=x1?v.plot_r:0);
            const double t =(x2-x1)!=0.0 ? (ex-x1)/(x2-x1) : 0.0;
            if(DistToSeg(mx,my,x1,y1,x1+t*(x2-x1),y1+t*(y2-y1))<=GRAB) return(i);
            break;
           }

         case TOOL_RECT:
         case TOOL_LONG:
         case TOOL_SHORT:
           {
            const double l=MathMin(x1,x2), r=MathMax(x1,x2);
            const double t=MathMin(y1,y2), b=MathMax(y1,y2);
            if(mx>=l-GRAB && mx<=r+GRAB && my>=t-GRAB && my<=b+GRAB) return(i);
            break;
           }

         case TOOL_FIB:
           {
            const double lv[7]={0.0,0.236,0.382,0.5,0.618,0.786,1.0};
            for(int k=0;k<7;k++)
              {
               const double y=y1+(y2-y1)*lv[k];
               if(MathAbs(my-y)<=GRAB && mx>=MathMin(x1,x2)-GRAB && mx<=v.plot_r)
                  return(i);
              }
            break;
           }

         default:
            if(DistToSeg(mx,my,x1,y1,x2,y2)<=GRAB) return(i);
        }
     }
   return(-1);
  }

//+------------------------------------------------------------------+
void CDrawings::MoveBy(const int i,const double dbar,const double dprice)
  {
   if(i<0 || i>=m_count)
      return;

   m_items[i].bar1  +=dbar;   m_items[i].bar2  +=dbar;
   m_items[i].price1+=dprice; m_items[i].price2+=dprice;
   m_items[i].price3+=dprice;
  }

//+------------------------------------------------------------------+
void CDrawings::MoveHandle(const int i,const int h,const double bar,const double price)
  {
   if(i<0 || i>=m_count)
      return;

   const int t=m_items[i].type;

   if(t==TOOL_LONG || t==TOOL_SHORT)
     {
      switch(h)
        {
         case 0: m_items[i].bar1=bar; m_items[i].price1=price; break;
         case 1: m_items[i].price2=price;                      break;
         case 2: m_items[i].price3=price;                      break;
         case 3: m_items[i].bar2=bar;                          break;
        }
      return;
     }

   if(h==0) { m_items[i].bar1=bar; m_items[i].price1=price; }
   else     { m_items[i].bar2=bar; m_items[i].price2=price; }
  }

//+------------------------------------------------------------------+
void CDrawings::RenderOne(const SView &v,const int i,const bool selected,
                          const int digits)
  {
   if(m_cv==NULL || i<0 || i>=m_count || !m_items[i].alive)
      return;

   const SDrawing d=m_items[i];
   const uint clr=ColorToARGB(d.clr,255);
   const int  w  =(d.width>0?d.width:2);

   const int x1=(int)BarToX(v,d.bar1), y1=(int)PriceToY(v,d.price1);
   const int x2=(int)BarToX(v,d.bar2), y2=(int)PriceToY(v,d.price2);

   switch(d.type)
     {
      case TOOL_TREND:
         Stroke(x1,y1,x2,y2,w,clr);
         break;

      case TOOL_RAY:
        {
         const int ex=(x2>=x1?v.plot_r:0);
         const int ey=(x2!=x1)? (int)(y1+(double)(ex-x1)/(x2-x1)*(y2-y1)) : y2;
         Stroke(x1,y1,ex,ey,w,clr);
         break;
        }

      case TOOL_HLINE:
        {
         Stroke(0,y1,v.plot_r,y1,w,clr);
         const string s=DoubleToString(d.price1,digits);
         m_cv.FillRectangle(v.plot_r+1,y1-9,v.plot_r+70,y1+9,clr);
         m_cv.TextOut(v.plot_r+6,y1-7,s,ColorToARGB(clrWhite,255));
         break;
        }

      case TOOL_VLINE:
         Stroke(x1,v.plot_t,x1,v.plot_b,w,clr);
         break;

      case TOOL_RECT:
        {
         const int l=MathMin(x1,x2), r=MathMax(x1,x2);
         const int t=MathMin(y1,y2), b=MathMax(y1,y2);
         Box(l,t,r,b,clr,w);
         break;
        }

      case TOOL_FIB:
        {
         const double lv[7]={0.0,0.236,0.382,0.5,0.618,0.786,1.0};
         const int    l=MathMin(x1,x2), r=MathMax(x1,x2);
         for(int k=0;k<7;k++)
           {
            const int    y=(int)(y1+(y2-y1)*lv[k]);
            const double p=d.price1+(d.price2-d.price1)*lv[k];
            Stroke(l,y,v.plot_r,y,1,clr);
            m_cv.TextOut(l+4,y-13,
                         StringFormat("%.3f  %s",lv[k],DoubleToString(p,digits)),clr);
           }
         Stroke(l,y1,l,y2,1,clr);
         break;
        }

      case TOOL_MEASURE:
        {
         const int l=MathMin(x1,x2), r=MathMax(x1,x2);
         const int t=MathMin(y1,y2), b=MathMax(y1,y2);
         Box(l,t,r,b,clr,1);
         Stroke(x1,y1,x2,y2,w,clr);

         const double dp=d.price2-d.price1;
         const double pc=(d.price1!=0.0? dp/d.price1*100.0 : 0.0);
         const string s =StringFormat("%s (%.2f%%)  %d bars",
                                      DoubleToString(dp,digits),pc,
                                      (int)MathAbs(d.bar2-d.bar1));
         const int tw=m_cv.TextWidth(s);
         m_cv.FillRectangle((l+r)/2-tw/2-6,t-22,(l+r)/2+tw/2+6,t-4,clr);
         m_cv.TextOut((l+r)/2-tw/2,t-20,s,ColorToARGB(clrWhite,255));
         break;
        }

      case TOOL_TEXT:
         m_cv.TextOut(x1,y1-7,d.text,clr);
         break;

      case TOOL_NOTE:
        {
         const int tw=m_cv.TextWidth(d.text);
         m_cv.FillRectangle(x1,y1-22,x1+tw+14,y1-2,ColorToARGB(C'30,34,45',255));
         Box(x1,y1-22,x1+tw+14,y1-2,clr,1);
         Stroke(x1+10,y1-2,x1+2,y1+10,1,clr);
         m_cv.TextOut(x1+7,y1-19,d.text,clr);
         break;
        }

      case TOOL_LONG:
      case TOOL_SHORT:
        {
         const int l =MathMin(x1,x2), r=MathMax(x1,x2);
         const int ye=(int)PriceToY(v,d.price1);
         const int yt=(int)PriceToY(v,d.price2);
         const int ys=(int)PriceToY(v,d.price3);

         const uint win =ColorToARGB(C'38,166,154',70);
         const uint loss=ColorToARGB(C'239,83,80',70);

         m_cv.FillRectangle(l,MathMin(ye,yt),r,MathMax(ye,yt),win);
         m_cv.FillRectangle(l,MathMin(ye,ys),r,MathMax(ye,ys),loss);
         Box(l,MathMin(MathMin(ye,yt),ys),r,MathMax(MathMax(ye,yt),ys),clr,1);
         Stroke(l,ye,r,ye,2,clr);

         const double risk  =MathAbs(d.price1-d.price3);
         const double reward=MathAbs(d.price2-d.price1);
         const string s=StringFormat("%s  R:R %.2f",
                                     (d.type==TOOL_LONG?"LONG":"SHORT"),
                                     (risk>0.0?reward/risk:0.0));
         m_cv.TextOut(l+6,ye-16,s,clr);
         break;
        }
     }

   if(selected)
     {
      const int n=HandleCount(i);
      for(int h=0;h<n;h++)
        {
         int hx,hy;
         if(HandlePos(v,i,h,hx,hy))
            Handle(hx,hy,false);
        }
     }
  }

//+------------------------------------------------------------------+
void CDrawings::RenderAll(const SView &v,const int selected,const int digits)
  {
   for(int i=0;i<m_count;i++)
      if(m_items[i].alive)
         RenderOne(v,i,(i==selected),digits);
  }

//+------------------------------------------------------------------+
bool CDrawings::Save(void)
  {
   if(m_file=="")
      return(false);

   const int fh=FileOpen(m_file,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(fh==INVALID_HANDLE)
      return(false);

   for(int i=0;i<m_count;i++)
     {
      if(!m_items[i].alive)
         continue;

      FileWrite(fh,m_items[i].type,
                DoubleToString(m_items[i].bar1,2),  DoubleToString(m_items[i].price1,8),
                DoubleToString(m_items[i].bar2,2),  DoubleToString(m_items[i].price2,8),
                DoubleToString(m_items[i].price3,8),
                (int)m_items[i].clr,m_items[i].width,m_items[i].text);
     }

   FileClose(fh);
   return(true);
  }

//+------------------------------------------------------------------+
bool CDrawings::Load(void)
  {
   Clear();

   if(m_file=="" || !FileIsExist(m_file))
      return(false);

   const int fh=FileOpen(m_file,FILE_READ|FILE_CSV|FILE_ANSI,',');
   if(fh==INVALID_HANDLE)
      return(false);

   while(!FileIsEnding(fh))
     {
      SDrawing d;
      d.type  =(int)FileReadNumber(fh);
      if(FileIsEnding(fh))
         break;

      d.bar1  =FileReadNumber(fh);
      d.price1=FileReadNumber(fh);
      d.bar2  =FileReadNumber(fh);
      d.price2=FileReadNumber(fh);
      d.price3=FileReadNumber(fh);
      d.clr   =(color)(int)FileReadNumber(fh);
      d.width =(int)FileReadNumber(fh);
      d.text  =FileReadString(fh);
      d.alive =true;

      if(d.type>=0 && d.type<TOOL_COUNT)
         Add(d);
     }

   FileClose(fh);
   return(true);
  }

//+------------------------------------------------------------------+
//| Toolbar: drawn on the canvas so it can be dragged anywhere.      |
//+------------------------------------------------------------------+
#define TB_CELL   26
#define TB_GRIP   14
#define TB_PAD    3

//--- the tools the toolbar exposes, in order
const int TB_TOOLS[13]=
  {
   TOOL_CROSS,TOOL_TREND,TOOL_RAY,TOOL_HLINE,TOOL_VLINE,TOOL_RECT,
   TOOL_FIB,TOOL_MEASURE,TOOL_TEXT,TOOL_NOTE,TOOL_LONG,TOOL_SHORT,-1
  };
#define TB_N  12                                  // -1 is the trailing delete cell

//+------------------------------------------------------------------+
int TbWidth(void)  { return(TB_GRIP+(TB_N+1)*TB_CELL+TB_PAD*2); }
int TbHeight(void) { return(TB_CELL+TB_PAD*2); }

//+------------------------------------------------------------------+
//| Index of the cell under the cursor, or -1.                       |
//+------------------------------------------------------------------+
int TbCellAt(const int tbx,const int tby,const int mx,const int my)
  {
   if(my<tby || my>tby+TbHeight() || mx<tbx || mx>tbx+TbWidth())
      return(-1);

   const int rel=mx-tbx-TB_GRIP-TB_PAD;
   if(rel<0)
      return(-2);                                 // the grip

   const int c=rel/TB_CELL;
   return(c<=TB_N ? c : -1);
  }

//+------------------------------------------------------------------+
//| Small vector glyphs, one per tool. No icon font needed.          |
//+------------------------------------------------------------------+
void TbGlyph(CCanvas *cv,const int tool,const int cx,const int cy,const uint c)
  {
   switch(tool)
     {
      case TOOL_CROSS:
         cv.LineHorizontal(cx-7,cx+7,cy,c);
         cv.LineVertical(cx,cy-7,cy+7,c);
         break;

      case TOOL_TREND:
         cv.LineAA(cx-7,cy+6,cx+7,cy-6,c);
         cv.Rectangle(cx-9,cy+4,cx-5,cy+8,c);
         cv.Rectangle(cx+5,cy-8,cx+9,cy-4,c);
         break;

      case TOOL_RAY:
         cv.LineAA(cx-8,cy+5,cx+8,cy-5,c);
         cv.Rectangle(cx-10,cy+3,cx-6,cy+7,c);
         break;

      case TOOL_HLINE:
         cv.LineHorizontal(cx-8,cx+8,cy,c);
         cv.Rectangle(cx-2,cy-2,cx+2,cy+2,c);
         break;

      case TOOL_VLINE:
         cv.LineVertical(cx,cy-8,cy+8,c);
         cv.Rectangle(cx-2,cy-2,cx+2,cy+2,c);
         break;

      case TOOL_RECT:
         cv.Rectangle(cx-8,cy-6,cx+8,cy+6,c);
         break;

      case TOOL_FIB:
         for(int k=-6;k<=6;k+=4)
            cv.LineHorizontal(cx-8,cx+8,cy+k,c);
         break;

      case TOOL_MEASURE:
         cv.LineHorizontal(cx-8,cx+8,cy,c);
         cv.LineVertical(cx-8,cy-5,cy+5,c);
         cv.LineVertical(cx+8,cy-5,cy+5,c);
         break;

      case TOOL_TEXT:
         cv.LineHorizontal(cx-6,cx+6,cy-7,c);
         cv.LineVertical(cx,cy-7,cy+7,c);
         break;

      case TOOL_NOTE:
         cv.Rectangle(cx-8,cy-7,cx+8,cy+3,c);
         cv.LineAA(cx-3,cy+3,cx-6,cy+8,c);
         break;

      case TOOL_LONG:
         cv.Rectangle(cx-8,cy-7,cx+8,cy,ColorToARGB(C'38,166,154',255));
         cv.Rectangle(cx-8,cy,cx+8,cy+7,ColorToARGB(C'239,83,80',255));
         break;

      case TOOL_SHORT:
         cv.Rectangle(cx-8,cy-7,cx+8,cy,ColorToARGB(C'239,83,80',255));
         cv.Rectangle(cx-8,cy,cx+8,cy+7,ColorToARGB(C'38,166,154',255));
         break;

      default:                                    // trash, the delete cell
         cv.Rectangle(cx-5,cy-4,cx+5,cy+7,c);
         cv.LineHorizontal(cx-7,cx+7,cy-6,c);
         cv.LineVertical(cx,cy-2,cy+5,c);
         break;
     }
  }

//+------------------------------------------------------------------+
void TbRender(CCanvas *cv,const int tbx,const int tby,const int active,
              const int hover)
  {
   const int w=TbWidth(), h=TbHeight();

   cv.FillRectangle(tbx,tby,tbx+w,tby+h,ColorToARGB(C'30,34,45',255));
   cv.Rectangle(tbx,tby,tbx+w,tby+h,ColorToARGB(C'67,70,81',255));

   //--- grip dots
   for(int r=0;r<3;r++)
      for(int col=0;col<2;col++)
         cv.FillRectangle(tbx+4+col*4,tby+8+r*5,tbx+6+col*4,tby+10+r*5,
                          ColorToARGB(C'120,123,134',255));

   for(int i=0;i<=TB_N;i++)
     {
      const int cx=tbx+TB_GRIP+TB_PAD+i*TB_CELL+TB_CELL/2;
      const int cy=tby+TB_PAD+TB_CELL/2;

      if(i==active)
         cv.FillRectangle(cx-12,cy-12,cx+12,cy+12,ColorToARGB(C'41,98,255',90));
      else if(i==hover)
         cv.FillRectangle(cx-12,cy-12,cx+12,cy+12,ColorToARGB(C'50,55,70',255));

      const uint c=(i==active)?ColorToARGB(C'88,140,255',255)
                              :ColorToARGB(C'209,212,220',255);
      TbGlyph(cv,TB_TOOLS[i],cx,cy,c);
     }
  }
//+------------------------------------------------------------------+
