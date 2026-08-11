//+------------------------------------------------------------------+
//|                                              RangeAggregator.mqh |
//|                          TradingView-compatible range bar engine |
//+------------------------------------------------------------------+
//
// Verified against live TradingView XAUUSD range-100 bars:
//
//   bar N-1 : O 4403.48  H 4404.16  L 4403.16  C 4403.16
//   bar N   : O 4403.15  H 4403.55  L 4402.55  C 4403.55
//
// Rules reproduced here:
//   1. bar height is exactly R
//   2. high/low float with the traversed path, they are not anchored
//      to the open
//   3. the bar closes the instant (high - low) reaches R, on the edge
//      that was just touched
//   4. the next bar opens one tick beyond that edge, in the direction
//      of the break
//
#property copyright "Range Chart"

//+------------------------------------------------------------------+
struct SRangeBar
  {
   double            open;
   double            high;
   double            low;
   double            close;
   datetime          time_open;
   datetime          time_close;
   long              volume;
  };

//+------------------------------------------------------------------+
//| Single-pass, incremental range bar builder.                      |
//| Feed it ticks (exact) or M1 rates (path is guessed).             |
//+------------------------------------------------------------------+
class CRangeAggregator
  {
private:
   double            m_range;      // bar height, in price units
   double            m_tick;       // instrument tick size
   double            m_eps;        // comparison tolerance
   SRangeBar         m_bars[];     // completed bars
   int               m_count;
   SRangeBar         m_cur;        // bar under construction
   bool              m_active;

   double            Q(const double p) const { return(MathRound(p/m_tick)*m_tick); }
   void              Append(const SRangeBar &b);
   void              OpenBar(const double price,const datetime t);

public:
                     CRangeAggregator(void);
   bool              Init(const double range_price,const double tick_size);
   void              Clear(void);

   void              AddTick(const double price,const datetime t,const long vol=1);
   void              AddM1(const MqlRates &r);

   int               Total(void)      const { return(m_count); }
   bool              HasCurrent(void) const { return(m_active); }
   double            Range(void)      const { return(m_range);  }
   double            Tick(void)       const { return(m_tick);   }

   bool              Get(const int i,SRangeBar &out) const;
   bool              Current(SRangeBar &out) const;

   // price levels at which the forming bar would complete
   bool              PendingLevels(double &up,double &dn) const;
  };

//+------------------------------------------------------------------+
CRangeAggregator::CRangeAggregator(void) : m_range(0.0),
                                           m_tick(0.0),
                                           m_eps(0.0),
                                           m_count(0),
                                           m_active(false)
  {
  }

//+------------------------------------------------------------------+
bool CRangeAggregator::Init(const double range_price,const double tick_size)
  {
   if(range_price<=0.0 || tick_size<=0.0)
      return(false);

   m_range = range_price;
   m_tick  = tick_size;
   m_eps   = tick_size*0.5;
   Clear();
   return(true);
  }

//+------------------------------------------------------------------+
void CRangeAggregator::Clear(void)
  {
   ArrayResize(m_bars,0,65536);
   m_count  = 0;
   m_active = false;
  }

//+------------------------------------------------------------------+
void CRangeAggregator::Append(const SRangeBar &b)
  {
   if(m_count>=ArraySize(m_bars))
      ArrayResize(m_bars,m_count+1,65536);   // reserve in blocks, no per-bar realloc

   m_bars[m_count]=b;
   m_count++;
  }

//+------------------------------------------------------------------+
void CRangeAggregator::OpenBar(const double price,const datetime t)
  {
   m_cur.open       = price;
   m_cur.high       = price;
   m_cur.low        = price;
   m_cur.close      = price;
   m_cur.time_open  = t;
   m_cur.time_close = t;
   m_cur.volume     = 0;
   m_active         = true;
  }

//+------------------------------------------------------------------+
//| Core. One tick in, zero or more completed bars out.              |
//+------------------------------------------------------------------+
void CRangeAggregator::AddTick(const double price,const datetime t,const long vol)
  {
   if(m_range<=0.0 || price<=0.0)
      return;

   const double p=Q(price);

   if(!m_active)
     {
      OpenBar(p,t);
      m_cur.volume=vol;
      return;
     }

   m_cur.volume    += vol;
   m_cur.time_close = t;

   // a single tick can span several ranges (gap / news spike), so loop
   for(int guard=0; guard<4096; guard++)
     {
      const bool up_fill   = (p>m_cur.high) && (p-m_cur.low  >= m_range-m_eps);
      const bool down_fill = (p<m_cur.low ) && (m_cur.high-p >= m_range-m_eps);

      if(!up_fill && !down_fill)
        {
         if(p>m_cur.high) m_cur.high=p;
         if(p<m_cur.low ) m_cur.low =p;
         m_cur.close=p;
         return;
        }

      double close_price,next_open;

      if(up_fill)
        {
         close_price = Q(m_cur.low+m_range);
         m_cur.high  = close_price;
         next_open   = Q(close_price+m_tick);
        }
      else
        {
         close_price = Q(m_cur.high-m_range);
         m_cur.low   = close_price;
         next_open   = Q(close_price-m_tick);
        }

      m_cur.close      = close_price;
      m_cur.time_close = t;
      Append(m_cur);

      OpenBar(next_open,t);
     }
  }

//+------------------------------------------------------------------+
//| M1 fallback for history the broker has no ticks for.             |
//| Path is guessed from the candle direction, the usual convention: |
//|   bullish -> O L H C      bearish -> O H L C                     |
//+------------------------------------------------------------------+
void CRangeAggregator::AddM1(const MqlRates &r)
  {
   const long v = (r.real_volume>0 ? (long)r.real_volume : (long)r.tick_volume);
   const long q = (v>4 ? v/4 : 1);

   AddTick(r.open,r.time,q);

   if(r.close>=r.open)
     {
      AddTick(r.low ,r.time,q);
      AddTick(r.high,r.time,q);
     }
   else
     {
      AddTick(r.high,r.time,q);
      AddTick(r.low ,r.time,q);
     }

   AddTick(r.close,r.time,(v-3*q>0 ? v-3*q : 1));
  }

//+------------------------------------------------------------------+
bool CRangeAggregator::Get(const int i,SRangeBar &out) const
  {
   if(i<0 || i>=m_count)
      return(false);

   out=m_bars[i];
   return(true);
  }

//+------------------------------------------------------------------+
bool CRangeAggregator::Current(SRangeBar &out) const
  {
   if(!m_active)
      return(false);

   out=m_cur;
   return(true);
  }

//+------------------------------------------------------------------+
//| Where the forming bar will close if price keeps going up / down. |
//+------------------------------------------------------------------+
bool CRangeAggregator::PendingLevels(double &up,double &dn) const
  {
   if(!m_active)
      return(false);

   up = Q(m_cur.low +m_range);
   dn = Q(m_cur.high-m_range);
   return(true);
  }
//+------------------------------------------------------------------+
