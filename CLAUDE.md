# Project brief

Range chart for MetaTrader 5, plus the **Hook Sharp v7.1** signal indicator
ported from TradingView Pine Script and running on those range bars.

Read `README.md` for the user-facing description. This file is the working
brief: what the pieces are, why they are shaped the way they are, and which
mistakes are easy to make here.

---

## 1. Layout

```
RangeChartCanvas.mq5     the indicator - inputs, event loop, render order
RangeAggregator.mqh      CRangeAggregator, the range bar engine
RangeDrawings.mqh        CDrawings, SView, the toolbar and coordinate helpers
RangeStrategy.mqh        CHook / CHookStrategy, the ported Pine logic
RangeDashboard.mqh       trade overlays and the performance panel
verify_engine.py         range bar rules vs live TradingView bars
verify_strategy.py       reference mirror of RangeStrategy.mqh + invariants
reference/
  hook_sharp_v7.1.pine   the original Pine source the port came from
```

All five MQL files sit in one folder (`MQL5/Indicators/`), nothing under
`Include/`. Only `RangeChartCanvas.mq5` is compiled.

**Every `.mqh` carries an include guard** (`RC_*_MQH`) and needs one: MQL5 does
not deduplicate `#include`, and the headers are pulled in along more than one
path (`RangeDashboard.mqh` → `RangeStrategy.mqh` → `RangeAggregator.mqh`, while
the `.mq5` includes all of them directly).

## 2. Git

| | |
|---|---|
| Work branch | `claude/tradingview-indicator-to-mql-w0bnr9` |
| Pull request | https://github.com/xzbnm/range/pull/1 |
| Where the pre-strategy code came from | `claude/candlestick-to-range-chart-qdqdtn` |

`main` holds only a README. Push to the work branch; it updates PR #1.

---

## 3. How the pieces fit

```
ticks ──► CRangeAggregator ──► CHookStrategy ──► CCanvas
          builds range bars    steps once per     paints bars, overlays
                               closed bar         and the dashboard
```

**`CRangeAggregator`** turns ticks into range bars. Four rules, verified against
live TradingView XAUUSD range-100 bars (see `README.md` and `verify_engine.py`):
a completed bar is exactly `R` tall, high and low float with the traversed path
rather than being anchored to the open, the bar closes on the edge that was just
touched, and the next bar opens one tick beyond that edge.

`Rebuild()` seeds from the start of the current week via `CopyTicksRange`,
falling back to M1 with a direction-guessed path. `PumpLive()` keeps it fed
between `OnCalculate` calls.

**`CHookStrategy`** is the Pine indicator. `ProcessNew()` steps every bar the
aggregator has finished since the last call, oldest first.

## 4. The rule that governs the port

**The strategy runs once per completed range bar. Never on the forming bar.**

That is the MQL equivalent of `barstate.isconfirmed`, and it is why the output
cannot repaint. Because of it, the index mapping is exact:

| Pine | here |
|---|---|
| `bar_index` | `m_bi`, the aggregator index of the bar being stepped |
| `last_bar_index` | `m_last_bi`, the newest bar of the current batch |
| `high[n]` | `H(n)`, `n` bars back from `m_bi` |
| `time` | the bar's `time_open` |

`m_last_bi` is the newest bar of the *batch*, which reproduces Pine exactly:
during the historical replay it is the final bar (so `bar_index` walks up to it
while `last_bar_index` is already known), and live it is the bar that just
closed. Anything keyed off `last_bar_index` - `input_start_main_candle`,
`input_end_main_candle` - falls out correctly without special-casing.

Every subscript in the Pine source therefore carries over unchanged. **Do not
"fix" an index while porting or editing.**

## 5. Pine quirks that are preserved on purpose

Tidying any of these changes which trades are taken. They are not bugs to fix;
they are the specification.

- **Pine's `for i = a to b` counts downwards when `b < a`.** With the default
  look-back of `0`, `f_are_prev_lows_higher` still runs for `i = 1` and `i = 0`,
  so it tests the bar before the start. The port reproduces the direction, not
  the apparent intent. `PrevLowsHigher` picks its step the same way.
- `f_are_prev_lows_higher` and `f_are_prev_highs_lower` are **not mirrors** -
  only the sell side is guarded by `len > 0`, so with the default it is a no-op
  while the buy side is not.
- `f_manage_order_buy_normal` has **no `else` on the hook-size test**, so a buy
  hook that fails only that test survives to the next bar. The sell side does
  have one.
- The second confirmation path uses `> 1` on the buy side and `> 2` on the sell
  side.
- `f_find_start_index_right_sharp_sell` checks lowest before highest, the
  reverse of the buy version.
- `f_clear_other_pending_orders` identifies hooks by `priceEnd`.
- The main sweep captures its loop bound once and guards with
  `if i > size - 1: continue`, iterating a list it mutates.
- `f_remove_hook` clears the signal, so a removal later in the same bar wipes a
  signal set earlier in it.

`CHook` is a **class, not a struct**, so that array slots hold references the
way Pine objects do - `array.get` in Pine returns a reference and mutating it
writes through. `m_own[]` owns every hook ever created; `m_list[]` is Pine's
`hooksList`. Removing a hook only detaches it from `m_list`, so a reference the
caller still holds stays valid for the rest of the bar.

## 6. Deviations the platform forces

| | |
|---|---|
| **Timezone** | Pine takes an IANA zone name. MQL has no timezone database, so the day start is an offset in minutes from broker time (`InpDayTzShiftMin`). `0` reads the start hour in broker time. |
| **Drawings** | Pine uses box/line/label objects and a table. None survive on a canvas overlay, so overlays and the dashboard are repainted from strategy state every frame. `DrawClean`/`DrawPosition` only set flags. |
| **Warm-up** | A guard skips the first `max(40, max_hook_bars + 2)` bars, standing in for the `na` history Pine propagates before enough bars exist. |
| **`min_hook_bars`** | Declared by the Pine source and never used by its logic. Kept as an input for parity, wired to nothing. |
| **Persian labels** | Off by default. `CCanvas` renders text without complex-script shaping, so Persian letters come out unjoined on most terminals. |

## 7. Render order matters

The canvas is `COLOR_FORMAT_XRGB_NOALPHA` - **no alpha channel**. A
`FillRectangle` overwrites whatever is under it; there is no blending. Real
per-pixel blending through `PixelGet`/`PixelSet` would be far too slow at
render rates.

Translucency is therefore achieved by ordering, and `Render()` depends on it:

```
1  erase
2  g_view  ← fixed here, before anything is painted
3  grid + price axis
4  HkRenderFills    risk bands, so bars paint over them
5  bars
6  forming-bar close line
7  HkRenderAll      box outline, entry / stop / target, result tags
8  g_draw.RenderAll user drawings
9  crosshair, header, time tag
10 panel chrome, toolbar, properties strip
11 DashRender       the performance panel, on top of everything
```

Steps 4 and 7 are the same overlays split in two. Moving either one breaks the
effect: the band must be under the bars so price action stays readable, the
levels must be over them so they stay legible. `g_view` is computed at step 2
rather than just before the drawings because step 4 needs it.

`RcBlend(fg, bg, t)` mixes a colour against the theme background by hand. The
band uses `t = 0.12`; lower it for a fainter tint.

## 8. Conventions

**MQL5 `const` methods.** `CHookStrategy` deliberately has **no** `const`
member functions. MQL5's const-correctness on member arrays of pointers is
stricter and less predictable than C++, and pulling a `CHook*` out of a member
array inside a `const` method is a compile risk that buys nothing here. Do not
add `const` qualifiers back.

**Code style** follows the existing files: `//+---+` banner comments,
`//---` section markers, aligned member declarations, Allman braces indented two
spaces, and comments that explain *why* rather than restating the code.

**Commits** describe the behaviour change and the reasoning, in prose, present
tense. No model identifiers in anything pushed to the repo.

## 9. Verification

```
python3 verify_engine.py      # range bar rules vs two live TradingView bars
python3 verify_strategy.py    # the hook logic + invariants
```

`verify_strategy.py` is a transliteration of `RangeStrategy.mqh` into Python.
It replays a synthetic tick path through the same bar rules, steps the hook
logic over the result, and asserts what has to hold if the control flow and the
arithmetic are right: equity equals capital plus the sum of closed P/L, the
TP/SL/RF counts match the result tags, a TP pays `risk × R:R − spread` and an SL
costs `risk + spread`, risk is the configured share of equity at entry, no trade
closes before it opens, and with concurrent trades off no two positions overlap.

**Keep the two in step.** If `RangeStrategy.mqh` changes, mirror the change in
`verify_strategy.py` - it is the only executable check on the port here.

Variants worth re-running after any change to money management (all were
consistent at the time of writing): risk-free on at 1.0R and 0.5R, SL-reduce at
40%, multi-trade on, min-minutes at 60, R:R 3 with look-back 3, and
`just_node_1` off.

## 10. Open items

- **Nothing has been compiled in MetaEditor.** No MQL toolchain exists in this
  environment. Structure was checked statically - bracket balance, all 56
  declaration/definition pairs matched, `const` qualifiers removed - and the
  logic was checked with the Python mirror, but minor compile errors are
  plausible on first build. Ask for the MetaEditor output and fix from there.
- Persian dashboard labels are untested against a real terminal.
- The dashboard hides itself when the plot is too short for all its rows rather
  than scrolling or shrinking.
