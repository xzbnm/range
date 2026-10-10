#ifndef RC_RANGE_STRATEGY_STORE_MQH
#define RC_RANGE_STRATEGY_STORE_MQH

#include "RangeStrategyData.mqh"

//+------------------------------------------------------------------+
class CStrategyStore
  {
private:
   string m_file;

public:
                     CStrategyStore(void): m_file("RC_trades.csv") {}

   void              SetFile(const string file) { m_file=file; }
   bool              Append(const STradeRecord &record);
   bool              Load(STradeRecord &records[]);
  };

//+------------------------------------------------------------------+
bool CStrategyStore::Append(const STradeRecord &record)
  {
   if(m_file=="" || record.schema_version!=RC_TRADE_SCHEMA_VERSION ||
      record.trade_id=="" || record.strategy_id=="")
      return(false);

   const int fh=FileOpen(m_file,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(fh==INVALID_HANDLE)
      return(false);

   if(!FileSeek(fh,0,SEEK_END))
     {
      FileClose(fh);
      return(false);
     }

   const uint written=FileWrite(fh,record.schema_version,record.trade_id,
             record.strategy_id,record.symbol,record.range_ticks,
             record.direction,(long)record.entry_time,
             DoubleToString(record.entry_price,8),
             DoubleToString(record.stop_price,8),
             DoubleToString(record.target_price,8),
             (long)record.exit_time,DoubleToString(record.exit_price,8),
             record.outcome,DoubleToString(record.pnl,8));

   FileClose(fh);
   return(written>0);
  }

//+------------------------------------------------------------------+
bool CStrategyStore::Load(STradeRecord &records[])
  {
   ArrayResize(records,0);
   if(m_file=="" || !FileIsExist(m_file))
      return(false);

   const int fh=FileOpen(m_file,FILE_READ|FILE_CSV|FILE_ANSI,',');
   if(fh==INVALID_HANDLE)
      return(false);

   int count=0;
   while(!FileIsEnding(fh))
     {
      STradeRecord row;
      row.schema_version=(int)FileReadNumber(fh);
      if(FileIsEnding(fh))
         break;

      row.trade_id   =FileReadString(fh);
      row.strategy_id=FileReadString(fh);
      row.symbol     =FileReadString(fh);
      row.range_ticks=(int)FileReadNumber(fh);
      row.direction  =(int)FileReadNumber(fh);
      row.entry_time =(datetime)(long)FileReadNumber(fh);
      row.entry_price=FileReadNumber(fh);
      row.stop_price =FileReadNumber(fh);
      row.target_price=FileReadNumber(fh);
      row.exit_time  =(datetime)(long)FileReadNumber(fh);
      row.exit_price =FileReadNumber(fh);
      row.outcome    =(int)FileReadNumber(fh);
      row.pnl        =FileReadNumber(fh);

      if(row.schema_version!=RC_TRADE_SCHEMA_VERSION)
        {
         FileClose(fh);
         ArrayResize(records,0);
         return(false);
        }

      if(ArrayResize(records,count+1,64)<0)
        {
         FileClose(fh);
         ArrayResize(records,0);
         return(false);
        }
      records[count]=row;
      count++;
     }

   FileClose(fh);
   return(true);
  }

#endif
