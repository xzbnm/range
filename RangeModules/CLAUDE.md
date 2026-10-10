# Project brief

Range Chart for MetaTrader 5. This project builds synthetic range bars, paints them with `CCanvas`, and provides chart navigation and user drawing tools. The Hook Sharp strategy and its paper-trading engine have been removed. Do not add strategy behavior to the chart or drawing modules.

## Layout

```text
RangeChartCanvas.mq5                 indicator entry point (repository root)
RangeModules/
  RangeAggregator.mqh                range-bar engine
  RangeChartRenderer.mqh              grid, axis, and range-bar painting
  RangeDrawingModel.mqh               drawing records, tools, and projection
  RangeDrawingStore.mqh               drawing CSV persistence
  RangeDrawings.mqh                   drawing editing and rendering
  RangeStrategyData.mqh               future strategy-neutral trade record
  RangeStrategyStore.mqh              future strategy CSV persistence
  README.md                           install and user documentation
  CLAUDE.md                           this working brief
  verify_engine.py                    range bar reference check
```

Compile only `RangeChartCanvas.mq5`. Keep each `.mqh` in `RangeModules/`; the main file includes them by relative path. Every header uses an include guard.

## Module boundaries

- `CRangeAggregator` owns the bar array and tick/M1 conversion. It has no chart, drawing, storage, or strategy dependency.
- `CRangeChartRenderer` paints only chart grid, price labels, OHLC bars, and the forming-bar close. `Render()` in the main file owns the full-frame order and user interface composition.
- `RangeDrawingModel.mqh` owns `SDrawing`, `SView`, tool identifiers, palette, and pixel/data conversion.
- `CDrawings` owns the in-memory drawing collection, hit testing, editing, toolbar, and shape rendering. It delegates serialization to `RangeDrawingStore.mqh`.
- `CStrategyStore` and `STradeRecord` are dormant extension points. They are independent of the chart and drawing classes and have no caller in the indicator.

## Range engine invariants

The range size is exactly `R`; high and low track the actual path instead of anchoring to the open; a bar closes at the first tick that makes the high-low span reach `R`; and the next bar opens one tick beyond the edge in the break direction. `Rebuild()` seeds from the current week's ticks and falls back to M1 path estimation if no tick history is available. `PumpLive()` keeps the engine fed between calculations.

Do not change these behaviors while removing strategy logic or moving render code. `verify_engine.py` is the existing reference mirror for the range engine.

## Rendering order

`Render()` must keep the projection available before dependent drawing layers. The frame order is:

1. Erase canvas and compute visible bar/price extent.
2. Set `g_view` projection.
3. Draw grid and price axis through `CRangeChartRenderer`.
4. Draw completed and forming OHLC bars.
5. Draw the forming close line/tag.
6. Draw user shapes, selection/placement previews, crosshair, header, toolbar, and status text.
7. Update the canvas.

The drawing tools' manual long/short position shapes are annotations only; no trade logic is connected to them.

## Persistence

Drawing files stay in `MQL5/Files/` as `RC_<symbol>_<range>.csv`. Preserve the existing field order and contents so saved drawings remain loadable.

Future trade records use `STradeRecord` in `RangeStrategyData.mqh` and `CStrategyStore` in `RangeStrategyStore.mqh`. Initialize records with `StrategyRecordInit()`. CSV rows start with schema version `1` and are stored in `MQL5/Files/RC_trades.csv` by default. The store rejects unsupported schema versions. The indicator must not instantiate or call this store until a separate strategy is explicitly added. Do not couple it to a particular strategy or silently change its schema.

Version 1 columns are `schema_version`, `trade_id`, `strategy_id`, `symbol`, `range_ticks`, `direction`, `entry_time`, `entry_price`, `stop_price`, `target_price`, `exit_time`, `exit_price`, `outcome`, `pnl`, and a trailing `END` row marker. Loading rejects incomplete rows and unsupported schema versions while accepting a genuinely empty file. Append requires nonempty trade and strategy IDs and rejects commas or line breaks in all text fields. Direction values are `1` long and `-1` short; outcomes are `0` open, `1` win, `2` loss, `3` breakeven, and `4` cancelled.

## Platform constraints

- MQL5 `CCanvas` has no alpha channel in this project; render in explicit order.
- Strategy code, signal inputs, trade overlays, and performance dashboards do not belong in the current chart.
- No MQL compiler is available in the development environment; compilation must be checked in MetaEditor when available.
- Do not add or run tests unless the user requests it; report when compilation or behavioral checks were not run.
