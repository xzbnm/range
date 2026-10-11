"""Exercise the actual MQL engine through a small C++ compatibility adapter.

This checks counting, not MetaTrader chart rendering or the terminal runtime.
Requires Python and g++ on PATH. Generated build files stay in a temporary folder.
"""
from pathlib import Path
import re
import subprocess
import tempfile

MODULE = Path(__file__).resolve().parents[1] / 'Indicators' / 'NodalCounting'
model = (MODULE / 'NodalCountingModel.mqh').read_text()
engine = (MODULE / 'NodalCountingEngine.mqh').read_text()
engine = re.sub(r'^#include.*$', '', engine, flags=re.MULTILINE)
engine = re.sub(r'SNodalNode\s+(m_nodes_\w+)\[\];', r'std::vector<SNodalNode> \1;', engine)
engine = engine.replace('m_aggregator.', 'm_aggregator->')
engine = engine.replace('aggregator.', 'aggregator->')
adapter = r'''
#include <vector>
#include <algorithm>
#include <cassert>
#include <iostream>
using color = int;
enum {clrWhite,clrYellow,clrAqua,clrLime,clrOrange,clrMagenta,clrBlue,clrRed};
template<class A, class B> auto MathMax(A a,B b) { return std::max<double>(a,b); }
template<class A, class B> auto MathMin(A a,B b) { return std::min<double>(a,b); }
template<class T> int ArraySize(const std::vector<T>& a) { return int(a.size()); }
template<class T> void ArrayResize(std::vector<T>& a,int n) { a.resize(n); }
template<class T> void ArrayRemove(std::vector<T>& a,int start,int count) {
  a.erase(a.begin()+start,a.begin()+start+count);
}
struct SRangeBar { double open, high, low, close; };
class CRangeAggregator {
public:
  std::vector<SRangeBar> bars;
  bool forming=false;
  SRangeBar current{};
  int Total() const { return int(bars.size()); }
  bool HasCurrent() const { return forming; }
  bool Current(SRangeBar& b) const { b=current; return forming; }
  bool Get(int i,SRangeBar& b) const {
    if(i<0 || i>=Total()) return false;
    b=bars[i]; return true;
  }
};
'''
cases = r'''
int main() {
  SNodalSettings settings; NodalSettingsInit(settings);
  CNodalCountingEngine engine;
  SNodalNode preview;
  bool preview_up=false;
  CRangeAggregator falling;
  falling.bars={{120,121,110,111},{110,111,100,101},{100,101,90,91}};
  engine.Rebuild(&falling,settings);
  assert(engine.DownCount()==0 && engine.UpCount()==0);
  falling.forming=true; falling.current={90,100,89,99};
  engine.Rebuild(&falling,settings);
  assert(engine.DownCount()==0); // unclosed green candle cannot confirm
  assert(engine.GetProvisional(preview,preview_up));
  assert(!preview_up && preview.index_node==3 && preview.high_node==89);
  assert(engine.DownCount()==0 && engine.UpCount()==0);
  falling.current={90,100,88,89}; // green turns red: cancel the preview
  engine.Rebuild(&falling,settings);
  assert(!engine.GetProvisional(preview,preview_up));
  falling.current={90,100,87,99};
  engine.Rebuild(&falling,settings);
  assert(engine.GetProvisional(preview,preview_up));
  assert(preview.high_node==87);
  falling.current={90,100,89,99};
  falling.bars.push_back(falling.current);
  falling.current={100,100,100,100};
  engine.Rebuild(&falling,settings);
  SNodalNode node;
  assert(engine.GetDown(engine.DownCount()-1,node));
  assert(node.number_node==1 && node.index_node==3 && node.high_node==89);
  assert(!engine.GetProvisional(preview,preview_up));
  falling.bars.push_back({100,110,99,109});
  engine.Rebuild(&falling,settings);
  assert(engine.GetDown(engine.DownCount()-1,node));
  assert(node.index_node==3 && node.low_correction==110);
  std::cout << "PASS: falling -> closed green confirms low and updates correction\n";

  CRangeAggregator rising;
  rising.bars={{90,100,89,99},{100,110,99,109},{110,120,109,119}};
  engine.Rebuild(&rising,settings);
  assert(engine.UpCount()==0 && engine.DownCount()==0);
  rising.forming=true; rising.current={120,121,110,111};
  engine.Rebuild(&rising,settings);
  assert(engine.UpCount()==0);
  assert(engine.GetProvisional(preview,preview_up));
  assert(preview_up && preview.index_node==3 && preview.high_node==121);
  settings.end_point=2; // counting window excludes the live candle
  engine.Rebuild(&rising,settings);
  assert(!engine.GetProvisional(preview,preview_up));
  settings.end_point=0;
  engine.Rebuild(&rising,settings);
  rising.bars.push_back(rising.current);
  rising.current={110,110,110,110};
  engine.Rebuild(&rising,settings);
  assert(engine.GetUp(engine.UpCount()-1,node));
  assert(node.number_node==1 && node.index_node==3 && node.high_node==121);
  assert(!engine.GetProvisional(preview,preview_up));
  rising.bars.push_back({110,111,100,101});
  engine.Rebuild(&rising,settings);
  assert(engine.GetUp(engine.UpCount()-1,node));
  assert(node.index_node==3 && node.low_correction==100);
  std::cout << "PASS: rising -> closed red confirms high and updates correction\n";

  // Also cover a reversal whose wick stays within the prior candle extreme.
  CRangeAggregator inside;
  inside.bars={{100,110,99,109},{110,120,109,119},{119,119,110,111}};
  engine.Rebuild(&inside,settings);
  assert(engine.GetUp(engine.UpCount()-1,node));
  assert(node.index_node==1 && node.high_node==120);
  inside.bars={{120,121,110,111},{110,111,100,101},{101,110,101,109}};
  engine.Rebuild(&inside,settings);
  assert(engine.GetDown(engine.DownCount()-1,node));
  assert(node.index_node==1 && node.high_node==100);
  std::cout << "PASS: both reversals retain the prior extreme when appropriate\n";
}
'''
with tempfile.TemporaryDirectory(prefix='nodal-regression-') as folder:
    source = Path(folder) / 'regression.cpp'
    binary = Path(folder) / 'regression.exe'
    source.write_text(adapter + model + engine + cases)
    subprocess.run(['g++', '-std=c++17', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
