#ifndef RC_NODAL_COUNTING_CANVAS_MQH
#define RC_NODAL_COUNTING_CANVAS_MQH

#include <Canvas\Canvas.mqh>
#include "..\\..\\RangeChartRenderer.mqh"
#include "NodalCountingModel.mqh"
#include "NodalCountingEngine.mqh"

class CNodalCountingCanvas
  {
private:
   bool           m_panel_open;
   SNodalSettings m_settings;
   CNodalCountingEngine m_engine;
   color          m_palette[8];
   int            m_text_sizes[6];
   string         m_text_names[6];
   int            m_button_x;
   int            m_button_y;
   int            m_panel_x;
   int            m_panel_y;
   int            m_panel_w;
   int            m_panel_h;
   int            m_edit_row;
   string         m_edit_buffer;
   bool           m_edit_replaced;

   bool           InRect(const int x,const int y,const int left,const int top,
                         const int width,const int height) const;
   void           DrawButton(CCanvas *cv,const int x,const int y,const int w,
                             const int h,const string text,const bool active,
                             const color text_color);
   void           DrawPanel(CCanvas *cv,const color text_color);
   void           DrawNodes(CCanvas *cv,const SView &view,const int first,
                            const int last_real);
   void           DrawWindowMarkers(CCanvas *cv,const SView &view);
   void           StepSetting(const int row,const int direction);

public:
                     CNodalCountingCanvas(void);
   void              Rebuild(CRangeAggregator *aggregator);
   void              Render(CCanvas *cv,const SView &view,const int first,
                            const int last_real,const color text_color);
   void              RenderPanel(CCanvas *cv,const color text_color);
   bool              HandleClick(const int x,const int y);
   bool              HandleKey(const int key,bool &settings_changed);
   bool              IsPointerOverUi(const int x,const int y) const;
   bool              Enabled(void) const { return(m_settings.draw); }
  };

CNodalCountingCanvas::CNodalCountingCanvas(void) : m_panel_open(false),
                                                   m_button_x(264),
                                                   m_button_y(6),
                                                   m_panel_x(8),
                                                   m_panel_y(48),
                                                   m_panel_w(248),
                                                   m_panel_h(211),
                                                   m_edit_row(-1),
                                                   m_edit_buffer(""),
                                                   m_edit_replaced(false)
  {
   NodalSettingsInit(m_settings);
   m_palette[0]=clrWhite;   m_palette[1]=clrYellow;
   m_palette[2]=clrAqua;    m_palette[3]=clrLime;
   m_palette[4]=clrOrange;  m_palette[5]=clrMagenta;
   m_palette[6]=clrBlue;    m_palette[7]=clrRed;
   m_text_sizes[0]=100; m_text_sizes[1]=180; m_text_sizes[2]=160;
   m_text_sizes[3]=120; m_text_sizes[4]=90;  m_text_sizes[5]=70;
   m_text_names[0]="Auto"; m_text_names[1]="Huge";
   m_text_names[2]="Large"; m_text_names[3]="Normal";
   m_text_names[4]="Small"; m_text_names[5]="Tiny";
   m_engine.Rebuild(NULL,m_settings);
  }

bool CNodalCountingCanvas::InRect(const int x,const int y,const int left,
                                  const int top,const int width,
                                  const int height) const
  {
   return(x>=left && x<=left+width && y>=top && y<=top+height);
  }

void CNodalCountingCanvas::DrawButton(CCanvas *cv,const int x,const int y,
                                      const int w,const int h,const string text,
                                      const bool active,const color text_color)
  {
   const color fill=(active?C'41,98,255':C'30,34,45');
   const color border=(active?C'41,98,255':C'67,70,81');
   cv.FillRectangle(x,y,x+w,y+h,ColorToARGB(fill,255));
   cv.Rectangle(x,y,x+w,y+h,ColorToARGB(border,255));
   cv.TextOut(x+7,y+5,text,ColorToARGB(text_color,255));
  }

void CNodalCountingCanvas::DrawNodes(CCanvas *cv,const SView &view,
                                    const int first,const int last_real)
  {
   if(!m_settings.draw) return;
   const int font_size=m_text_sizes[m_settings.text_size];
   const int label_height=(int)MathMax(7,font_size/10);
   cv.FontSet("Tahoma",-font_size);

   int color_index=0;
   for(int i=0;i<m_engine.UpCount();i++)
     {
      SNodalNode node;
      SRangeBar bar;
      if(!m_engine.GetUp(i,node)) continue;
      if(i>0 && node.number_node==1)
        { color_index++; if(color_index==8) color_index=1; }
      if(node.index_node<first ||
         node.index_node>last_real || !m_engine.GetBar(node.index_node,bar)) continue;
      const int x=(int)MathRound(view.anchor_x-(view.last_slot-node.index_node)*view.step);
      const int y=view.plot_t+(int)((view.hi-bar.high)/view.span*view.plot_h)-label_height-4;
      if(x<0 || x>=view.plot_r || y<view.plot_t+2 || y>=view.plot_b) continue;

      string label=IntegerToString(node.number_node);
      if(i>0)
        {
         SNodalNode prior;
         if(m_engine.GetUp(i-1,prior) && prior.index_node==node.index_node)
            label="   "+label;
        }
      cv.TextOut(x-(int)cv.TextWidth(label)/2,y,label,
                 ColorToARGB(m_settings.colors[color_index],255));
     }

   color_index=0;
   for(int i=0;i<m_engine.DownCount();i++)
     {
      SNodalNode node;
      SRangeBar bar;
      if(!m_engine.GetDown(i,node)) continue;
      if(i>0 && node.number_node==1)
        { color_index++; if(color_index==8) color_index=1; }
      if(node.index_node<first ||
         node.index_node>last_real || !m_engine.GetBar(node.index_node,bar)) continue;
      const int x=(int)MathRound(view.anchor_x-(view.last_slot-node.index_node)*view.step);
      const int y=view.plot_t+(int)((view.hi-bar.low)/view.span*view.plot_h)+4;
      if(x<0 || x>=view.plot_r || y<view.plot_t || y>=view.plot_b-2) continue;

      string label=IntegerToString(node.number_node);
      if(i>0)
        {
         SNodalNode prior;
         if(m_engine.GetDown(i-1,prior) && prior.index_node==node.index_node)
            label="   "+label;
        }
      cv.TextOut(x-(int)cv.TextWidth(label)/2,y,label,
                 ColorToARGB(m_settings.colors[color_index],255));
     }
   cv.FontSet("Tahoma",-100);
  }

void CNodalCountingCanvas::DrawWindowMarkers(CCanvas *cv,const SView &view)
  {
   if(!m_settings.draw || m_engine.BarCount()<=0) return;

   const int start=m_engine.WindowStart();
   const int end=m_engine.WindowEnd();
   if(start<0 || end<start) return;

   const int x_start=(int)MathRound(view.anchor_x-(view.last_slot-start)*view.step);
   const int x_end=(int)MathRound(view.anchor_x-(view.last_slot-end)*view.step);
   const bool start_visible=(x_start>=0 && x_start<view.plot_r);
   const bool end_visible=(x_end>=0 && x_end<view.plot_r);
   const int marker_y=view.plot_b-3;
   const uint start_color=ColorToARGB(C'76,175,128',230);
   const uint end_color=ColorToARGB(C'236,170,76',230);

   cv.FontSet("Tahoma",-80);
   if(start_visible)
     {
      cv.LineVertical(x_start,marker_y-6,marker_y,start_color);
      cv.TextOut(x_start-3,marker_y-17,"S",start_color);
     }
   if(end_visible)
     {
      cv.LineVertical(x_end,marker_y-6,marker_y,end_color);
      const int label_y=(start_visible && MathAbs(x_end-x_start)<12?
                         marker_y-29:marker_y-17);
      cv.TextOut(x_end-3,label_y,"E",end_color);
     }
   cv.FontSet("Tahoma",-100);
  }

void CNodalCountingCanvas::DrawPanel(CCanvas *cv,const color text_color)
  {
   const int x=m_panel_x, y=m_panel_y, w=m_panel_w;
   const color panel=C'25,29,41', border=C'67,70,81';
   cv.FillRectangle(x,y,x+w,y+m_panel_h,ColorToARGB(panel,250));
   cv.Rectangle(x,y,x+w,y+m_panel_h,ColorToARGB(border,255));
   cv.TextOut(x+10,y+8,"Nodal Counting settings",ColorToARGB(text_color,255));
   cv.TextOut(x+w-20,y+8,"x",ColorToARGB(C'180,185,198',255));
   cv.LineHorizontal(x+1,x+w-1,y+29,ColorToARGB(border,255));

   const int row_y[4]={y+37,y+68,y+99,y+130};
   const string labels[4]={"Start bars","End bars","Symmetry","Label size"};
   for(int row=0;row<4;row++)
     {
      cv.TextOut(x+10,row_y[row]+5,labels[row],ColorToARGB(text_color,255));
      if(row<2)
        {
         DrawButton(cv,x+134,row_y[row],25,23,"-",false,text_color);
         const int value=(row==0?m_settings.start_point:m_settings.end_point);
         const string value_text=(m_edit_row==row?m_edit_buffer:IntegerToString(value));
         const color field_border=(m_edit_row==row?C'41,98,255':border);
         cv.FillRectangle(x+162,row_y[row]+1,x+208,row_y[row]+22,
                          ColorToARGB(C'19,23,34',255));
         cv.Rectangle(x+162,row_y[row]+1,x+208,row_y[row]+22,
                      ColorToARGB(field_border,255));
         cv.TextOut(x+168,row_y[row]+5,value_text,ColorToARGB(text_color,255));
         DrawButton(cv,x+210,row_y[row],25,23,"+",false,text_color);
        }
      else if(row==2)
         DrawButton(cv,x+150,row_y[row],85,23,m_settings.symmetry?"On":"Off",
                    m_settings.symmetry,text_color);
      else
         DrawButton(cv,x+134,row_y[row],101,23,m_text_names[m_settings.text_size],
                    false,text_color);
     }

   cv.TextOut(x+10,y+164,"Number colors",ColorToARGB(text_color,255));
   for(int i=0;i<8;i++)
     {
      const int col=i%4, row=i/4;
      const int sx=x+116+col*30, sy=y+159+row*23;
      cv.FillRectangle(sx,sy,sx+20,sy+15,ColorToARGB(m_settings.colors[i],255));
      cv.Rectangle(sx,sy,sx+20,sy+15,ColorToARGB(C'100,105,118',255));
     }
   cv.TextOut(x+10,y+198,"Values: click, type, Enter  |  Colors: click",
              ColorToARGB(C'150,156,170',255));
  }

void CNodalCountingCanvas::Rebuild(CRangeAggregator *aggregator)
  {
   m_engine.Rebuild(aggregator,m_settings);
  }

void CNodalCountingCanvas::Render(CCanvas *cv,const SView &view,
                                  const int first,const int last_real,
                                  const color text_color)
  {
   const bool narrow=(view.plot_r<=380);
   m_button_x=(narrow?8:260);
   m_button_y=(narrow?48:6);
   m_panel_y=(narrow?80:48);
   DrawButton(cv,m_button_x,m_button_y,82,25,m_settings.draw?"NDS  ON":"NDS  OFF",
              m_settings.draw,text_color);
   DrawButton(cv,m_button_x+87,m_button_y,30,25,"...",m_panel_open,text_color);
   DrawWindowMarkers(cv,view);
   DrawNodes(cv,view,first,last_real);
  }

void CNodalCountingCanvas::RenderPanel(CCanvas *cv,const color text_color)
  {
   if(m_panel_open) DrawPanel(cv,text_color);
  }

void CNodalCountingCanvas::StepSetting(const int row,const int direction)
  {
   if(row==0) m_settings.start_point=(int)MathMax(1,MathMin(5000,m_settings.start_point+direction));
   if(row==1) m_settings.end_point=(int)MathMax(0,MathMin(5000,m_settings.end_point+direction));
   m_edit_row=-1;
   m_edit_buffer="";
   m_edit_replaced=false;
  }

bool CNodalCountingCanvas::HandleClick(const int x,const int y)
  {
   if(InRect(x,y,m_button_x,m_button_y,82,25))
     { m_edit_row=-1; m_edit_buffer=""; m_edit_replaced=false; m_settings.draw=!m_settings.draw; return(true); }
   if(InRect(x,y,m_button_x+87,m_button_y,30,25))
     {
      m_panel_open=!m_panel_open;
      if(!m_panel_open) { m_edit_row=-1; m_edit_buffer=""; m_edit_replaced=false; }
      return(true);
     }
   if(!m_panel_open || !InRect(x,y,m_panel_x,m_panel_y,m_panel_w,m_panel_h))
     {
      m_edit_row=-1;
      m_edit_buffer="";
      m_edit_replaced=false;
      return(false);
     }

   const int rel_y=y-m_panel_y;
   if(rel_y<=29 && x>=m_panel_x+m_panel_w-28)
     { m_panel_open=false; m_edit_row=-1; m_edit_buffer=""; m_edit_replaced=false; return(true); }
   m_edit_row=-1;
   m_edit_buffer="";
   m_edit_replaced=false;
   if(rel_y>=37 && rel_y<=60)
     {
      if(x>=m_panel_x+134 && x<=m_panel_x+159) StepSetting(0,-1);
      else if(x>=m_panel_x+210 && x<=m_panel_x+238) StepSetting(0,1);
      else if(x>=m_panel_x+162 && x<=m_panel_x+208)
        { m_edit_row=0; m_edit_buffer=IntegerToString(m_settings.start_point); }
      return(true);
     }
   if(rel_y>=68 && rel_y<=91)
     {
      if(x>=m_panel_x+134 && x<=m_panel_x+159) StepSetting(1,-1);
      else if(x>=m_panel_x+210 && x<=m_panel_x+238) StepSetting(1,1);
      else if(x>=m_panel_x+162 && x<=m_panel_x+208)
        { m_edit_row=1; m_edit_buffer=IntegerToString(m_settings.end_point); }
      return(true);
     }
   if(rel_y>=99 && rel_y<=122 && x>=m_panel_x+150 && x<=m_panel_x+235)
     { m_settings.symmetry=!m_settings.symmetry; return(true); }
   if(rel_y>=130 && rel_y<=153 && x>=m_panel_x+134 && x<=m_panel_x+235)
     { m_settings.text_size=(m_settings.text_size+1)%6; return(true); }
   if(rel_y>=159 && rel_y<=205)
     {
      const int col=(x-(m_panel_x+116))/30;
      const int row=(rel_y-159)/23;
      if(col>=0 && col<4 && row>=0 && row<2)
        {
         const int i=row*4+col;
         int p=0;
         for(int k=0;k<8;k++) if(m_palette[k]==m_settings.colors[i]) p=k;
         m_settings.colors[i]=m_palette[(p+1)%8];
        }
      return(true);
     }
   return(true);
  }

bool CNodalCountingCanvas::HandleKey(const int key,bool &settings_changed)
  {
   settings_changed=false;
   if(m_edit_row<0) return(false);
   if(key==27)
     { m_edit_row=-1; m_edit_buffer=""; m_edit_replaced=false; return(true); }
   if(key==13)
     {
      if(m_edit_buffer!="")
        {
         const int value=(int)StringToInteger(m_edit_buffer);
         if(m_edit_row==0) m_settings.start_point=(int)MathMax(1,MathMin(5000,value));
         else              m_settings.end_point=(int)MathMax(0,MathMin(5000,value));
         settings_changed=true;
        }
      m_edit_row=-1;
      m_edit_buffer="";
      m_edit_replaced=false;
      return(true);
     }
   if(key==8)
     {
      if(!m_edit_replaced) m_edit_replaced=true;
      const int length=StringLen(m_edit_buffer);
      if(length>0) m_edit_buffer=StringSubstr(m_edit_buffer,0,length-1);
      return(true);
     }
   int digit=-1;
   if(key>=48 && key<=57) digit=key-48;
   else if(key>=96 && key<=105) digit=key-96;
   if(digit>=0)
     {
      if(!m_edit_replaced) { m_edit_buffer=""; m_edit_replaced=true; }
      if(StringLen(m_edit_buffer)<4) m_edit_buffer+=IntegerToString(digit);
     }
   return(true);
  }

bool CNodalCountingCanvas::IsPointerOverUi(const int x,const int y) const
  {
   if(InRect(x,y,m_button_x,m_button_y,117,25)) return(true);
   return(m_panel_open && InRect(x,y,m_panel_x,m_panel_y,m_panel_w,m_panel_h));
  }

#endif
