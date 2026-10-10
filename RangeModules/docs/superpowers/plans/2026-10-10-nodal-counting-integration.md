# Nodal Counting indicator integration plan

## Goal
Port the provided Pine v6 Nodal Counting (NDS) algorithm as one optional chart indicator inside `RangeModules/Indicators/NodalCounting/`, rendered on the existing RangeChartCanvas. The chart remains the only compiled entry point. Build its toggle, settings panel, and label drawing with the existing CCanvas.

## Architecture
- Model: portable NDS settings, nodes, and colors.
- Engine: up/down pivot detection, correction tracking, symmetry handling, and node sorting; no canvas or chart UI dependencies.
- Canvas adapter/panel: label projection and interactive controls, using the parent chart's canvas and bar view.
- Root indicator: owns module instance and dispatches range bars and pointer events.

## Compatibility decisions
- Treat the range bars produced by the current chart as the NDS source bars.
- Match Pine's sample input defaults: startPoint=2200, endPoint=0, symmetry=true, label size Normal, 8 sample colors, drawing enabled.
- Pine's endPoint/startPoint bound the processed bar window; they are not pivot lookback lengths.
- Keep the indicator enabled by default and expose a CCanvas toggle like TradingView's visibility control.
- Settings UI uses CCanvas controls for start/end window, symmetry, label size, eight colors, visibility, and close/open state.
- Preserve the source's number labels; connecting lines remain disabled as in the supplied code.

## Validation constraints
- Do not add or run automated tests under the active higher-priority instruction. Attempt MetaEditor compilation only if available; otherwise use static inspection and report limitation.
- Keep all implementation files under `RangeModules/Indicators/NodalCounting/`.
