# Modular Range Chart Design

## Intent

Remove the current Hook Sharp signal and paper-trading behavior while keeping the MetaTrader 5 range chart usable. Organize support code under `RangeModules/`, leaving `RangeChartCanvas.mq5` as the only project source file at the repository root. Keep future strategy data and persistence independent from the chart and from any specific strategy.

## Goals

- Preserve range-bar construction, chart rendering, navigation, drawing tools, and drawing persistence.
- Remove Hook Sharp detection, signal generation, pending orders, paper positions, trade management, strategy inputs, overlays, and performance dashboard from the active indicator.
- Split chart support code into focused modules with clear dependencies and readable interfaces.
- Provide strategy-neutral records and a persistence module that a later strategy can use without changing the range engine or drawing tools.
- Move support source, docs, verification scripts, reference material, and generated support artifacts into `RangeModules/`; keep `RangeChartCanvas.mq5` at the root.
- Keep the project buildable by compiling only `RangeChartCanvas.mq5` in MetaEditor.

## Non-goals

- Do not implement a replacement trading strategy.
- Do not connect to a broker, place live orders, or create a live-trading Expert Advisor.
- Do not retain or recreate the Hook Sharp dashboard; no strategy is active to populate it.
- Remove the Hook Sharp Pine reference and its Python strategy mirror because they belong only to the deleted strategy.
- Do not migrate or delete saved user drawings.
- Do not add a third-party database dependency. Use MQL5 file storage and stable, versioned CSV records as the initial persistence backend.

## Architecture

`RangeChartCanvas.mq5` remains the composition root: it owns indicator inputs, MQL event callbacks, and connects modules. `RangeModules/RangeAggregator.mqh` remains responsible only for building range bars. Drawing types and coordinate projection move to a small model/header module; drawing interaction/rendering stays in its own module; CSV drawing serialization is extracted behind a drawing-store module. Chart rendering helpers are separated from event/input coordination where doing so preserves the existing render order and behavior.

Strategy-independent future data lives in a separate model/store pair. The model defines versioned trade records without Hook-specific fields. A record stores a caller-provided trade ID, strategy ID, symbol, range size, direction, entry/exit times and prices, stop/target, outcome, and P/L. The store exposes explicit load/append operations and uses CSV under the terminal's MQL5 Files area. It is not called by the chart until a future strategy is added. Unsupported schema versions and rows without the trailing completion marker fail explicitly; empty files load successfully. Text fields reject CSV delimiters and line breaks. Existing drawing CSV names and field order remain compatible.

All project support files, including `.mqh` modules, README/working brief, range-engine verification script, and generated `.ex5` artifact if retained, live under `RangeModules/`. The Hook Sharp Pine reference and strategy verification script are removed. The repository `.git` metadata remains untouched. Include paths from the root source are updated to `RangeModules/...`.

## Constraints

- Only `RangeChartCanvas.mq5` is compiled.
- The range engine's tick and M1 fallback behavior must remain unchanged.
- Drawing anchors remain `(bar index, price)` and drawing files remain per symbol and range.
- Keep the XRGB canvas render order that places bars over fills and overlays above bars wherever those layers remain applicable.
- Do not add or run tests unless requested. Existing verification scripts may be updated to remove obsolete strategy checks and retained for the range engine.

## Acceptance criteria

- Root contains the main `.mq5` source as its only project file; support files are under `RangeModules/`.
- The main source no longer includes or references Hook strategy inputs, state, processing, overlays, or dashboard.
- The indicator still builds its range chart and preserves drawing interactions and existing drawing persistence format.
- Strategy-neutral data records and storage are isolated in their own modules, are not coupled to `CRangeAggregator` or `CDrawings`, and are not invoked until a future strategy uses them.
- README and working brief describe the strategy-free chart, module layout, storage boundaries, and correct install/compile paths.
- The finished implementation is committed to `main`; after `main` is updated, all other local and remote branches are removed.
