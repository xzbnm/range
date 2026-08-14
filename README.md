# Range Chart for MetaTrader 5

TradingView-style range bars for MT5, rendered on a `CCanvas` overlay with a
top-left panel for the range size, plus the **Hook Sharp v7.1** signal
indicator ported from Pine Script and running on those range bars.

## Install

Copy all five files into `MQL5/Indicators/` in your terminal's data folder
(`File > Open Data Folder`):

```
RangeChartCanvas.mq5     the indicator
RangeAggregator.mqh      the range bar engine
RangeDrawings.mqh        drawing tools, toolbar and editing
RangeStrategy.mqh        the Hook Sharp v7.1 signal logic
RangeDashboard.mqh       trade overlays and the performance panel
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

## Hook Sharp v7.1

The TradingView indicator is ported in `RangeStrategy.mqh` and drives a
paper-trading account: it finds hooks, places pending orders, turns them into
positions, manages stop and target, and keeps the running statistics.

### What it runs on

Pine executes once per confirmed chart bar. Here the chart bar is a **completed
range bar**, so the strategy is stepped once for every bar the aggregator
appends, oldest first. The forming bar is never evaluated, which is the MQL
equivalent of `barstate.isconfirmed` and means the result cannot repaint.

`bar_index` maps to the aggregator's bar index and `high[n]` to that bar's
high, so every index in the Pine source carries over unchanged. During the
rebuild the whole week of range bars is replayed in one pass, exactly as
TradingView replays history, and after that each new bar is stepped as it
closes.

### What it draws

Every pending order and open position gets the box, entry, stop and target the
Pine version draws, and a finished trade leaves its `TP n` / `SL n` / `RF n`
tag behind. Anchors are (bar index, price), so the overlays stay welded to
their bars through scroll, zoom and price scaling. A live position has a solid
entry line, a pending order a dashed one.

The canvas is XRGB with no alpha channel, so a fill cannot be blended against
what is already on it. The entry-to-stop band is therefore painted **before**
the bars: it tints the background and the grid, and every bar is then drawn
straight over it, so the price action inside a position stays fully readable.
The outline and the three levels are painted after the bars, so they stay on
top.

The stats table becomes a canvas panel at the top right, carrying the same
rows: capital, net P/L, return, max drawdown, win rate, profit factor, R:R,
trade counts, and the suggested spread. Two rows are new - average trade
duration and open/pending count - plus a footer with the last signal that
`sendSignal()` emitted. `D` toggles the panel.

### Inputs

Grouped under `Hook strategy`, `Hook / detection`, `Hook / money management`
and `Hook / window and timing`. Each one maps to the Pine input of the same
meaning and keeps its default, so an untouched load reproduces the Pine
defaults: range hooks up to $100, 10% minimum pullback, 15 bars maximum, 10%
risk on $100 of capital at 1:2, 10 minutes between trades, one trade at a
time, dynamic start at 01:30.

Three inputs behave differently from Pine, because the platform leaves no
choice:

| Input | Difference |
|---|---|
| `Day timezone shift from broker time` | Pine takes an IANA zone name; MQL has no timezone database, so the day start is expressed as an offset in minutes from broker time. `0` means the day-start hour is read in broker time. |
| `Min hook bars` | Declared by the Pine source but never used by its logic. Kept for parity, wired to nothing. |
| `Dashboard labels in Persian` | Off by default. `CCanvas` renders text without complex-script shaping, so Persian letters come out unjoined on most terminals. |

`Start at bar` only applies when dynamic start is off, and like Pine it is
measured against the newest bar, so during the historical replay it selects
the last N bars and in real time it is always satisfied.

### Faithfulness

The port keeps the quirks of the original rather than tidying them, because
tidying them would change which trades are taken:

* Pine's `for i = a to b` counts **downwards** when `b < a`. With the default
  look-back of 0, `f_are_prev_lows_higher` therefore still tests the bar before
  the start. The port reproduces the direction, not the intent.
* `f_are_prev_lows_higher` and `f_are_prev_highs_lower` are not mirror images -
  only the sell side is guarded by `len > 0`.
* The buy and sell branches of `f_manage_order_*_normal` differ: the buy side
  has no `else` on the hook-size test, so a hook that fails only that test
  survives to the next bar, and the second confirmation path uses `> 1` on the
  buy side against `> 2` on the sell side.
* `f_find_start_index_right_sharp_sell` checks lowest before highest, the
  reverse of the buy version.
* `f_clear_other_pending_orders` identifies hooks by `priceEnd`.

A warm-up guard skips the first `max(40, max hook bars + 2)` bars, standing in
for the `na` history Pine propagates before enough bars exist.

### Checking the port

```
python3 verify_engine.py      # range bar rules against live TradingView bars
python3 verify_strategy.py    # the hook logic, as a reference mirror
```

`verify_strategy.py` is a transliteration of `RangeStrategy.mqh`. It replays a
synthetic tick path through the same bar rules, steps the hook logic over the
result, and asserts the invariants that have to hold if the control flow and
the arithmetic are right: equity equals capital plus the sum of closed P/L,
the TP/SL/RF counts match the result tags, a TP pays `risk x R:R - spread` and
an SL costs `risk + spread`, risk is the configured share of equity at entry,
no trade closes before it opens, and with concurrent trades off no two
positions ever overlap.
