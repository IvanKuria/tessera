# Pro Charting Suite (v1) — Design

**Date:** 2026-06-17
**Goal:** Make Tessera's market chart look and feel like a serious trading app — the first of four flagship upgrades ("features Kalshi users wish Kalshi had"). Optimize for visible "wow," not power-user depth.

## Context

The detail screen currently shows a **line chart of implied probability** (single line for binary as Yes+No, multiple colored lines for multi-outcome events), built in `PriceChartView` from `DetailStore.chartSeries` (downsampled `ChartPoint{date, percent}`). The Kalshi candlestick endpoint already returns full OHLC + volume + bid/ask, but the current pipeline throws all of it away (keeps only `probability`). This design adds a **candlestick mode** without disturbing the existing line/multi-outcome behavior.

Verified data (live API): each candle has `price.{open,high,low,close,mean,previous}_dollars`, `volume_fp`, `yes_bid`/`yes_ask` OHLC, `open_interest_fp`. No-trade periods drop `price` OHLC but keep `previous_dollars` + bid/ask. Requests are capped at 5000 candles by span; intervals are only {1, 60, 1440} minutes.

## Scope

**In v1 (the visible wow):**
- **Candlesticks** — real OHLC bodies + wicks, green up / red down, for a single focused market.
- **Volume histogram** — a panel beneath the price chart, x-aligned, bars tinted up/down.
- **Hover crosshair** — a vertical line that snaps to the nearest candle and shows an **O/H/L/C + change% + volume** tooltip, shared across the price and volume panels.
- **Bid/ask spread band** — a faint shaded band behind the candles (toggle).
- **Toggles** — `Line ⇄ Candles`, `Volume on/off`, `Spread on/off`, `Log/Linear` y-axis. The existing timeframe selector (1H/1D/1W/1M/ALL) is reused.

**Deferred to v2 (out of scope):** VWAP line, open-interest subplot, drawing/measure tools, moving-average / RSI / other indicators, compare-overlays. These serve power users and add clutter; not needed to wow.

## UX

- Candlestick mode is offered only when a **single market is focused**: binary markets always (the Yes market); multi-outcome events only after the user taps an outcome. When no single market is focused (multi-outcome, nothing selected), the chart stays in line mode and the candle toggle is hidden.
- A compact control row sits with the timeframe selector: `[Line · Candles]`, and in candle mode the `Vol` / `Spread` / `Log` toggles.
- Colors come from `Theme.yes` (up) / `Theme.no` (down). Hover readout uses the existing tooltip styling.
- Mode/toggle changes animate; switching to a multi-outcome (no focus) snaps back to line mode.

## Architecture

Three layers, each independently testable:

1. **KalshiKit — candle aggregation (pure, unit-tested).**
   A pure helper that buckets `[Candlestick]` into a target count (~120–200) of OHLC candles: `open` = first in bucket, `high` = max, `low` = min, `close` = last, `volume` = sum, plus bid/ask close. No-trade gaps carry forward `previous_dollars` (flat doji, volume 0). This is the one real correctness risk (must **aggregate**, never **stride** OHLC), so it lives in the SDK with unit tests. Output is a value type the app maps to its view-model.

2. **DetailStore — focused-market candle data.**
   Add `private(set) var focusedCandles: [Candle]` (stable `Int` ids, OHLC 0–100, volume, bidClose/askClose) and a `prepareCandles(...)` that runs over the **focused** outcome's already-fetched candles (no extra network call) using the SDK aggregator. Refresh it on focus change and timeframe change. The existing `chartSeries`, `downsample`, and live-WebSocket paths are untouched.

3. **PriceChartView + DetailView — rendering & controls.**
   `PriceChartView` keeps its line `chart` exactly as-is and gains a `candleChart` (RuleMark wick + RectangleMark body on a categorical bar-index x to avoid time gaps) plus a `volumeChart` (second stacked `Chart` sharing the x-domain, y-axes width matched for alignment), a spread `AreaMark` drawn behind the candles, and the toggle row. New parameters default to line mode so existing call sites are unchanged. `DetailView` owns the chart-mode + toggle state and resets to line mode when focus clears.

Macro constraints: macOS 14 floor (for `chartXSelection` hover); pin `chartYScale` (clamp >0 for log); stable candle ids for smooth hover; ~120–200 candles after aggregation keeps it well within the performance budget and the 5000-candle API cap.

## Verification

- **SDK unit tests** for the aggregator: OHLC bucket correctness (open/high/low/close/volume), no-trade gap carry-forward, target-count behavior, edge cases (empty, single candle).
- **Manual**: open a liquid market → toggle Candles → scrub and confirm the tooltip O/H/L/C matches the candle under the cursor → volume bars align beneath candles → spread band + log + each timeframe render correctly → in a multi-outcome event, candles appear only after selecting an outcome and snap back to line on deselect.

## Risks

- **OHLC aggregation correctness** — mitigated by isolating it in a unit-tested SDK function.
- **No-trade gaps** — handled by carry-forward of `previous_dollars`; volume 0 for those buckets.
- **Panel alignment** (price vs volume leading edge) — matched y-axis widths / shared x-domain.
- **Mode/focus desync** — `chartMode` resets to line whenever a single market isn't focused.
