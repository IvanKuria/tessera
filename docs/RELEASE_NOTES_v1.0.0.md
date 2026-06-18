# Tessera + KalshiKit v1.0.0

A native macOS app for [Kalshi](https://kalshi.com), the CFTC-regulated prediction
market — and the reusable Swift SDK underneath it. Free, open-source, MIT.

> **Unofficial & not affiliated.** This is an independent, open-source portfolio
> project. It is **not** affiliated with, authorized, endorsed by, or sponsored by
> Kalshi or KalshiEX LLC. "Kalshi" is used only descriptively to indicate
> compatibility. Informational only — **not financial advice**, and **not a guarantee
> of profit**. Trading is opt-in and uses **your own** API key. See
> [`DISCLAIMER.md`](../DISCLAIMER.md).

## What it is

**Tessera** is a real native Mac desktop client for Kalshi — not a wrapped website and
not a glanceable menu-bar widget. Browse live markets and implied odds, drill into
price history, candlestick charts, and order books, watch a within-Kalshi mispricing
**Scanner**, track your portfolio, set alerts, and — opt-in, with your own key — place
trades.

**KalshiKit** is the standalone, typed Swift 6 SDK powering it, usable on its own in
your own macOS/iOS tools.

Both are **free, non-commercial, MIT-licensed** portfolio projects.

## Headline features

- **Scanner — honest, within-Kalshi mispricing detection.** The flagship. It hunts the
  exchange for arbitrage and mispricing and shows only the **net-of-fee, depth-aware,
  annualized** truth — never a gross price gap that lies. Two honestly-labeled lanes:
  - **Locks** — *provable* multi-outcome arbitrage that survives fees and a real
    Level-2 orderbook depth walk.
  - **Edges** — *scored, not guaranteed* signals (ladder monotonicity, wide spreads,
    stale quotes), clearly labeled as estimates.

  It surfaces non-atomic legging risk and worst-case loss on every multi-leg row,
  offers a dutching calculator clamped to fillable depth, forward-only paper trading
  (no backtested "you would've made $X"), and opt-in alerts. Real arbitrage is rare, so
  **an empty Scanner is the normal, honest state** — not a bug.
- **Candlestick charting suite** on market detail — candles + volume, a moving average,
  a bid/ask spread band, log scale, pinch-to-zoom-at-cursor, a hover OHLC crosshair, a
  live last-price tick, set-an-alert-from-the-chart, and a Line vs Candles toggle.
- **Markets dashboard & detail** — live implied probabilities across categories,
  multi-outcome price history, volume, open interest, order books, and recent trades.
- **Portfolio, Alerts & Triggers** — balances, positions, resting orders and fills;
  native price/probability alerts; and opt-in automated rules.
- **Bring-your-own-key trading** — keys live only in the macOS Keychain and go nowhere
  except directly to Kalshi.
- **Dark mode** — app-wide, following the system appearance.

## A note on honesty

This project leans into honesty as the brand. The Scanner never says "guaranteed"
about execution, never shows hypothetical past performance, and never gamifies trade
frequency. Signals are informational only — not advice, not certainties. Fees,
slippage, legging risk, capital lock-up, and settlement outcomes are your own, and you
should verify everything directly on Kalshi before acting. See
[`DISCLAIMER.md`](../DISCLAIMER.md).

## Install

> Install instructions are finalized at release. Planned distribution:

- **Signed `.dmg`** — download from the [v1.0.0 release](https://github.com/IvanKuria/tessera/releases/tag/v1.0.0),
  open it, and drag Tessera to Applications. *(Download link added on the release.)*
- **Homebrew cask** — `brew install --cask tessera`. *(Cask name/tap added on the release.)*

Requirements: **macOS 14+** (Sonoma or later). Market data is read-only and needs **no
credentials**; connect your own Kalshi API key only for portfolio and trading.

Prefer to build from source? See the [README](../README.md) Quick start.

## KalshiKit (the SDK)

`KalshiKit` ships standalone for your own projects: market data, websocket streaming,
RSA request signing, fee math, candle aggregation, and a pure, reusable **Scanner
detection engine** (Opportunity model, detectors, fee + VWAP/depth math). See
[`KalshiKit/README.md`](../KalshiKit/README.md) and the standalone
[KalshiKit repo](https://github.com/IvanKuria/KalshiKit).

## Feedback

Issues and pull requests are welcome on the
[tessera repo](https://github.com/IvanKuria/tessera). If something looks wrong, tell me
— and always confirm it on Kalshi first.
