# Range Chart for MetaTrader 5

TradingView-style range bars for MT5, rendered on a `CCanvas` overlay with a
top-left panel for the range size.

## Install

Copy all three files into `MQL5/Indicators/` in your terminal's data folder
(`File > Open Data Folder`):

```
RangeChartCanvas.mq5     the indicator
RangeAggregator.mqh      the range bar engine
RangeDrawings.mqh        drawing tools, toolbar and editing
```

They live in the same folder, so there is nothing to put under `Include/`.
Compile `RangeChartCanvas.mq5` in MetaEditor, then drop it on an XAUUSD chart.

## The rules it implements

Derived from, and verified against, live TradingView range-100 bars on XAUUSD:

1. Every completed bar is exactly `R` tall (`R = Range x tick size`).
2. High and low float with the path price actually traversed - the box is
   **not** anchored to the open, so the open often sits mid-bar.
3. A bar closes the moment `high - low` reaches `R`, on the edge just touched.
4. The next bar opens **one tick beyond** that edge, in the break direction.

Reference bars used for verification:

```
bar N-1   O 4403.48   H 4404.16   L 4403.16   C 4403.16
bar N     O 4403.15   H 4403.55   L 4402.55   C 4403.55
```

`4403.15` is not fed to the engine - it is derived by rule 4 from the previous
close of `4403.16`. Run `python3 verify_engine.py` to check both bars.

## Data

Seeded from the **start of the current week**, using real ticks
(`CopyTicksRange`). If the broker has no tick history for that window, it falls
back to M1 bars with a direction-based path guess
(`bullish -> O L H C`, `bearish -> O H L C`). After seeding, it stays live off
`CopyTicksRange`, so no ticks are dropped between `OnCalculate` calls.

## Chart style

Range charts on TradingView are drawn as OHLC bars, so that is the default
here: a high-low stem with the open as a nub on the left and the close as a
nub on the right. The `Bars`/`Candles` button in the panel switches rendering
live, and `Chart style` sets which one it starts on.

Since a range bar always closes on one of its two edges, the close nub sits at
the top or the bottom of the stem, never in between.

## Panel & controls

Navigation follows TradingView: the wheel zooms, dragging pans.

| Input | Action |
|---|---|
| Range box + Apply | rebuild at a new range size (`Enter` also applies) |
| Bars / Candles | switch how each bar is drawn |
| wheel | zoom horizontally, anchored on the bar under the cursor |
| shift + wheel | pan horizontally |
| ctrl + wheel | zoom the price scale |
| drag on the chart | pan; dragging past the newest bar widens the right shift |
| drag vertically on the chart | switches the price scale to manual |
| drag on the price axis | stretch or compress the price scale |
| `>\|` button, bottom right | back to the live edge and auto scale |
| arrows / Home / End | pan, jump to oldest, jump to live |

`Right shift` sets how much empty space is kept between the newest bar and
the price axis, the same idea as MT5's chart shift, measured in bars so it
holds its proportions through zoom. Dragging the chart past the newest bar
widens it further; `>|` or `End` restores the configured value.

A crosshair follows the cursor with a price tag on the axis and a time tag
under the chart, and the header switches to the OHLC of whichever bar is
hovered.

The forming bar is drawn live, outlined in white, with a dashed line and a
price tag at its current close.

MT5's own mouse scrolling is turned off while the indicator is attached, so the
chart underneath cannot drift out from under the canvas. It is restored on
removal.

## Known limits of the canvas approach

The canvas paints over the whole chart, so MT5 indicators, EAs, drawing
objects and the native scale are not visible on it, and the Strategy Tester
is not usable. Scroll and zoom are the handlers above, not MT5's own.

## Drawing tools

A draggable toolbar sits over the chart, moved by the grip on its left edge.
Pick a tool, draw, and it reverts to the crosshair, the same one-shape-per-pick
behaviour TradingView has.

| Tool | Points | Notes |
|---|---|---|
| Crosshair | - | selection mode |
| Trend line | 2 | |
| Ray | 2 | extends to the right edge |
| Horizontal line | 1 | spans the plot, tagged on the price axis |
| Vertical line | 1 | |
| Rectangle | 2 | |
| Fib retracement | 2 | 0 / .236 / .382 / .5 / .618 / .786 / 1 |
| Measure | 2 | price delta, percent, bar count |
| Text | 1 | |
| Note | 1 | callout box with a leader |
| Long position | 2 | entry, target, stop with R:R |
| Short position | 2 | |

Two-point tools are drawn by dragging; a plain click drops one at a default
size. One-point tools place on click.

### Editing

Click a shape to select it. Handles appear at its anchors: drag a handle to
reshape, drag the body to move, and press `Delete` to remove it. `Esc` cancels
a placement and clears the selection. The strip under the toolbar cycles the
colour and line width and holds a delete button; the trash cell at the end of
the toolbar deletes the selection too.

Anchors are stored as (bar index, price), never pixels, so shapes stay welded
to their bars through scroll, zoom and price scaling.

### Persistence

Drawings are written to `MQL5/Files/RC_<symbol>_<range>.csv` on every change
and reloaded on attach. Each range size keeps its own file, because changing
the range renumbers the bars the anchors point at.
