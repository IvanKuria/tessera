# Tessera

A native macOS app for live **Kalshi** prediction-market data, built on
[KalshiKit](../KalshiKit). Read-only market data needs no credentials; portfolio
and trade execution are opt-in with **your own** API key.

> **Unofficial.** Not affiliated with, endorsed by, or connected to Kalshi /
> KalshiEX LLC. For informational purposes only — not financial advice.

![Markets dashboard](../docs/screenshots/dashboard.png)

## What's in it

A standard windowed Dock app with a Mac-native sidebar:

- **Markets** — a dashboard of the most active open markets by category, with
  live implied probabilities, refreshed live and cached to disk for instant
  cold-launch render.
- **Market detail** — multi-outcome price history (1H / 1D / 1W / 1M / All), 24h
  volume, open interest, order book, recent trades, and per-outcome Yes/No
  pricing; with a trade ticket when a key is connected.
- **Portfolio** — balance, open positions, resting orders, recent fills, and
  settled markets (requires a connected key).
- **Alerts & Triggers** — price/probability alerts with native notifications, and
  automated triggers that can place orders when conditions are met.

## Build & run

Requires macOS 14+, Xcode 16+ (Swift 6), and [xcodegen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
cd Tessera
xcodegen generate                 # writes Tessera.xcodeproj from project.yml
open Tessera.xcodeproj             # then Run (⌘R), or:
xcodebuild -scheme Tessera -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The app runs as a single-window Dock app (it quits when you close the window).
Market data is read-only and keyless; connect a Kalshi key from the sidebar only
for portfolio and trading.

## Architecture

The app is a single `Window` scene wrapping a `NavigationSplitView`
(`RootView`). State lives in a set of `@MainActor @Observable` stores and engines
that all sit on top of the `KalshiClient` actor from KalshiKit:

| Type | Role |
| --- | --- |
| `WatchlistStore` | Drives the Markets dashboard (active markets, categories, live refresh + disk cache). |
| `DetailStore` | Loads price history, order book, and recent trades for the selected market. |
| `AccountStore` | Holds the connected credentials and authenticated client; gates portfolio + trading. |
| `PortfolioStore` | Balance, positions, orders, fills, settlements (built from `AccountStore`). |
| `AlertEngine` | Watches prices and fires native notifications on threshold crossings. |
| `TriggerEngine` | Evaluates automation rules and can place orders via `AccountStore`. |

All networking runs off the main thread inside the `KalshiClient` actor; the
stores only touch UI state. Credentials are stored exclusively in the macOS
Keychain and are sent nowhere except directly to Kalshi.

## License

MIT. See [LICENSE](../LICENSE).
