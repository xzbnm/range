#ifndef RC_NODAL_COUNTING_MODEL_MQH
#define RC_NODAL_COUNTING_MODEL_MQH

struct SNodalSettings
  {
   int   start_point;
   int   end_point;
   bool  symmetry;
   bool  draw;
   int   text_size;
   color colors[8];
  };

struct SNodalNode
  {
   int    index_pre_node;
   int    index_node;
   int    index_correction;
   int    number_node;
   double low_pre_node;
   double high_node;
   double low_correction;
   double amount_correction;
  };

void NodalSettingsInit(SNodalSettings &settings)
  {
   settings.start_point=2200;
   settings.end_point=0;
   settings.symmetry=true;
   settings.draw=true;
   settings.text_size=3; // Normal
   settings.colors[0]=clrWhite;
   settings.colors[1]=clrYellow;
   settings.colors[2]=clrAqua;
   settings.colors[3]=clrLime;
   settings.colors[4]=clrOrange;
   settings.colors[5]=clrMagenta;
   settings.colors[6]=clrBlue;
   settings.colors[7]=clrRed;
  }

#endif
