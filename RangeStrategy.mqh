#ifndef RC_RANGE_STRATEGY_MQH
#define RC_RANGE_STRATEGY_MQH

//+------------------------------------------------------------------+
//|                                                RangeStrategy.mqh |
//|      "Hook Sharp v7.1" signal logic, ported from Pine Script v6  |
//|      and rewired to run on the range bars CRangeAggregator makes |
//+------------------------------------------------------------------+
//
// The Pine original runs one pass per confirmed chart bar. Here the
// "chart bar" is a completed range bar, so the strategy is stepped
// once for every bar the aggregator appends, oldest first. Nothing is
// evaluated on the forming bar, which is the MQL equivalent of
// barstate.isconfirmed and keeps the result free of repainting.
//
// Index convention matches Pine exactly:
//   bar_index      -> m_bi, the absolute index of the bar being stepped
//   last_bar_index -> m_last_bi, the newest bar known to this batch
//   high[off]      -> H(off), off bars back from m_bi
//
// Deviations from the Pine source, all forced by the platform:
//   * drawings are not TradingView objects; a confirmed hook carries
//     its geometry and RangeChartCanvas paints it onto the canvas
//   * the day-start timezone is an offset in minutes from broker time
//     rather than an IANA name, since MQL has no tz database
//   * a warm-up guard skips the first bars, standing in for Pine's
//     na-propagation on history that does not exist yet
//
#property copyright "Range Chart"

#include "RangeAggregator.mqh"

//--- result of a finished trade, for the label the Pine code draws
#define HK_RESULT_NONE 0
#define HK_RESULT_TP   1
#define HK_RESULT_SL   2
#define HK_RESULT_RF   3

//+------------------------------------------------------------------+
//| Pine's `type hook`. A class, not a struct, so that array slots    |
//| hold references the way Pine objects do.                          |
//+------------------------------------------------------------------+
class CHook
  {
public:
   bool              isSharpRightHook;
   int               indexStart;
   int               indexPeak;
   int               indexEnd;
   double            priceStart;
   double            pricePeak;
   double            priceEnd;
   string            typeSignal;
   bool              isConfirmed;
   bool              isDrawn;
   bool              isOpen;
   bool              isOrder;
   bool              isGetProfit;
   bool              isFinish;
   bool              isRiskFreeActive;
   bool              isRiskFreeClosed;
   double            priceStopLoss;
   double            priceTakeProfit;
   double            tradeCapitalAtEntry;
   double            tradeRiskAmount;
   double            tradePnl;
   datetime          tradeOpenTime;
   datetime          tradeCloseTime;
   int               tradeDurationMinutes;

   //--- what the canvas needs to paint the finished-trade label
   int               resultKind;
   int               resultNum;
   double            resultPrice;

                     CHook(void);
   bool              IsBuy(void) { return(typeSignal=="buy"); }
  };

//+------------------------------------------------------------------+
CHook::CHook(void) : isSharpRightHook(false),
                     indexStart(0),
                     indexPeak(0),
                     indexEnd(0),
                     priceStart(0.0),
                     pricePeak(0.0),
                     priceEnd(0.0),
                     typeSignal(""),
                     isConfirmed(false),
                     isDrawn(false),
                     isOpen(false),
                     isOrder(false),
                     isGetProfit(false),
                     isFinish(false),
                     isRiskFreeActive(false),
                     isRiskFreeClosed(false),
                     priceStopLoss(0.0),
                     priceTakeProfit(0.0),
                     tradeCapitalAtEntry(0.0),
                     tradeRiskAmount(0.0),
                     tradePnl(0.0),
                     tradeOpenTime(0),
                     tradeCloseTime(0),
                     tradeDurationMinutes(0),
                     resultKind(HK_RESULT_NONE),
                     resultNum(0),
                     resultPrice(0.0)
  {
  }

//+------------------------------------------------------------------+
//| Every input of the Pine indicator, in one place.                 |
//+------------------------------------------------------------------+
struct SHookSettings
  {
   //--- detection
   double            max_dollar_hook;
   double            max_pullback_hook;
   int               min_hook_bars;        // declared by the Pine source, unused by its logic
   int               max_hook_bars;
   int               look_back_len;
   //--- money management
   double            initial_capital;
   double            risk_percent;
   double            risk_reward;
   double            spread;
   bool              enable_sl_reduce;
   double            sl_reduce_percent;
   bool              enable_risk_free;
   double            risk_free_trigger;
   //--- main window
   int               start_main_candle;
   int               end_main_candle;
   bool              enable_dynamic_start;
   int               day_start_hour;
   int               day_start_minute;
   int               day_tz_shift_min;     // minutes to add to broker time
   //--- timing
   int               min_minutes;
   bool              allow_multi_trade;
   //--- debug
   int               min_size_sharp;
   bool              just_node_1;
  };

//+------------------------------------------------------------------+
//| Sensible defaults, matching the Pine input defaults.             |
//+------------------------------------------------------------------+
void HookSettingsDefaults(SHookSettings &s)
  {
   s.max_dollar_hook      = 100.0;
   s.max_pullback_hook    = 10.0;
   s.min_hook_bars        = 5;
   s.max_hook_bars        = 15;
   s.look_back_len        = 0;
   s.initial_capital      = 100.0;
   s.risk_percent         = 10.0;
   s.risk_reward          = 2.0;
   s.spread               = 2.0;
   s.enable_sl_reduce     = false;
   s.sl_reduce_percent    = 20.0;
   s.enable_risk_free     = false;
   s.risk_free_trigger    = 1.0;
   s.start_main_candle    = 4990;
   s.end_main_candle      = 0;
   s.enable_dynamic_start = true;
   s.day_start_hour       = 1;
   s.day_start_minute     = 30;
   s.day_tz_shift_min     = 0;
   s.min_minutes          = 10;
   s.allow_multi_trade    = false;
   s.min_size_sharp       = 1;
   s.just_node_1          = true;
  }

//+------------------------------------------------------------------+
//| The ported indicator.                                            |
//+------------------------------------------------------------------+
class CHookStrategy
  {
private:
   SHookSettings     m_s;
   CRangeAggregator *m_agg;

   CHook            *m_own[];      // owns every hook ever created
   CHook            *m_list[];     // Pine's hooksList

   int               m_processed;  // bars already stepped
   int               m_bi;         // bar_index
   int               m_last_bi;    // last_bar_index
   datetime          m_day_start;  // _todayStartTime, in broker time
   int               m_warmup;

   //--- equity & timing tracker
   double            m_equity;
   double            m_peak_equity;
   double            m_max_dd;
   int               m_cnt_tp, m_cnt_sl, m_cnt_rf, m_cnt_buy, m_cnt_sell;
   double            m_total_profit, m_total_loss, m_gross_pnl;
   datetime          m_last_open_time;
   int               m_total_dur_min;

   //--- signal, reset at the top of every bar like the Pine original
   double            m_sig_entry, m_sig_sl, m_sig_remove;
   datetime          m_sig_time;
   string            m_sig_type;
   //--- and the last one that actually fired, kept for the dashboard
   double            m_last_entry, m_last_sl, m_last_remove;
   datetime          m_last_time;
   string            m_last_type;

   //--- bar access, all relative to m_bi
   bool              Valid(const int off) { return(off>=0 && m_bi-off>=0); }
   double            H(const int off);
   double            L(const int off);
   double            O(const int off);
   double            C(const int off);
   bool              IsGreen(const int off);
   bool              IsRed(const int off);
   datetime          BarTime(void);
   double            TrueRange(void);

   //--- list plumbing
   int               IndexOf(CHook *h);
   void              ListPush(CHook *h);
   void              ListRemove(const int i);

   //--- Pine helpers
   double            HighestBetween(const int abs_from,const int abs_to,bool &ok);
   double            LowestBetween (const int abs_from,const int abs_to,bool &ok);
   bool              PrevLowsHigher (const int idx);
   bool              PrevHighsLower (const int idx);
   void              ZigzagGreen(const int idxStart,const int idxEnd,bool &flag,int &idxZ);
   void              ZigzagRed  (const int idxStart,const int idxEnd,bool &flag,int &idxZ);
   int               FindStartLeftSharpBuy (void);
   int               FindStartLeftSharpSell(void);
   int               FindPeakBuy (void);
   int               FindPeakSell(void);
   void              FindStartRightSharpBuy (const int index_peak_hook,bool &isSignal,int &startIdx);
   void              FindStartRightSharpSell(const int index_peak_hook,bool &isSignal,int &startIdx);

   bool              CheckPullbackBuy (CHook *h);
   bool              CheckPullbackSell(CHook *h);
   bool              CheckDollarBuy   (CHook *h);
   bool              CheckDollarSell  (CHook *h);

   //--- order & position management
   double            AdjustedSL(const double entry,const double raw_sl);
   double            RiskAmount(const double cap);
   int               MinutesSinceLastTrade(void);
   bool              CanOpenNewTrade(void);
   void              ClearOtherPendingOrders(CHook *keep);
   void              SendSignal(const string type,const double entry,
                                const double sl,const double remove);
   void              SendSignalOff(void);
   void              DrawClean(CHook *h);
   void              DrawPosition(CHook *h);
   void              DrawResult(CHook *h);
   void              RemoveHook(CHook *h);

   CHook            *NewHook(const int idxStart,const int idxPeak,const int idxEnd,
                             const double priceStart,const double pricePeak,
                             const double priceEnd,const string typeSignal);

   bool              ManageOrderBuyNormal (CHook *h);
   bool              ManageOrderBuySharp  (CHook *h);
   bool              ManageOrderSellNormal(CHook *h);
   bool              ManageOrderSellSharp (CHook *h);
   void              ManageOrder(CHook *h,bool &didBuy,bool &didSell);
   void              ManagePosition(CHook *h,bool &didTP,bool &didSL,bool &didRF,
                                    double &pnl,int &dur);
   void              CheckHookBuy(void);
   void              CheckHookSell(void);

   bool              InStartWindow(void);
   void              ComputeDayStart(void);
   void              OnBar(const int bar_index,const int last_bar_index);

public:
                     CHookStrategy(void);
                    ~CHookStrategy(void);

   void              Attach(CRangeAggregator *agg) { m_agg=agg; }
   void              Configure(const SHookSettings &s);
   void              Reset(void);
   bool              ProcessNew(void);       // true when something changed

   //--- read-only view for the renderer
   int               HookCount(void) { return(ArraySize(m_list)); }
   CHook            *HookAt(const int i);

   double            Equity(void)         { return(m_equity);        }
   double            PeakEquity(void)     { return(m_peak_equity);   }
   double            MaxDrawdown(void)    { return(m_max_dd);        }
   int               CountTP(void)        { return(m_cnt_tp);        }
   int               CountSL(void)        { return(m_cnt_sl);        }
   int               CountRF(void)        { return(m_cnt_rf);        }
   int               CountBuy(void)       { return(m_cnt_buy);       }
   int               CountSell(void)      { return(m_cnt_sell);      }
   double            TotalProfit(void)    { return(m_total_profit);  }
   double            TotalLoss(void)      { return(m_total_loss);    }
   int               TotalDuration(void)  { return(m_total_dur_min); }
   datetime          DayStart(void)       { return(m_day_start);     }
   int               Processed(void)      { return(m_processed);     }

   double            LastEntry(void)      { return(m_last_entry);    }
   double            LastSL(void)         { return(m_last_sl);       }
   double            LastRemove(void)     { return(m_last_remove);   }
   datetime          LastSignalTime(void) { return(m_last_time);     }
   string            LastSignalType(void) { return(m_last_type);     }

   int               OpenCount(void);
   int               PendingCount(void);
   SHookSettings     Settings(void) { return(m_s); }
  };

//+------------------------------------------------------------------+
CHookStrategy::CHookStrategy(void) : m_agg(NULL),
                                     m_processed(0),
                                     m_bi(0),
                                     m_last_bi(0),
                                     m_day_start(0),
                                     m_warmup(40)
  {
   HookSettingsDefaults(m_s);
   Reset();
  }

//+------------------------------------------------------------------+
CHookStrategy::~CHookStrategy(void)
  {
   for(int i=ArraySize(m_own)-1;i>=0;i--)
      if(m_own[i]!=NULL)
         delete m_own[i];

   ArrayResize(m_own,0);
   ArrayResize(m_list,0);
  }

//+------------------------------------------------------------------+
void CHookStrategy::Configure(const SHookSettings &s)
  {
   m_s=s;

   //--- the right-sharp scan walks back max_hook_bars bars, so history
   //--- must be at least that deep before the first evaluation
   m_warmup=(int)MathMax(40,m_s.max_hook_bars+2);
  }

//+------------------------------------------------------------------+
void CHookStrategy::Reset(void)
  {
   for(int i=ArraySize(m_own)-1;i>=0;i--)
      if(m_own[i]!=NULL)
         delete m_own[i];

   ArrayResize(m_own,0);
   ArrayResize(m_list,0);

   m_processed      = 0;
   m_bi             = 0;
   m_last_bi        = 0;

   m_equity         = m_s.initial_capital;
   m_peak_equity    = m_s.initial_capital;
   m_max_dd         = 0.0;
   m_cnt_tp=m_cnt_sl=m_cnt_rf=m_cnt_buy=m_cnt_sell=0;
   m_total_profit   = 0.0;
   m_total_loss     = 0.0;
   m_gross_pnl      = 0.0;
   m_last_open_time = 0;
   m_total_dur_min  = 0;

   m_sig_entry=m_sig_sl=m_sig_remove=0.0;
   m_sig_time=0;  m_sig_type="";
   m_last_entry=m_last_sl=m_last_remove=0.0;
   m_last_time=0; m_last_type="";

   ComputeDayStart();
  }

//+------------------------------------------------------------------+
CHook *CHookStrategy::HookAt(const int i)
  {
   if(i<0 || i>=ArraySize(m_list))
      return(NULL);

   return(m_list[i]);
  }

//+------------------------------------------------------------------+
int CHookStrategy::OpenCount(void)
  {
   int n=0;
   for(int i=0;i<ArraySize(m_list);i++)
      if(m_list[i]!=NULL && m_list[i].isConfirmed && !m_list[i].isFinish)
         n++;

   return(n);
  }

//+------------------------------------------------------------------+
int CHookStrategy::PendingCount(void)
  {
   int n=0;
   for(int i=0;i<ArraySize(m_list);i++)
      if(m_list[i]!=NULL && m_list[i].isOrder && !m_list[i].isConfirmed)
         n++;

   return(n);
  }

//+------------------------------------------------------------------+
//| Bar access. Out-of-range offsets are clamped so nothing can read  |
//| past the array; call sites test Valid() where Pine would have     |
//| produced na.                                                      |
//+------------------------------------------------------------------+
double CHookStrategy::H(const int off)
  {
   SRangeBar b;
   int i=m_bi-off;
   if(i<0) i=0;
   if(i>m_bi) i=m_bi;
   if(!m_agg.Get(i,b)) return(0.0);
   return(b.high);
  }

//+------------------------------------------------------------------+
double CHookStrategy::L(const int off)
  {
   SRangeBar b;
   int i=m_bi-off;
   if(i<0) i=0;
   if(i>m_bi) i=m_bi;
   if(!m_agg.Get(i,b)) return(0.0);
   return(b.low);
  }

//+------------------------------------------------------------------+
double CHookStrategy::O(const int off)
  {
   SRangeBar b;
   int i=m_bi-off;
   if(i<0) i=0;
   if(i>m_bi) i=m_bi;
   if(!m_agg.Get(i,b)) return(0.0);
   return(b.open);
  }

//+------------------------------------------------------------------+
double CHookStrategy::C(const int off)
  {
   SRangeBar b;
   int i=m_bi-off;
   if(i<0) i=0;
   if(i>m_bi) i=m_bi;
   if(!m_agg.Get(i,b)) return(0.0);
   return(b.close);
  }

//+------------------------------------------------------------------+
bool CHookStrategy::IsGreen(const int off)
  {
   if(!Valid(off))
      return(false);

   return(C(off)>O(off));
  }

//+------------------------------------------------------------------+
bool CHookStrategy::IsRed(const int off)
  {
   if(!Valid(off))
      return(false);

   return(C(off)<O(off));
  }

//+------------------------------------------------------------------+
//| Pine's `time` is the bar's opening time.                         |
//+------------------------------------------------------------------+
datetime CHookStrategy::BarTime(void)
  {
   SRangeBar b;
   if(!m_agg.Get(m_bi,b))
      return(0);

   return(b.time_open);
  }

//+------------------------------------------------------------------+
double CHookStrategy::TrueRange(void)
  {
   const double h=H(0), l=L(0);
   if(!Valid(1))
      return(h-l);

   const double pc=C(1);
   return(MathMax(h,pc)-MathMin(l,pc));
  }

//+------------------------------------------------------------------+
int CHookStrategy::IndexOf(CHook *h)
  {
   for(int i=0;i<ArraySize(m_list);i++)
      if(m_list[i]==h)
         return(i);

   return(-1);
  }

//+------------------------------------------------------------------+
void CHookStrategy::ListPush(CHook *h)
  {
   const int n=ArraySize(m_list);
   ArrayResize(m_list,n+1,256);
   m_list[n]=h;
  }

//+------------------------------------------------------------------+
void CHookStrategy::ListRemove(const int i)
  {
   const int n=ArraySize(m_list);
   if(i<0 || i>=n)
      return;

   for(int k=i;k<n-1;k++)
      m_list[k]=m_list[k+1];

   ArrayResize(m_list,n-1,256);
  }

//+------------------------------------------------------------------+
//| f_highest_between / f_lowest_between, absolute indices.          |
//+------------------------------------------------------------------+
double CHookStrategy::HighestBetween(const int abs_from,const int abs_to,bool &ok)
  {
   double best=0.0;
   ok=false;

   for(int i=abs_from;i<=abs_to;i++)
     {
      const int off=m_bi-i;
      if(!Valid(off))
         continue;

      const double v=H(off);
      if(!ok || v>best) { best=v; ok=true; }
     }

   return(best);
  }

//+------------------------------------------------------------------+
double CHookStrategy::LowestBetween(const int abs_from,const int abs_to,bool &ok)
  {
   double best=0.0;
   ok=false;

   for(int i=abs_from;i<=abs_to;i++)
     {
      const int off=m_bi-i;
      if(!Valid(off))
         continue;

      const double v=L(off);
      if(!ok || v<best) { best=v; ok=true; }
     }

   return(best);
  }

//+------------------------------------------------------------------+
//| f_are_prev_lows_higher.                                          |
//|                                                                  |
//| Pine's `for i = 1 to len` counts downwards when len < 1, so with  |
//| the default len = 0 the loop still runs for i = 1 and i = 0. That |
//| makes it "the bar just before the start must not dip lower", and  |
//| the port keeps that behaviour rather than the intuitive one.      |
//+------------------------------------------------------------------+
bool CHookStrategy::PrevLowsHigher(const int idx)
  {
   const int base=m_bi-idx;
   if(!Valid(base))
      return(true);

   const double refLow=L(base);
   const int    to    =m_s.look_back_len;
   const int    step  =(to>=1?1:-1);

   for(int i=1,guard=0; guard<5000; i+=step,guard++)
     {
      const int off=base+i;
      if(Valid(off) && L(off)<refLow)
         return(false);

      if(i==to)
         break;
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| f_are_prev_highs_lower. Unlike the buy side this one is guarded   |
//| by `len > 0`, so with the default it is a no-op.                  |
//+------------------------------------------------------------------+
bool CHookStrategy::PrevHighsLower(const int idx)
  {
   const int len =m_s.look_back_len;
   const int base=m_bi-idx;

   if(len<=0 || base<0 || !Valid(base))
      return(true);

   const double refHigh=H(base);

   for(int k=1;k<=len;k++)
     {
      const int off=base+k;
      if(!Valid(off))
         break;

      if(H(off)>refHigh)
         return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| f_check_zigzag_pattern_green / _red.                             |
//|                                                                  |
//| Scans from one bar after idxStart towards idxEnd + 1 and reports  |
//| the first bar of the wanted colour. The scan direction follows    |
//| Pine's implicit step, so it also handles the peak == end case     |
//| where the range runs forwards.                                   |
//+------------------------------------------------------------------+
void CHookStrategy::ZigzagGreen(const int idxStart,const int idxEnd,bool &flag,int &idxZ)
  {
   flag=false;
   idxZ=0;

   const int from=m_bi-idxStart-1;
   const int to  =m_bi-idxEnd+1;
   const int step=(to>=from?1:-1);

   for(int i=from,guard=0; guard<10000; i+=step,guard++)
     {
      if(IsGreen(i)) { idxZ=i; flag=true; return; }
      if(i==to) break;
     }
  }

//+------------------------------------------------------------------+
void CHookStrategy::ZigzagRed(const int idxStart,const int idxEnd,bool &flag,int &idxZ)
  {
   flag=false;
   idxZ=0;

   const int from=m_bi-idxStart-1;
   const int to  =m_bi-idxEnd+1;
   const int step=(to>=from?1:-1);

   for(int i=from,guard=0; guard<10000; i+=step,guard++)
     {
      if(IsRed(i)) { idxZ=i; flag=true; return; }
      if(i==to) break;
     }
  }

//+------------------------------------------------------------------+
//| The four "walk back while the colour holds" scans. Each returns   |
//| the absolute index of the oldest bar in the run, or -1 for na.    |
//+------------------------------------------------------------------+
int CHookStrategy::FindStartLeftSharpBuy(void)
  {
   int startIdx=-1;
   for(int i=1;i<30;i++)
     {
      if(!IsGreen(i))
         break;

      startIdx=m_bi-i;
     }
   return(startIdx);
  }

//+------------------------------------------------------------------+
int CHookStrategy::FindStartLeftSharpSell(void)
  {
   int startIdx=-1;
   for(int i=1;i<30;i++)
     {
      if(!IsRed(i))
         break;

      startIdx=m_bi-i;
     }
   return(startIdx);
  }

//+------------------------------------------------------------------+
int CHookStrategy::FindPeakBuy(void)
  {
   int startIdx=-1;
   for(int i=1;i<30;i++)
     {
      if(!IsRed(i))
         break;

      startIdx=m_bi-i;
     }
   return(startIdx);
  }

//+------------------------------------------------------------------+
int CHookStrategy::FindPeakSell(void)
  {
   int startIdx=-1;
   for(int i=1;i<30;i++)
     {
      if(!IsGreen(i))
         break;

      startIdx=m_bi-i;
     }
   return(startIdx);
  }

//+------------------------------------------------------------------+
//| f_find_start_index_right_sharp_buy.                              |
//+------------------------------------------------------------------+
void CHookStrategy::FindStartRightSharpBuy(const int index_peak_hook,
                                           bool &isSignal,int &startIdx)
  {
   isSignal=false;
   startIdx=-1;

   const int index_peak=m_bi-index_peak_hook;      // offset of the peak bar
   if(index_peak<0)
      return;

   int i=index_peak;
   while(i<m_s.max_hook_bars)
     {
      if(Valid(i) && L(i)<=L(0))
        {
         bool ok_h;
         const double highest=HighestBetween(m_bi-i,m_bi-index_peak,ok_h);
         if(ok_h && highest>H(index_peak))
            break;

         bool ok_l;
         const double lowest=LowestBetween(m_bi-i,m_bi-index_peak,ok_l);
         if(ok_l && lowest<L(i))
           {
            i++;
            continue;
           }

         if(PrevLowsHigher(m_bi-i))
           {
            const int index_start=i;

            bool flagIsZigzag; int indexZigzag;
            ZigzagRed(m_bi-index_start,m_bi-index_peak,flagIsZigzag,indexZigzag);

            bool isJustNode_1=true;
            if(flagIsZigzag && m_s.just_node_1)
              {
               isJustNode_1=false;
               if(Valid(indexZigzag) && L(indexZigzag)>=L(0))
                  isJustNode_1=true;
              }

            if(flagIsZigzag && isJustNode_1)
              {
               startIdx=m_bi-i;

               const double all=H(index_peak)-L(i);
               if(all<=m_s.max_dollar_hook)
                 {
                  const double part   =H(index_peak)-L(0);
                  const double percent=(all>0.0 ? part*100.0/all : 0.0);
                  if(percent>=m_s.max_pullback_hook)
                    {
                     isSignal=true;
                     break;
                    }
                 }
               else
                  break;
              }
           }
        }

      i++;
     }
  }

//+------------------------------------------------------------------+
//| f_find_start_index_right_sharp_sell. Not a strict mirror of the   |
//| buy version - the order of the highest/lowest guards differs in   |
//| the Pine source and is preserved here.                            |
//+------------------------------------------------------------------+
void CHookStrategy::FindStartRightSharpSell(const int index_peak_hook,
                                            bool &isSignal,int &startIdx)
  {
   isSignal=false;
   startIdx=-1;

   const int index_peak=m_bi-index_peak_hook;
   if(index_peak<0)
      return;

   int i=index_peak;
   while(i<m_s.max_hook_bars)
     {
      if(Valid(i) && H(i)>=H(0))
        {
         bool ok_l;
         const double lowest=LowestBetween(m_bi-i,m_bi-index_peak,ok_l);
         if(ok_l && lowest<L(index_peak))
            break;

         bool ok_h;
         const double highest=HighestBetween(m_bi-i,m_bi-index_peak,ok_h);
         if(ok_h && highest>H(i))
           {
            i++;
            continue;
           }

         if(PrevHighsLower(m_bi-i))
           {
            const int index_start=i;

            bool flagIsZigzag; int indexZigzag;
            ZigzagGreen(m_bi-index_start,m_bi-index_peak,flagIsZigzag,indexZigzag);

            bool isJustNode_1=true;
            if(flagIsZigzag && m_s.just_node_1)
              {
               isJustNode_1=false;
               if(Valid(indexZigzag) && H(indexZigzag)<=H(0))
                  isJustNode_1=true;
              }

            if(flagIsZigzag && isJustNode_1)
              {
               startIdx=m_bi-i;

               const double all=H(i)-L(index_peak);
               if(all<=m_s.max_dollar_hook)
                 {
                  const double part   =H(0)-L(index_peak);
                  const double percent=(all>0.0 ? part*100.0/all : 0.0);
                  if(percent>=m_s.max_pullback_hook)
                    {
                     isSignal=true;
                     break;
                    }
                 }
               else
                  break;
              }
           }
        }

      i++;
     }
  }

//+------------------------------------------------------------------+
bool CHookStrategy::CheckPullbackBuy(CHook *h)
  {
   const double all=h.pricePeak-h.priceStart;
   if(all<=0.0)
      return(false);

   return((h.pricePeak-h.priceEnd)*100.0/all>=m_s.max_pullback_hook);
  }

//+------------------------------------------------------------------+
bool CHookStrategy::CheckPullbackSell(CHook *h)
  {
   const double all=h.priceStart-h.pricePeak;
   if(all<=0.0)
      return(false);

   return((h.priceEnd-h.pricePeak)*100.0/all>=m_s.max_pullback_hook);
  }

//+------------------------------------------------------------------+
bool CHookStrategy::CheckDollarBuy(CHook *h)
  {
   return((h.pricePeak-h.priceStart)<=m_s.max_dollar_hook);
  }

//+------------------------------------------------------------------+
bool CHookStrategy::CheckDollarSell(CHook *h)
  {
   return((h.priceStart-h.pricePeak)<=m_s.max_dollar_hook);
  }

//+------------------------------------------------------------------+
//| f_adjusted_sl. Pulling the stop closer also pulls the target in,  |
//| because the target is derived from the stop distance and R:R.     |
//+------------------------------------------------------------------+
double CHookStrategy::AdjustedSL(const double entry,const double raw_sl)
  {
   if(!m_s.enable_sl_reduce || m_s.sl_reduce_percent<=0.0)
      return(raw_sl);

   const double dist=entry-raw_sl;
   return(entry-dist*(1.0-m_s.sl_reduce_percent/100.0));
  }

//+------------------------------------------------------------------+
double CHookStrategy::RiskAmount(const double cap)
  {
   return(cap*m_s.risk_percent/100.0);
  }

//+------------------------------------------------------------------+
int CHookStrategy::MinutesSinceLastTrade(void)
  {
   return((int)((BarTime()-m_last_open_time)/60));
  }

//+------------------------------------------------------------------+
bool CHookStrategy::CanOpenNewTrade(void)
  {
   const bool timeOk=(m_last_open_time==0 ||
                      MinutesSinceLastTrade()>=m_s.min_minutes);

   if(m_s.allow_multi_trade)
      return(timeOk);

   for(int i=0;i<ArraySize(m_list);i++)
     {
      CHook *h=m_list[i];
      if(h!=NULL && h.isConfirmed && !h.isFinish)
         return(false);
     }

   return(timeOk);
  }

//+------------------------------------------------------------------+
//| Drops every pending order except the hook that just became a      |
//| position. Identity follows the Pine source and compares priceEnd. |
//+------------------------------------------------------------------+
void CHookStrategy::ClearOtherPendingOrders(CHook *keep)
  {
   if(m_s.allow_multi_trade)
      return;

   for(int i=ArraySize(m_list)-1;i>=0;i--)
     {
      if(i>ArraySize(m_list)-1)
         continue;

      CHook *h=m_list[i];
      if(h==NULL)
         continue;

      if(h.priceEnd!=keep.priceEnd && !h.isConfirmed && !h.isFinish)
         RemoveHook(h);
     }
  }

//+------------------------------------------------------------------+
void CHookStrategy::SendSignal(const string type,const double entry,
                               const double sl,const double remove)
  {
   m_sig_type   = type;
   m_sig_entry  = entry;
   m_sig_sl     = sl;
   m_sig_remove = remove;
   m_sig_time   = BarTime();

   m_last_type   = type;
   m_last_entry  = entry;
   m_last_sl     = sl;
   m_last_remove = remove;
   m_last_time   = m_sig_time;
  }

//+------------------------------------------------------------------+
void CHookStrategy::SendSignalOff(void)
  {
   m_sig_type   = "";
   m_sig_entry  = 0.0;
   m_sig_sl     = 0.0;
   m_sig_remove = 0.0;
   m_sig_time   = 0;
  }

//+------------------------------------------------------------------+
//| The Pine original deletes boxes, lines and labels here. On the    |
//| canvas nothing is retained between frames, so clearing the flag   |
//| is the whole job.                                                 |
//+------------------------------------------------------------------+
void CHookStrategy::DrawClean(CHook *h)
  {
   h.isDrawn     = false;
   h.resultKind  = HK_RESULT_NONE;
   h.resultNum   = 0;
   h.resultPrice = 0.0;
  }

//+------------------------------------------------------------------+
void CHookStrategy::DrawPosition(CHook *h)
  {
   if(h.indexEnd!=-1)
      h.isDrawn=true;
  }

//+------------------------------------------------------------------+
//| f_draw_result. Numbers are the counts *before* the main loop      |
//| increments them, plus one, exactly as the Pine source passes them.|
//+------------------------------------------------------------------+
void CHookStrategy::DrawResult(CHook *h)
  {
   if(!h.isFinish || h.resultKind!=HK_RESULT_NONE)
      return;

   if(h.isRiskFreeClosed)
     {
      h.resultKind=HK_RESULT_RF;
      h.resultNum =m_cnt_rf+1;
     }
   else if(h.isGetProfit)
     {
      h.resultKind=HK_RESULT_TP;
      h.resultNum =m_cnt_tp+1;
     }
   else
     {
      h.resultKind=HK_RESULT_SL;
      h.resultNum =m_cnt_sl+1;
     }

   const double tr=TrueRange();
   h.resultPrice=(h.IsBuy() ? h.priceTakeProfit+tr*1.5
                            : h.priceTakeProfit-tr*1.5);
  }

//+------------------------------------------------------------------+
//| f_remove_hook. The object stays owned by m_own so that any        |
//| reference still held by the caller remains valid for this bar.    |
//+------------------------------------------------------------------+
void CHookStrategy::RemoveHook(CHook *h)
  {
   SendSignalOff();
   DrawClean(h);

   const int idx=IndexOf(h);
   if(idx>=0)
      ListRemove(idx);
  }

//+------------------------------------------------------------------+
CHook *CHookStrategy::NewHook(const int idxStart,const int idxPeak,const int idxEnd,
                              const double priceStart,const double pricePeak,
                              const double priceEnd,const string typeSignal)
  {
   CHook *h=new CHook();
   if(h==NULL)
      return(NULL);

   h.indexStart = idxStart;
   h.indexPeak  = idxPeak;
   h.indexEnd   = idxEnd;
   h.priceStart = priceStart;
   h.pricePeak  = pricePeak;
   h.priceEnd   = priceEnd;
   h.typeSignal = typeSignal;

   const int n=ArraySize(m_own);
   ArrayResize(m_own,n+1,1024);
   m_own[n]=h;

   return(h);
  }

//+------------------------------------------------------------------+
//| BUY, left-sharp hook (isSharpRightHook == false).                |
//+------------------------------------------------------------------+
bool CHookStrategy::ManageOrderBuyNormal(CHook *h)
  {
   bool didConfirmBuy=false;

   bool flagIsZigzag; int indexZigzag;
   ZigzagGreen(h.indexPeak,h.indexEnd,flagIsZigzag,indexZigzag);

   if(h.priceStart>L(0))
     {
      RemoveHook(h);
     }
   else if(h.pricePeak<H(0) && !flagIsZigzag)
     {
      RemoveHook(h);
     }
   else if(h.pricePeak<H(0))
     {
      if(h.indexEnd-h.indexPeak>2)
        {
         bool flag2; int idx2;
         ZigzagGreen(h.indexPeak,h.indexEnd,flag2,idx2);

         if(flag2)
           {
            if(CheckPullbackBuy(h))
              {
               //--- note: the Pine source has no `else` here, so a hook that
               //--- fails only the dollar test survives to the next bar
               if(CheckDollarBuy(h))
                 {
                  if(CanOpenNewTrade())
                    {
                     h.isConfirmed         = true;
                     h.isOpen              = true;
                     h.priceStopLoss       = AdjustedSL(h.pricePeak,h.priceEnd);
                     h.priceTakeProfit     = h.pricePeak+(h.pricePeak-h.priceStopLoss)*m_s.risk_reward;
                     h.tradeCapitalAtEntry = m_equity;
                     h.tradeOpenTime       = BarTime();
                     h.tradeRiskAmount     = RiskAmount(m_equity);
                     didConfirmBuy         = true;

                     DrawClean(h);
                     DrawPosition(h);
                    }
                  else
                     RemoveHook(h);
                 }
              }
            else
               RemoveHook(h);
           }
        }
      else
         RemoveHook(h);
     }
   else if(h.priceEnd>=L(0))
     {
      h.indexEnd=m_bi;
      h.priceEnd=L(0);

      bool flag3; int idx3;
      ZigzagGreen(h.indexPeak,h.indexEnd,flag3,idx3);

      if(flag3 && m_bi-h.indexPeak>1)
        {
         if(CheckPullbackBuy(h))
            if(CheckDollarBuy(h))
               if(CanOpenNewTrade())
                 {
                  DrawClean(h);
                  h.priceStopLoss   = AdjustedSL(h.pricePeak,h.priceEnd);
                  h.priceTakeProfit = h.pricePeak+(h.pricePeak-h.priceStopLoss)*m_s.risk_reward;
                  h.isOrder         = true;

                  DrawPosition(h);
                  SendSignal("buy",h.pricePeak,h.priceStopLoss,h.priceStart);
                 }
        }
     }

   return(didConfirmBuy);
  }

//+------------------------------------------------------------------+
//| BUY, right-sharp hook (isSharpRightHook == true).                |
//+------------------------------------------------------------------+
bool CHookStrategy::ManageOrderBuySharp(CHook *h)
  {
   bool didConfirmBuy=false;

   if(h.priceEnd>L(0))
     {
      RemoveHook(h);
     }
   else if(h.pricePeak<H(0))
     {
      if(CanOpenNewTrade())
        {
         h.isConfirmed         = true;
         h.isOpen              = true;
         h.priceStopLoss       = AdjustedSL(h.pricePeak,h.priceEnd);
         h.priceTakeProfit     = h.pricePeak+(h.pricePeak-h.priceStopLoss)*m_s.risk_reward;
         h.tradeCapitalAtEntry = m_equity;
         h.tradeOpenTime       = BarTime();
         h.tradeRiskAmount     = RiskAmount(m_equity);
         didConfirmBuy         = true;

         DrawClean(h);
         DrawPosition(h);
         SendSignal("buy",h.pricePeak,h.priceStopLoss,h.priceStart);
        }
      else
         RemoveHook(h);
     }

   return(didConfirmBuy);
  }

//+------------------------------------------------------------------+
//| SELL, left-sharp hook.                                           |
//+------------------------------------------------------------------+
bool CHookStrategy::ManageOrderSellNormal(CHook *h)
  {
   bool didConfirmSell=false;

   bool flagIsZigzag; int indexZigzag;
   ZigzagRed(h.indexPeak,h.indexEnd,flagIsZigzag,indexZigzag);

   if(h.priceStart<H(0))
     {
      RemoveHook(h);
     }
   else if(h.pricePeak>L(0) && !flagIsZigzag)
     {
      RemoveHook(h);
     }
   else if(h.pricePeak>L(0))
     {
      if(h.indexEnd-h.indexPeak>2)
        {
         bool flag2; int idx2;
         ZigzagRed(h.indexPeak,h.indexEnd,flag2,idx2);

         if(flag2)
           {
            if(CheckPullbackSell(h))
              {
               if(CheckDollarSell(h))
                 {
                  if(CanOpenNewTrade())
                    {
                     h.isConfirmed         = true;
                     h.isOpen              = true;
                     h.priceStopLoss       = AdjustedSL(h.pricePeak,h.priceEnd);
                     h.priceTakeProfit     = h.pricePeak-(h.priceStopLoss-h.pricePeak)*m_s.risk_reward;
                     h.tradeCapitalAtEntry = m_equity;
                     h.tradeOpenTime       = BarTime();
                     h.tradeRiskAmount     = RiskAmount(m_equity);
                     didConfirmSell        = true;

                     DrawClean(h);
                     DrawPosition(h);
                     SendSignal("sell",h.pricePeak,h.priceStopLoss,h.priceStart);
                    }
                  else
                     RemoveHook(h);
                 }
               else
                  RemoveHook(h);
              }
            else
               RemoveHook(h);
           }
        }
      else
         RemoveHook(h);
     }
   else if(h.priceEnd<=H(0))
     {
      h.indexEnd=m_bi;
      h.priceEnd=H(0);

      bool flag3; int idx3;
      ZigzagRed(h.indexPeak,h.indexEnd,flag3,idx3);

      if(flag3 && h.indexEnd-h.indexPeak>2)
        {
         if(CheckPullbackSell(h))
            if(CheckDollarSell(h))
               if(CanOpenNewTrade())
                 {
                  DrawClean(h);
                  h.priceStopLoss   = AdjustedSL(h.pricePeak,h.priceEnd);
                  h.priceTakeProfit = h.pricePeak-(h.priceStopLoss-h.pricePeak)*m_s.risk_reward;
                  h.isOrder         = true;

                  DrawPosition(h);
                  SendSignal("sell",h.pricePeak,h.priceStopLoss,h.priceStart);
                 }
        }
     }

   return(didConfirmSell);
  }

//+------------------------------------------------------------------+
//| SELL, right-sharp hook.                                          |
//+------------------------------------------------------------------+
bool CHookStrategy::ManageOrderSellSharp(CHook *h)
  {
   bool didConfirmSell=false;

   if(h.priceEnd<H(0))
     {
      RemoveHook(h);
     }
   else if(h.pricePeak>L(0))
     {
      if(CanOpenNewTrade())
        {
         h.isConfirmed         = true;
         h.isOpen              = true;
         h.priceStopLoss       = AdjustedSL(h.pricePeak,h.priceEnd);
         h.priceTakeProfit     = h.pricePeak-(h.priceStopLoss-h.pricePeak)*m_s.risk_reward;
         h.tradeCapitalAtEntry = m_equity;
         h.tradeOpenTime       = BarTime();
         h.tradeRiskAmount     = RiskAmount(m_equity);
         didConfirmSell        = true;

         DrawClean(h);
         DrawPosition(h);
         SendSignal("sell",h.pricePeak,h.priceStopLoss,h.priceStart);
        }
      else
         RemoveHook(h);
     }

   return(didConfirmSell);
  }

//+------------------------------------------------------------------+
void CHookStrategy::ManageOrder(CHook *h,bool &didBuy,bool &didSell)
  {
   didBuy =false;
   didSell=false;

   if(h.typeSignal=="buy" && !h.isOpen)
     {
      if(!h.isSharpRightHook) didBuy=ManageOrderBuyNormal(h);
      else                    didBuy=ManageOrderBuySharp(h);
     }
   else if(h.typeSignal=="sell" && !h.isOpen)
     {
      if(!h.isSharpRightHook) didSell=ManageOrderSellNormal(h);
      else                    didSell=ManageOrderSellSharp(h);
     }
   else
      SendSignalOff();
  }

//+------------------------------------------------------------------+
//| f_manage_position: risk-free shift, then TP before SL.           |
//+------------------------------------------------------------------+
void CHookStrategy::ManagePosition(CHook *h,bool &didTP,bool &didSL,bool &didRF,
                                   double &pnl,int &dur)
  {
   didTP=false; didSL=false; didRF=false;
   pnl=0.0;     dur=0;

   if(h.isOpen && !h.isFinish)
     {
      //--- move the stop to break-even once the trade is far enough ahead
      if(m_s.enable_risk_free && !h.isRiskFreeActive)
        {
         if(h.typeSignal=="buy")
           {
            const double riskDist=h.pricePeak-h.priceStopLoss;
            if(H(0)>=h.pricePeak+riskDist*m_s.risk_free_trigger)
              {
               h.isRiskFreeActive=true;
               h.priceStopLoss   =h.pricePeak;
              }
           }
         else if(h.typeSignal=="sell")
           {
            const double riskDist=h.priceStopLoss-h.pricePeak;
            if(L(0)<=h.pricePeak-riskDist*m_s.risk_free_trigger)
              {
               h.isRiskFreeActive=true;
               h.priceStopLoss   =h.pricePeak;
              }
           }
        }

      if(h.typeSignal=="buy")
        {
         if(h.priceTakeProfit<H(0))
           {
            h.isGetProfit=true;
            h.isFinish   =true;
           }
         else if(h.priceStopLoss>L(0))
           {
            h.isFinish=true;
            if(h.isRiskFreeActive) h.isRiskFreeClosed=true;
            else                   h.isGetProfit=false;
           }
        }

      if(h.typeSignal=="sell")
        {
         if(h.priceTakeProfit>L(0))
           {
            h.isGetProfit=true;
            h.isFinish   =true;
           }
         else if(h.priceStopLoss<H(0))
           {
            h.isFinish=true;
            if(h.isRiskFreeActive) h.isRiskFreeClosed=true;
            else                   h.isGetProfit=false;
           }
        }
     }

   if(h.isFinish && h.tradeCloseTime==0)
     {
      h.tradeCloseTime       = BarTime();
      h.tradeDurationMinutes = (int)((h.tradeCloseTime-h.tradeOpenTime)/60);

      if(h.isRiskFreeClosed)
        {
         h.tradePnl=0.0;
         didRF     =true;
        }
      else if(h.isGetProfit)
        {
         h.tradePnl=h.tradeRiskAmount*m_s.risk_reward-m_s.spread;
         didTP     =true;
        }
      else
        {
         h.tradePnl=-(h.tradeRiskAmount+m_s.spread);
         didSL     =true;
        }
     }

   DrawResult(h);

   pnl=h.tradePnl;
   dur=h.tradeDurationMinutes;
  }

//+------------------------------------------------------------------+
//| f_check_hook_buy.                                                |
//+------------------------------------------------------------------+
void CHookStrategy::CheckHookBuy(void)
  {
   //--- left side of the hook is sharp
   if(IsRed(0) && IsGreen(1))
     {
      const int index_start_hook=FindStartLeftSharpBuy();
      if(index_start_hook>=0 && PrevLowsHigher(index_start_hook))
        {
         CHook *h=NewHook(index_start_hook,m_bi,m_bi,
                          L(m_bi-index_start_hook),H(0),L(0),"buy");
         if(h!=NULL)
            ListPush(h);
        }
     }

   //--- right side of the hook is sharp
   if(IsGreen(0) && IsRed(1))
     {
      const int index_peak_hook=FindPeakBuy();
      if(index_peak_hook>=0 && m_bi-index_peak_hook>m_s.min_size_sharp)
        {
         bool isSignal; int index_start_hook;
         FindStartRightSharpBuy(index_peak_hook,isSignal,index_start_hook);

         if(isSignal && index_start_hook>=0)
           {
            CHook *h=NewHook(index_start_hook,index_peak_hook,m_bi,
                             L(m_bi-index_start_hook),
                             H(m_bi-index_peak_hook),
                             L(0),"buy");
            if(h!=NULL)
              {
               h.isSharpRightHook = true;
               h.priceStopLoss    = AdjustedSL(h.pricePeak,h.priceEnd);
               h.priceTakeProfit  = h.pricePeak+(h.pricePeak-h.priceStopLoss)*m_s.risk_reward;

               DrawClean(h);
               DrawPosition(h);
               h.isOrder=true;

               SendSignal("buy",h.pricePeak,h.priceStopLoss,h.priceStart);
               ListPush(h);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| f_check_hook_sell.                                               |
//+------------------------------------------------------------------+
void CHookStrategy::CheckHookSell(void)
  {
   if(IsGreen(0) && IsRed(1))
     {
      const int index_start_hook=FindStartLeftSharpSell();
      if(index_start_hook>=0 && PrevHighsLower(index_start_hook))
        {
         CHook *h=NewHook(index_start_hook,m_bi,m_bi,
                          H(m_bi-index_start_hook),L(0),H(0),"sell");
         if(h!=NULL)
            ListPush(h);
        }
     }

   if(IsRed(0) && IsGreen(1))
     {
      const int index_peak_hook=FindPeakSell();
      if(index_peak_hook>=0 && m_bi-index_peak_hook>m_s.min_size_sharp)
        {
         bool isSignal; int index_start_hook;
         FindStartRightSharpSell(index_peak_hook,isSignal,index_start_hook);

         if(isSignal && index_start_hook>=0)
           {
            CHook *h=NewHook(index_start_hook,index_peak_hook,m_bi,
                             H(m_bi-index_start_hook),
                             L(m_bi-index_peak_hook),
                             H(0),"sell");
            if(h!=NULL)
              {
               h.isSharpRightHook = true;

               DrawClean(h);
               h.priceStopLoss   = AdjustedSL(h.pricePeak,h.priceEnd);
               h.priceTakeProfit = h.pricePeak-(h.priceStopLoss-h.pricePeak)*m_s.risk_reward;

               DrawPosition(h);
               h.isOrder=true;
               ListPush(h);

               SendSignal("sell",h.pricePeak,h.priceStopLoss,h.priceStart);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| _todayStartTime. The Pine version resolves an IANA zone; here the |
//| zone is a fixed offset from broker time, set once in the inputs.  |
//+------------------------------------------------------------------+
void CHookStrategy::ComputeDayStart(void)
  {
   const int      shift  = m_s.day_tz_shift_min*60;
   const datetime now_tz = TimeCurrent()+shift;
   const datetime anchor = now_tz-(m_s.day_start_hour*3600+m_s.day_start_minute*60);

   MqlDateTime dt;
   TimeToStruct(anchor,dt);
   dt.hour = m_s.day_start_hour;
   dt.min  = m_s.day_start_minute;
   dt.sec  = 0;

   m_day_start=StructToTime(dt)-shift;
  }

//+------------------------------------------------------------------+
bool CHookStrategy::InStartWindow(void)
  {
   if(m_s.enable_dynamic_start)
      return(BarTime()>=m_day_start);

   return(m_bi>=m_last_bi-m_s.start_main_candle);
  }

//+------------------------------------------------------------------+
//| SECTION 6 - MAIN LOOP, one pass per completed range bar.         |
//+------------------------------------------------------------------+
void CHookStrategy::OnBar(const int bar_index,const int last_bar_index)
  {
   m_bi      = bar_index;
   m_last_bi = last_bar_index;

   SendSignalOff();

   if(m_bi<m_warmup)                      // stands in for Pine's na history
      return;

   if(!InStartWindow())
      return;

   if(m_bi>m_last_bi-m_s.end_main_candle)
      return;

   const int n0=ArraySize(m_list);
   if(n0>0)
     {
      //--- the bound is captured once, the way Pine evaluates `to`, and the
      //--- guard covers hooks removed underneath us during the sweep
      for(int i=n0-1;i>=0;i--)
        {
         if(i>ArraySize(m_list)-1)
            continue;

         CHook *h=m_list[i];
         if(h==NULL)
            continue;

         if(h.isConfirmed && h.isFinish)
            continue;

         if(!h.isConfirmed)
           {
            bool isBuyConfirmed,isSellConfirmed;
            ManageOrder(h,isBuyConfirmed,isSellConfirmed);

            if(isBuyConfirmed)
              {
               m_cnt_buy++;
               m_last_open_time=BarTime();
               ClearOtherPendingOrders(h);
              }

            if(isSellConfirmed)
              {
               m_cnt_sell++;
               m_last_open_time=BarTime();
               ClearOtherPendingOrders(h);
              }
           }

         if(h.isConfirmed && !h.isFinish)
           {
            bool isTP,isSL,isRF; double pnlVal; int durMin;
            ManagePosition(h,isTP,isSL,isRF,pnlVal,durMin);

            if(isTP)
              {
               m_cnt_tp++;
               m_total_profit  += pnlVal;
               m_equity        += pnlVal;
               m_gross_pnl     += pnlVal;
               m_total_dur_min += durMin;
              }

            if(isSL)
              {
               m_cnt_sl++;
               m_total_loss    += MathAbs(pnlVal);
               m_equity        += pnlVal;
               m_gross_pnl     += pnlVal;
               m_total_dur_min += durMin;
              }

            if(isRF)
              {
               m_cnt_rf++;
               m_equity        += pnlVal;
               m_gross_pnl     += pnlVal;
               m_total_dur_min += durMin;
              }

            if(isTP || isSL || isRF)
              {
               if(m_equity>m_peak_equity)
                  m_peak_equity=m_equity;

               if(m_peak_equity>0.0)
                 {
                  const double dd=(m_peak_equity-m_equity)/m_peak_equity*100.0;
                  if(dd>m_max_dd)
                     m_max_dd=dd;
                 }
              }
           }
        }
     }

   CheckHookBuy();
   CheckHookSell();
  }

//+------------------------------------------------------------------+
//| Steps every bar the aggregator has finished since the last call.  |
//|                                                                   |
//| last_bar_index is the newest bar of the batch, which reproduces    |
//| Pine exactly: during the historical pass it is the final bar, and  |
//| live it is the bar that just closed.                              |
//+------------------------------------------------------------------+
bool CHookStrategy::ProcessNew(void)
  {
   if(m_agg==NULL)
      return(false);

   const int last=m_agg.Total()-1;
   if(m_processed>last)
      return(false);

   ComputeDayStart();

   while(m_processed<=last)
     {
      OnBar(m_processed,last);
      m_processed++;
     }

   return(true);
  }
//+------------------------------------------------------------------+
#endif // RC_RANGE_STRATEGY_MQH
