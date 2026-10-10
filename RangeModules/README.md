# Range Chart for MetaTrader 5

A TradingView-style range chart for MT5. It builds range bars from market ticks and renders them on a `CCanvas` overlay. It has no active signal or trading strategy.

## Install

Copy `RangeChartCanvas.mq5` and the `RangeModules` folder into the same directory under your terminal's `MQL5/Indicators/` folder. Keep the folder name `RangeModules` so the relative includes resolve. Compile only `RangeChartCanvas.mq5` in MetaEditor, then add it to a chart.

```text
MQL5/Indicators/
  RangeChartCanvas.mq5
  RangeModules/
    RangeAggregator.mqh
    RangeChartRenderer.mqh
    RangeDrawingModel.mqh
    RangeDrawingStore.mqh
    RangeDrawings.mqh
    RangeStrategyData.mqh
    RangeStrategyStore.mqh
```

## Range bars

The bar engine implements these rules, checked against live TradingView XAUUSD range-100 bars:

1. Each completed bar is exactly `R` tall (`R = Range × tick size`).
2. High and low follow the traversed price path; the open does not anchor the range.
3. The bar closes as soon as its high-low range reaches `R`, on the edge just touched.
4. The next bar opens one tick beyond that edge, in the direction of the break.

The indicator seeds from the start of the current week using `CopyTicksRange`. If the broker has no tick history for that period, it falls back to M1 bars and estimates the intrabar path from candle direction. After seeding, it continues from live ticks.

## Chart and controls

Bars (OHLC) is the default style; the panel switches between Bars and Candles. The mouse wheel zooms, dragging pans, and the chart supports crosshair price/time tags and a live forming-bar outline.

| Control | Action |
|---|---|
| Range box + Apply | Rebuild at a new range size; Enter also applies |
| Bars / Candles | Switch rendering style |
| Wheel | Zoom horizontally around the bar under the pointer |
| Shift + wheel | Pan horizontally |
| Ctrl + wheel | Zoom the price scale |
| Drag chart | Pan; dragging beyond the newest bar widens the right shift |
| Drag vertically on chart | Switch to manual price scaling |
| Drag price axis | Stretch or compress the price scale |
| `>|`, End | Return to the live edge and automatic scale |
| Arrows, Home | Pan, jump to oldest bar, or return to live |

The canvas covers the chart area, so native MT5 indicators, drawing objects, and scale are not visible above it. The Strategy Tester is not supported by this canvas-based indicator.

## Drawing tools

The movable toolbar supports crosshair, trend line, ray, horizontal/vertical lines, rectangle, Fibonacci retracement, measure, text, note, and long/short position drawings. These position tools are chart annotations; they do not place or manage trades.

Click a shape to select it. Drag its handles to reshape it, drag its body to move it, and press Delete to remove it. Esc cancels placement and clears selection. Anchors are stored as `(bar index, price)` so drawings remain attached while the chart is panned or zoomed.

Drawings are saved as CSV in the terminal's `MQL5/Files/` folder, one file per symbol and range size: `RC_<symbol>_<range>.csv`. The existing file format is retained.

## Modules and future strategies

| Module | Responsibility |
|---|---|
| `RangeChartCanvas.mq5` | Inputs, MT5 events, rebuilds, and full-frame composition |
| `RangeAggregator.mqh` | Tick/M1 input and range-bar construction |
| `RangeChartRenderer.mqh` | Grid, price axis, OHLC bars, and forming-bar close |
| `RangeDrawingModel.mqh` | Drawing records, tools, and chart coordinate projection |
| `RangeDrawings.mqh` | Drawing editing, hit testing, toolbar, and drawing rendering |
| `RangeDrawingStore.mqh` | Backward-compatible drawing CSV read/write |
| `RangeStrategyData.mqh` | Strategy-independent trade record and common enums |
| `RangeStrategyStore.mqh` | Versioned CSV persistence for future strategy records |

No strategy currently calls the strategy data or store modules. Future strategies should initialize `STradeRecord` with `StrategyRecordInit()` and pass records to `CStrategyStore` rather than writing files directly. Its default file is `RC_trades.csv` under `MQL5/Files/`; each row begins with schema version `1`, and the store rejects unsupported versions so a migration can be added deliberately. This is file-backed persistence, not a relational database.

The version 1 row columns are `schema_version`, `trade_id`, `strategy_id`, `symbol`, `range_ticks`, `direction`, `entry_time`, `entry_price`, `stop_price`, `target_price`, `exit_time`, `exit_price`, `outcome`, `pnl`, and a trailing `END` row marker. The marker lets the loader reject incomplete records. Append requires a trade ID and strategy ID; commas and line breaks are rejected in all text fields so CSV columns remain aligned. Direction is `1` for long and `-1` for short. Outcome is `0` open, `1` win, `2` loss, `3` breakeven, or `4` cancelled.

## Source checks

`verify_engine.py` compares the range-bar rules with two reference bars. No Hook Sharp source, strategy simulator, strategy inputs, or trade dashboard is included.
