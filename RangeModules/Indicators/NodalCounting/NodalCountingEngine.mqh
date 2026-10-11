#ifndef RC_NODAL_COUNTING_ENGINE_MQH
#define RC_NODAL_COUNTING_ENGINE_MQH

#include "..\\..\\RangeAggregator.mqh"
#include "NodalCountingModel.mqh"

// Calculation-only port of the NDS library. It deliberately has no chart or
// canvas dependencies, which keeps it reusable by later chart modules.
class CNodalCountingEngine
  {
private:
   CRangeAggregator *m_aggregator;
   int         m_bar_count;
   SNodalNode  m_nodes_up[];
   SNodalNode  m_nodes_down[];
   SNodalSettings m_settings;
   double      m_price_lowest;
   int         m_index_lowest;
   double      m_price_highest;
   int         m_index_highest;
   int         m_leg_direction;
   int         m_leg_extreme_index;
   int         m_leg_pre_index;
   double      m_leg_extreme;

   double LowAt(const int index) const;
   double HighAt(const int index) const;
   void   SortDown(void);
   void   SortUp(void);
   bool   SymmetryDown(void) const;
   bool   SymmetryUp(void) const;
   void   FindDown(const int bar_index,const int extreme_index,
                   const int pre_index);
   void   FindUp(const int bar_index,const int extreme_index,
                 const int pre_index);
   void   Process(const int bar_index,const int last_bar_index);

public:
                     CNodalCountingEngine(void);
   void              Rebuild(CRangeAggregator *aggregator,
                             const SNodalSettings &settings);
   int               UpCount(void) const { return(ArraySize(m_nodes_up)); }
   int               DownCount(void) const { return(ArraySize(m_nodes_down)); }
   bool              GetUp(const int index,SNodalNode &node) const;
   bool              GetDown(const int index,SNodalNode &node) const;
   bool              GetBar(const int index,SRangeBar &bar) const;
   int               BarCount(void) const { return(m_bar_count); }
   int               WindowStart(void) const;
   int               WindowEnd(void) const;
  };

CNodalCountingEngine::CNodalCountingEngine(void) : m_aggregator(NULL),
                                                    m_bar_count(0),
                                                    m_price_lowest(999999.0),
                                                    m_index_lowest(0),
                                                    m_price_highest(0.0),
                                                    m_index_highest(0),
                                                    m_leg_direction(0),
                                                    m_leg_extreme_index(0),
                                                    m_leg_pre_index(0),
                                                    m_leg_extreme(0.0)
  {
   NodalSettingsInit(m_settings);
  }

double CNodalCountingEngine::LowAt(const int index) const
  {
   SRangeBar bar;
   if(!GetBar(index,bar)) return(0.0);
   return(bar.low);
  }

double CNodalCountingEngine::HighAt(const int index) const
  {
   SRangeBar bar;
   if(!GetBar(index,bar)) return(0.0);
   return(bar.high);
  }

bool CNodalCountingEngine::GetUp(const int index,SNodalNode &node) const
  {
   if(index<0 || index>=ArraySize(m_nodes_up)) return(false);
   node=m_nodes_up[index];
   return(true);
  }

bool CNodalCountingEngine::GetDown(const int index,SNodalNode &node) const
  {
   if(index<0 || index>=ArraySize(m_nodes_down)) return(false);
   node=m_nodes_down[index];
   return(true);
  }

bool CNodalCountingEngine::GetBar(const int index,SRangeBar &bar) const
  {
   if(m_aggregator==NULL || index<0 || index>=m_bar_count) return(false);
   const int completed=m_aggregator.Total();
   if(index>=completed) return(m_aggregator.Current(bar));
   if(!m_aggregator.Get(index,bar)) return(false);
   return(true);
  }

int CNodalCountingEngine::WindowStart(void) const
  {
   if(m_bar_count<=0) return(-1);
   const int last=m_bar_count-1;
   return((int)MathMax(0,last-m_settings.start_point+1));
  }

int CNodalCountingEngine::WindowEnd(void) const
  {
   if(m_bar_count<=0) return(-1);
   const int last=m_bar_count-1;
   return((int)MathMin(last,last-m_settings.end_point+1));
  }

bool CNodalCountingEngine::SymmetryDown(void) const
  {
   const int n=ArraySize(m_nodes_down);
   if(n<4) return(false);
   const SNodalNode node=m_nodes_down[n-1];
   const SNodalNode pre=m_nodes_down[n-2];
   const SNodalNode pre_pre=m_nodes_down[n-3];
   const SNodalNode pre_pre_pre=m_nodes_down[n-4];
   if(pre_pre.number_node!=2 || node.amount_correction<pre_pre.amount_correction)
      return(false);
   const double symmetry=pre_pre_pre.low_pre_node-pre_pre.high_node;
   const double min_price=pre_pre.low_correction-symmetry;
   return(node.high_node<=min_price);
  }

bool CNodalCountingEngine::SymmetryUp(void) const
  {
   const int n=ArraySize(m_nodes_up);
   if(n<4) return(false);
   const SNodalNode node=m_nodes_up[n-1];
   const SNodalNode pre=m_nodes_up[n-2];
   const SNodalNode pre_pre=m_nodes_up[n-3];
   const SNodalNode pre_pre_pre=m_nodes_up[n-4];
   if(pre_pre.number_node!=2 || node.amount_correction<pre_pre.amount_correction)
      return(false);
   const double symmetry=pre_pre.high_node-pre_pre_pre.low_pre_node;
   const double max_price=pre_pre.low_correction+symmetry;
   return(node.high_node>=max_price);
  }

void CNodalCountingEngine::SortDown(void)
  {
   int i=ArraySize(m_nodes_down)-1;
   int guard=0;
   while(i>=0 && guard++<8192)
     {
      const int size=ArraySize(m_nodes_down);
      SNodalNode node=m_nodes_down[i];
      if(size<=1)
        {
         if(node.low_correction>=node.low_pre_node) ArrayRemove(m_nodes_down,0,1);
         break;
        }
      if(i<=0) break;
      const SNodalNode pre=m_nodes_down[i-1];

      if(node.low_correction<pre.low_correction)
        {
         if(node.amount_correction<pre.amount_correction)
           { node.number_node=1; m_nodes_down[i]=node; break; }
         if(pre.number_node==1)
           {
            if(m_settings.symmetry && SymmetryDown())
              {
               const SNodalNode ppp=m_nodes_down[i-3];
               node.index_pre_node=ppp.index_pre_node;
               node.low_pre_node=ppp.low_pre_node;
               node.number_node=1;
               m_nodes_down[i]=node;
               ArrayRemove(m_nodes_down,i-3,3);
               i-=3;
               continue;
              }
            node.number_node=2; m_nodes_down[i]=node; break;
           }
         if(pre.number_node==2 && i>=2)
           {
            node.index_pre_node=m_nodes_down[i-2].index_pre_node;
            node.low_pre_node=m_nodes_down[i-2].low_pre_node;
            node.number_node=1;
            m_nodes_down[i]=node;
            ArrayRemove(m_nodes_down,i-2,2);
            i-=2;
            continue;
           }
        }
      else
        {
         if(node.high_node>pre.high_node)
           {
            if(node.low_correction>pre.low_correction)
              {
               node.index_pre_node=pre.index_pre_node;
               node.index_node=pre.index_node;
               node.high_node=pre.high_node;
               node.low_pre_node=pre.low_pre_node;
               node.amount_correction=node.low_correction-node.high_node;
               node.number_node=pre.number_node;
               m_nodes_down[i]=node;
               ArrayRemove(m_nodes_down,i-1,1);
               --i;
               continue;
              }
            if(node.low_correction==pre.low_correction)
              { node.number_node=1; m_nodes_down[i]=node; break; }
           }
         if(node.high_node<=pre.high_node)
           {
            if(pre.number_node==1)
              {
               if(node.low_correction>pre.low_correction)
                 {
                  node.number_node=1;
                  node.index_pre_node=pre.index_pre_node;
                  node.low_pre_node=pre.low_pre_node;
                  m_nodes_down[i]=node;
                  ArrayRemove(m_nodes_down,i-1,1);
                  --i;
                  continue;
                 }
               if(node.low_correction==pre.low_correction)
                 { node.number_node=2; m_nodes_down[i]=node; break; }
              }
            if(pre.number_node==2 && i>=2)
              {
               node.index_pre_node=m_nodes_down[i-2].index_pre_node;
               node.low_pre_node=m_nodes_down[i-2].low_pre_node;
               node.number_node=1;
               m_nodes_down[i]=node;
               ArrayRemove(m_nodes_down,i-2,2);
               i-=2;
               continue;
              }
           }
        }
      break;
     }
  }

void CNodalCountingEngine::SortUp(void)
  {
   int i=ArraySize(m_nodes_up)-1;
   int guard=0;
   while(i>=0 && guard++<8192)
     {
      const int size=ArraySize(m_nodes_up);
      SNodalNode node=m_nodes_up[i];
      if(size<=1)
        {
         if(node.low_correction<=node.low_pre_node) ArrayRemove(m_nodes_up,0,1);
         break;
        }
      if(i<=0) break;
      const SNodalNode pre=m_nodes_up[i-1];

      if(node.low_correction>pre.low_correction)
        {
         if(node.amount_correction<pre.amount_correction)
           { node.number_node=1; m_nodes_up[i]=node; break; }
         if(pre.number_node==1)
           {
            if(m_settings.symmetry && SymmetryUp())
              {
               const SNodalNode ppp=m_nodes_up[i-3];
               node.index_pre_node=ppp.index_pre_node;
               node.low_pre_node=ppp.low_pre_node;
               node.number_node=1;
               m_nodes_up[i]=node;
               ArrayRemove(m_nodes_up,i-3,3);
               i-=3;
               continue;
              }
            node.number_node=2; m_nodes_up[i]=node; break;
           }
         if(pre.number_node==2 && i>=2)
           {
            node.index_pre_node=m_nodes_up[i-2].index_pre_node;
            node.low_pre_node=m_nodes_up[i-2].low_pre_node;
            node.number_node=1;
            m_nodes_up[i]=node;
            ArrayRemove(m_nodes_up,i-2,2);
            i-=2;
            continue;
           }
        }
      else
        {
         if(node.high_node<pre.high_node)
           {
            if(node.low_correction<pre.low_correction)
              {
               node.index_pre_node=pre.index_pre_node;
               node.index_node=pre.index_node;
               node.high_node=pre.high_node;
               node.low_pre_node=pre.low_pre_node;
               node.amount_correction=node.high_node-node.low_correction;
               node.number_node=pre.number_node;
               m_nodes_up[i]=node;
               ArrayRemove(m_nodes_up,i-1,1);
               --i;
               continue;
              }
            if(node.low_correction==pre.low_correction)
              { node.number_node=1; m_nodes_up[i]=node; break; }
           }
         if(node.high_node>=pre.high_node)
           {
            if(pre.number_node==1)
              {
               if(node.low_correction<pre.low_correction)
                 {
                  node.number_node=1;
                  node.index_pre_node=pre.index_pre_node;
                  node.low_pre_node=pre.low_pre_node;
                  m_nodes_up[i]=node;
                  ArrayRemove(m_nodes_up,i-1,1);
                  --i;
                  continue;
                 }
               if(node.low_correction==pre.low_correction)
                 { node.number_node=2; m_nodes_up[i]=node; break; }
              }
            if(pre.number_node==2 && i>=2)
              {
               node.index_pre_node=m_nodes_up[i-2].index_pre_node;
               node.low_pre_node=m_nodes_up[i-2].low_pre_node;
               node.number_node=1;
               m_nodes_up[i]=node;
               ArrayRemove(m_nodes_up,i-2,2);
               i-=2;
               continue;
              }
           }
        }
      break;
     }
  }

void CNodalCountingEngine::FindDown(const int i,const int extreme_index,
                                   const int pre_index)
  {
   const int count=ArraySize(m_nodes_down);

   SNodalNode node;
   node.number_node=1;
   node.index_pre_node=pre_index;
   node.index_node=extreme_index;
   node.index_correction=i;
   node.low_pre_node=HighAt(node.index_pre_node);
   node.high_node=LowAt(extreme_index);
   node.low_correction=HighAt(i);
   node.amount_correction=node.low_correction-node.high_node;
   if(count>0)
     {
      node.index_pre_node=m_nodes_down[count-1].index_correction;
      node.low_pre_node=HighAt(node.index_pre_node);
     }
   ArrayResize(m_nodes_down,count+1);
   m_nodes_down[count]=node;
   SortDown();
  }

void CNodalCountingEngine::FindUp(const int i,const int extreme_index,
                                 const int pre_index)
  {
   SNodalNode node;
   node.number_node=1;
   node.index_pre_node=pre_index;
   node.index_node=extreme_index;
   node.index_correction=i;
   node.low_correction=LowAt(i);
   node.low_pre_node=LowAt(node.index_pre_node);
   node.high_node=HighAt(extreme_index);
   node.amount_correction=node.high_node-node.low_correction;
   const int count=ArraySize(m_nodes_up);
   if(count>0)
     {
      node.index_pre_node=m_nodes_up[count-1].index_correction;
      node.low_pre_node=LowAt(node.index_pre_node);
     }
   ArrayResize(m_nodes_up,count+1);
   m_nodes_up[count]=node;
   SortUp();
  }

void CNodalCountingEngine::Process(const int i,const int last_bar_index)
  {
   if(LowAt(i)<m_price_lowest)
     { m_price_lowest=LowAt(i); m_index_lowest=i; }

   SRangeBar bar;
   if(!GetBar(i,bar)) return;
   const int direction=(bar.close>bar.open?1:(bar.close<bar.open?-1:0));
   if(direction!=0)
     {
      const int window_first=(int)MathMax(0,last_bar_index-m_settings.start_point+1);
      const int window_last=(int)MathMin(last_bar_index,last_bar_index-m_settings.end_point+1);
      const bool count_this_bar=(i>=window_first && i<=window_last);

      if(m_leg_direction==0)
        {
         m_leg_direction=direction;
         m_leg_extreme_index=i;
         m_leg_extreme=(direction>0?LowAt(i):HighAt(i));
         m_leg_pre_index=(direction>0?m_index_highest:m_index_lowest);
        }
      else if(direction==m_leg_direction)
        {
         const double extreme=(direction>0?LowAt(i):HighAt(i));
         if((direction>0 && extreme<m_leg_extreme) ||
            (direction<0 && extreme>m_leg_extreme))
           {
            m_leg_extreme=extreme;
            m_leg_extreme_index=i;
           }
        }
      else
        {
         if(count_this_bar)
           {
            if(m_leg_direction>0)
               FindDown(i,m_leg_extreme_index,m_leg_pre_index);
            else
               FindUp(i,m_leg_extreme_index,m_leg_pre_index);
           }

         const int prior_extreme=m_leg_extreme_index;
         m_leg_direction=direction;
         m_leg_extreme_index=i;
         m_leg_extreme=(direction>0?LowAt(i):HighAt(i));
         m_leg_pre_index=prior_extreme;
        }
     }

   if(direction>0)
     {
      const int count=ArraySize(m_nodes_down);
      if(count>0)
        {
         SNodalNode node=m_nodes_down[count-1];
         if(HighAt(i)>=node.low_correction)
           {
            node.low_correction=HighAt(i);
            node.index_correction=i;
            node.amount_correction=node.low_correction-node.high_node;
            m_nodes_down[count-1]=node;
            SortDown();
           }
        }
     }
   else if(direction<0)
     {
      const int count=ArraySize(m_nodes_up);
      if(count>0)
        {
         SNodalNode node=m_nodes_up[count-1];
         if(LowAt(i)<=node.low_correction)
           {
            node.low_correction=LowAt(i);
            node.index_correction=i;
            node.amount_correction=node.high_node-node.low_correction;
            m_nodes_up[count-1]=node;
            SortUp();
           }
        }
     }

   if(HighAt(i)>m_price_highest)
     { m_price_highest=HighAt(i); m_index_highest=i; }
  }

void CNodalCountingEngine::Rebuild(CRangeAggregator *aggregator,
                                   const SNodalSettings &settings)
  {
   m_settings=settings;
   ArrayResize(m_nodes_up,0);
   ArrayResize(m_nodes_down,0);
   m_price_lowest=999999.0;
   m_index_lowest=0;
   m_price_highest=0.0;
   m_index_highest=0;
   m_leg_direction=0;
   m_leg_extreme_index=0;
   m_leg_pre_index=0;
   m_leg_extreme=0.0;
   m_aggregator=aggregator;
   m_bar_count=0;
   if(aggregator==NULL) return;

   const int completed=aggregator.Total();
   const bool current=aggregator.HasCurrent();
   const int total=completed+(current?1:0);
   if(total<=0) return;
   m_bar_count=total;
   const int last=total-1;
   const int first=(int)MathMax(0,last-m_settings.start_point+1);
   const int last_to_process=(int)MathMin(last,last-m_settings.end_point+1);
   const int history_first=(int)MathMax(1,first-5000);
   for(int i=history_first;i<=last_to_process;i++) Process(i,last);
  }

#endif
