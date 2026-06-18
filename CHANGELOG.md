# Changelog

All notable changes to this project are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Unofficial & not affiliated.** Not affiliated with, authorized, endorsed by, or
> sponsored by Kalshi or KalshiEX LLC. Informational only — not financial advice.
> See [`DISCLAIMER.md`](DISCLAIMER.md).

## [v1.0.0] — 2026-06-17

First public release of **Tessera** (native macOS app) and **KalshiKit** (Swift SDK).

### Added

- **Markets dashboard** — browse series, events, and markets by category with live
  implied probabilities and prices, cached to disk for instant cold-launch render.
- **Market detail** — multi-outcome price history (1H / 1D / 1W / 1M / All), 24h
  volume, open interest, order book, recent trades, and per-outcome Yes/No pricing.
- **Candlestick charting suite** — candles plus a volume panel, a moving average, a
  bid/ask spread band, log scale, pinch-to-zoom-at-cursor, a hover crosshair with an
  OHLC tooltip, a live last-price tick, set-an-alert-from-the-chart, and a Line vs
  Candles toggle.
- **Scanner** — a within-Kalshi arbitrage and mispricing scanner with two
  honestly-labeled lanes: **Locks** (provable multi-outcome arbitrage that survives
  fees and orderbook depth) and **Edges** (scored ladder-monotonicity, spread, and
  stale-quote signals). All math is net-of-fee, depth-aware (Level-2 VWAP walk), and
  annualized against a real hurdle. Includes a Simple/Pro mode, a dutching calculator
  clamped to fillable depth, a bound-legs execution panel gated behind a mandatory
  non-atomic legging-risk warning, forward-only paper trading, Watching / Paper P&L /
  Digest tabs, and opt-in native alerts.
- **Portfolio** — balance, open positions, resting orders, recent fills, and settled
  markets (requires your own API key).
- **Alerts** — price/probability thresholds with native notifications.
- **Triggers** — automated rules that can place orders when conditions are met
  (opt-in, your key).
- **Bring-your-own-key trading** — keys live only in the macOS Keychain and are sent
  nowhere except directly to Kalshi.
- **Dark mode** — app-wide, following the system appearance.
- **KalshiKit SDK** — a typed Swift 6 SDK for the Kalshi trade API (v2): market data,
  websocket streaming, RSA request signing, fee math, and candle aggregation. Includes
  a pure, reusable **Scanner detection engine** (`Sources/KalshiKit/Scanner/` —
  Opportunity model, detectors, and fee + VWAP/depth math) covered by unit tests.

[v1.0.0]: https://github.com/IvanKuria/tessera/releases/tag/v1.0.0
