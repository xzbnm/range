# Nodal Counting module

This module adapts the supplied Pine v6 `nLib_Range_ex_2_developer` NDS behavior as an optional overlay on the range bars built by `RangeChartCanvas.mq5`. It is not a separately compiled MQL5 indicator. Compile the root `RangeChartCanvas.mq5` entry point.

## Files

- `NodalCountingModel.mqh`: settings and pivot/correction-node records.
- `NodalCountingEngine.mqh`: independent up/down reversal detection, correction updates, sorting, count assignment, and symmetry reductions.
- `NodalCountingCanvas.mqh`: overlay label projection, visibility control, and the CCanvas settings panel.

The engine receives the current synthetic OHLC range bars. It confirms a rising-leg low on the first bearish bar and a falling-leg high on the first bullish bar, then carries on with correction updates, pairwise node reduction rules, and optional symmetry comparisons. `start_point` and `end_point` constrain the absolute bar-index window as the Pine example does; they are not pivot lengths. The start and end of the active count window are marked with small `S` and `E` ticks at the bottom of the chart. The default panel values mirror the example inputs (2200/0, symmetry on, Normal text, and its eight colors).

The source's label drawing is active while its connecting-line drawing is commented out. This module therefore displays count labels above up nodes and below down nodes. The `NDS ON/OFF` control beside the Range controls changes visibility, and `...` opens the CCanvas-only settings panel. Click either bar-window value, type digits, and press Enter to apply it. Click a color swatch to cycle its color. No chart objects are created for this module.
