# Modular Range Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Hook Sharp trading behavior, keep the range chart intact, and organize its support code and future strategy storage into independent modules under `RangeModules/`.

**Architecture:** Keep `RangeChartCanvas.mq5` at the repository root as the MQL indicator entry point. Move support files to `RangeModules/`; split drawing data and CSV persistence, isolate chart painting helpers, and add strategy-neutral trade records with a file-backed store that has no active caller.

**Tech Stack:** MQL5, MetaTrader 5 `CCanvas`, MQL5 CSV file APIs, Python documentation/verification scripts.

**Spec:** `RangeModules/docs/superpowers/specs/2026-10-10-modular-range-chart-design.md`

## Global Constraints

- Only `RangeChartCanvas.mq5` is compiled.
- Do not change range-bar tick and M1 fallback behavior.
- Drawing anchors remain `(bar index, price)` and drawing files remain per symbol and range.
- Keep existing drawing CSV names and field order compatible.
- Strategy-neutral storage uses MQL5 file storage and versioned CSV; it is not called by the chart.
- Do not add or run tests unless requested.

## Review Focus

- Relative include paths must resolve from the root `.mq5` after support files move; update each include and install path.
- Removing strategy code must also remove dashboard paint ordering and the `D` dashboard toggle without changing other keyboard behavior.
- Drawing CSV read/write must preserve existing filenames, values, and text content after extraction.
- The strategy record CSV schema must be versioned and handle an empty or missing file without affecting chart startup.
- Rendering changes must preserve the mapping and bar draw order that keeps range bars aligned to drawings.

---

### Task 1: Move support files into `RangeModules/`

**Files:**
- Move: `RangeAggregator.mqh`, `RangeDrawings.mqh`, `README.md`, `CLAUDE.md`, `verify_engine.py` into `RangeModules/`
- Keep: root `.gitignore` as repository metadata for generated files
- Delete: stale `RangeChartCanvas.ex5` build, which still contains the removed strategy
- Modify: `RangeChartCanvas.mq5` include paths
- Delete: `RangeStrategy.mqh`, `RangeDashboard.mqh`, `verify_strategy.py`, `reference/hook_sharp_v7.1.pine`
- Delete: now-empty `reference/` directory

**Interfaces:**
- Root source includes support modules from `RangeModules/`.
- `RangeModules/README.md` documents root source compilation and support folder contents.

- [x] Move the listed support files and remove the stale generated artifact, keeping `RangeChartCanvas.mq5` at root and `.gitignore` at root as repository metadata.
- [x] Update `.mqh` include paths and all documented file/install paths to `RangeModules/`.
- [x] Remove the strategy-only source, Pine reference, and Python mirror.
- [x] Read the resulting file list and confirm the only root application source file is `RangeChartCanvas.mq5`.

### Task 2: Remove Hook Sharp and paper-trading behavior

**Files:**
- Modify: `RangeChartCanvas.mq5`
- Modify: `RangeModules/README.md`
- Modify: `RangeModules/CLAUDE.md`
- Delete: `RangeModules/RangeStrategy.mqh`
- Delete: `RangeModules/RangeDashboard.mqh`

**Interfaces:**
- The indicator continues to initialize `CRangeAggregator` and `CDrawings` and renders the range chart without a strategy object.
- No replacement strategy interface is instantiated by the indicator.

- [x] Remove Hook inputs, settings conversion, strategy state, rebuild replay, per-bar processing, trade overlay calls, dashboard calls, and dashboard key handling.
- [x] Remove obsolete `RangeStrategy.mqh` and `RangeDashboard.mqh` includes and all remaining Hook-specific status strings.
- [x] Update README and working brief to describe a strategy-free range chart and the new module map.
- [x] Review the active indicator for remaining Hook or paper-trading references; documentation mentions the removed feature only to describe its absence.

### Task 3: Separate drawing model and persistence

**Files:**
- Create: `RangeModules/RangeDrawingModel.mqh`
- Create: `RangeModules/RangeDrawingStore.mqh`
- Modify: `RangeModules/RangeDrawings.mqh`
- Modify: `RangeChartCanvas.mq5`

**Interfaces:**
- `RangeDrawingModel.mqh` owns `ENUM_RC_TOOL`, `SDrawing`, `SView`, palette constants, and pixel/data projection helpers.
- `RangeDrawingStore.mqh` exposes CSV load/save functions over `SDrawing` arrays and an explicit file path.
- `CDrawings` owns editing, hit-testing, rendering, and in-memory items; its `Save`/`Load` calls delegate serialization to the drawing store.

- [x] Move the drawing data types and projection helpers out of `RangeDrawings.mqh` without changing names or field order.
- [x] Move CSV serialization into `RangeDrawingStore.mqh`, preserving file naming and field order.
- [x] Update `CDrawings` to call the store while preserving add/remove semantics and current per-symbol/per-range behavior.
- [x] Update module includes and README module descriptions.

### Task 4: Add strategy-neutral records and CSV store

**Files:**
- Create: `RangeModules/RangeStrategyData.mqh`
- Create: `RangeModules/RangeStrategyStore.mqh`
- Modify: `RangeModules/README.md`
- Modify: `RangeModules/CLAUDE.md`

**Interfaces:**
- `STradeRecord` has `schema_version`, `trade_id`, `strategy_id`, `symbol`, `range_ticks`, `direction`, `entry_time`, `entry_price`, `stop_price`, `target_price`, `exit_time`, `exit_price`, `outcome`, and `pnl` fields.
- `CStrategyStore::Append(const STradeRecord &record)` appends one row to `RC_trades.csv` in MQL5 Files.
- `CStrategyStore::Load(STradeRecord &records[])` loads schema version 1 and returns false for missing, unreadable, or unsupported-version storage.
- The store is not instantiated or called by the chart.

- [x] Define the strategy-independent record and direction/outcome enums with no Hook-specific members.
- [x] Implement versioned CSV append/load with explicit open/close handling and empty-file behavior.
- [x] Document the CSV schema, location, and rule that future strategies call the store rather than writing files directly.

### Task 5: Isolate range-chart painting helpers

**Files:**
- Create: `RangeModules/RangeChartRenderer.mqh`
- Modify: `RangeChartCanvas.mq5`
- Modify: `RangeModules/README.md`

**Interfaces:**
- `CRangeChartRenderer` paints the range grid/price axis and completed/forming OHLC bars from an explicit canvas pointer, aggregator pointer, view geometry, range style, and chart colors.
- `RangeChartCanvas.mq5::Render()` remains responsible for full-frame order and user-interface composition, invoking renderer methods at the existing grid/bar stages.

- [x] Move the grid/axis and OHLC bar painting helpers into `CRangeChartRenderer` with explicit inputs and no access to strategy state.
- [x] Keep full-frame render order in `Render()` and preserve drawing overlays above bars and crosshair/UI above drawings.
- [x] Update includes and document module responsibilities.

### Task 6: Update project instructions and final layout

**Files:**
- Modify: `RangeModules/README.md`
- Modify: `RangeModules/CLAUDE.md`
- Modify: `RangeModules/.gitignore` if needed

**Interfaces:**
- Installation instructions copy root `RangeChartCanvas.mq5` and the `RangeModules/` folder into the same MQL5 source directory.
- Documentation identifies the range engine, chart renderer, drawing model/store, and future strategy data/store modules.

- [x] Align all diagrams and file listings with the final structure.
- [x] Remove references to deleted Hook settings, dashboards, verification mirror, and Pine source from user-facing and working documentation.
- [x] Confirm by inspection that support files are under `RangeModules/` and the only application source at root is `RangeChartCanvas.mq5`.

### Task 7: Finish on `main` and remove other branches

**Files:**
- Git branch state only

**Interfaces:**
- `main` contains the completed implementation and all retained commits before any other local or remote branch is removed.
- `origin/main` is updated before deleting remote branches so the requested work remains available remotely.

- [ ] Commit the completed refactor on local `main`.
- [ ] Update `origin/main` with the completed commit.
- [ ] Remove every other local and remote branch, retaining `main` and `origin/main` only.
