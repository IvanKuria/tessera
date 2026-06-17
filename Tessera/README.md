# Tessera

A native macOS menu-bar app for live **Kalshi** prediction-market odds, built on
[KalshiKit](../KalshiKit). Read-only today; trade execution is planned.

> **Unofficial.** Not affiliated with, endorsed by, or connected to Kalshi /
> KalshiEX LLC. For informational purposes only — not financial advice.

## Status

Early WIP. Current milestone (M3): a menu-bar glance + window showing the most
active open markets with their implied probabilities, refreshed live and cached
to disk for instant cold-launch render.

## Build & run

Requires macOS 14+, Xcode 16+ (Swift 6), and [xcodegen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
cd Tessera
xcodegen generate                 # writes Tessera.xcodeproj from project.yml
open Tessera.xcodeproj             # then Run, or:
xcodebuild -scheme Tessera -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The app runs as a menu-bar item (no Dock icon). Click it for the market list, or
**Open Window** for the full table.

## Architecture

`WatchlistStore` (`@MainActor @Observable`) consumes the `KalshiClient` actor from
KalshiKit and drives both the `MenuBarExtra` glance and the main `Window`. All
networking is off the main thread in the actor; the store only touches UI state.

## License

MIT. See [LICENSE](../LICENSE).
