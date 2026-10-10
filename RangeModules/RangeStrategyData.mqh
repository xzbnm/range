#ifndef RC_RANGE_STRATEGY_DATA_MQH
#define RC_RANGE_STRATEGY_DATA_MQH

#define RC_TRADE_SCHEMA_VERSION 1

enum ENUM_RC_TRADE_DIRECTION
  {
   RC_TRADE_SHORT = -1,
   RC_TRADE_LONG  = 1
  };

enum ENUM_RC_TRADE_OUTCOME
  {
   RC_TRADE_OPEN      = 0,
   RC_TRADE_WIN       = 1,
   RC_TRADE_LOSS      = 2,
   RC_TRADE_BREAKEVEN = 3,
   RC_TRADE_CANCELLED = 4
  };

//--- Version 1 is intentionally independent of any one signal algorithm.
struct STradeRecord
  {
   int      schema_version;
   string   trade_id;
   string   strategy_id;
   string   symbol;
   int      range_ticks;
   int      direction;
   datetime entry_time;
   double   entry_price;
   double   stop_price;
   double   target_price;
   datetime exit_time;
   double   exit_price;
   int      outcome;
   double   pnl;
  };

void StrategyRecordInit(STradeRecord &record)
  {
   record.schema_version=RC_TRADE_SCHEMA_VERSION;
   record.trade_id="";
   record.strategy_id="";
   record.symbol="";
   record.range_ticks=0;
   record.direction=RC_TRADE_LONG;
   record.entry_time=0;
   record.entry_price=0.0;
   record.stop_price=0.0;
   record.target_price=0.0;
   record.exit_time=0;
   record.exit_price=0.0;
   record.outcome=RC_TRADE_OPEN;
   record.pnl=0.0;
  }

#endif
