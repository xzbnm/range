#ifndef RC_RANGE_DRAWING_STORE_MQH
#define RC_RANGE_DRAWING_STORE_MQH

#include "RangeDrawingModel.mqh"

//+------------------------------------------------------------------+
bool RangeDrawingStoreSave(const string file,SDrawing &items[],const int count)
  {
   if(file=="")
      return(false);

   const int fh=FileOpen(file,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(fh==INVALID_HANDLE)
      return(false);

   for(int i=0;i<count;i++)
     {
      if(!items[i].alive)
         continue;

      FileWrite(fh,items[i].type,
                DoubleToString(items[i].bar1,2),  DoubleToString(items[i].price1,8),
                DoubleToString(items[i].bar2,2),  DoubleToString(items[i].price2,8),
                DoubleToString(items[i].price3,8),
                (int)items[i].clr,items[i].width,items[i].text);
     }

   FileClose(fh);
   return(true);
  }

//+------------------------------------------------------------------+
bool RangeDrawingStoreLoad(const string file,SDrawing &items[],int &count)
  {
   count=0;
   ArrayResize(items,0);

   if(file=="" || !FileIsExist(file))
      return(false);

   const int fh=FileOpen(file,FILE_READ|FILE_CSV|FILE_ANSI,',');
   if(fh==INVALID_HANDLE)
      return(false);

   while(!FileIsEnding(fh))
     {
      SDrawing d;
      d.type=(int)FileReadNumber(fh);
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
        {
         if(ArrayResize(items,count+1,64)<0)
           {
            FileClose(fh);
            count=0;
            ArrayResize(items,0);
            return(false);
           }
         items[count]=d;
         count++;
        }
     }

   FileClose(fh);
   return(true);
  }

#endif
