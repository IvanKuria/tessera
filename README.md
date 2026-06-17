> **Unofficial & not affiliated.** This is an independent, open-source project. It is **not** affiliated with, authorized, endorsed by, or sponsored by Kalshi or KalshiEX LLC. "Kalshi" is used only descriptively to indicate compatibility. See the [Disclaimer](#disclaimer) below and [`DISCLAIMER.md`](DISCLAIMER.md).

# Tessera (working name) + KalshiKit

A native macOS app and a reusable Swift SDK for [Kalshi](https://kalshi.com), the CFTC-regulated prediction market. The app shows live odds (read-only) first, and can later place trades using **your own** API key. The SDK (`KalshiKit`) is a standalone library anyone can use to build Kalshi-compatible tools in Swift.

> **Status: early work in progress.** APIs, names, and features are unstable and may change. The app name "Tessera" is a working title and is **not final**.

---

## What this is

This repository ships **two deliverables**:

| Deliverable | What it is |
| --- | --- |
| **`KalshiKit`** | An open-source Swift SDK (SwiftPM library) for the Kalshi trade API — market data, websocket, and trading. Reusable on its own. |
| **macOS app** (working name *Tessera*, final name TBD) | A native menu-bar / desktop client for live odds (read-only), and later opt-in trade execution with your own API key. |

Both are **free, non-commercial, portfolio projects** released under the **MIT License**.

## Why

- There is **no official native Mac app** for Kalshi; the desktop experience is the website.
- There is a **gap for a reusable Swift SDK** — a clean, typed library other developers can drop into their own macOS/iOS tools.
- A read-only menu-bar app already exists in the wild ([PredictBar](https://github.com/) is one example), so this project's focus is the **reusable SDK** plus **actual trade execution**, not just glanceable odds.

This is a learning / portfolio project, built in the open.

## Planned features (by milestone)

1. **Read-only dashboard** — browse series, events, and markets; live implied probabilities and prices.
2. **Alerts** — price/probability thresholds and movement notifications.
3. **Trade execution** — opt-in, with **your own** Kalshi API key (key id + RSA private key). Keys live only in the macOS Keychain.
4. **Widgets** — at-a-glance odds in Notification Center / on the desktop.

Milestones are aspirational and subject to change.

## Build requirements

- **macOS 14+** (Sonoma or later)
- **Xcode 16+** with **Swift 6** (strict concurrency)
- Swift Package Manager (no third-party runtime dependencies)

## Repository layout

```
mac-app/
├── KalshiKit/        # the open-source Swift SDK (SwiftPM package)
│   └── README.md     # SDK usage and API surface
├── DISCLAIMER.md     # full disclaimer + pre-release legal checklist
├── NAMING.md         # branding / nominative-fair-use notes
├── LICENSE           # MIT
└── README.md         # you are here
```

## License

[MIT](LICENSE). See [`KalshiKit/LICENSE`](KalshiKit/LICENSE) for the SDK (it ships standalone under the same terms).

---

## Disclaimer

- **Not affiliated.** This project is **not** affiliated with, authorized, endorsed by, or sponsored by Kalshi or KalshiEX LLC. No Kalshi logo, wordmark, brand colors, or other trademarks/artwork are used. The name "Kalshi" appears only to describe compatibility (nominative fair use).
- **Informational only — not financial advice.** Any odds, prices, or data shown are for informational purposes only and may be delayed, incomplete, or wrong. Nothing here is financial, investment, legal, or tax advice.
- **AS IS, no warranty.** The software is provided "AS IS", without warranty of any kind. You use it at your own risk. See the [LICENSE](LICENSE).
- **Trading is opt-in and uses your own key.** Read-only features need no credentials. Trade execution is strictly opt-in and requires **your own** Kalshi API key (key id + RSA private key), which is stored **only in the macOS Keychain** and is **never transmitted anywhere except directly to Kalshi**. You are solely responsible for any trades placed.
- **Always verify on Kalshi.** Before acting on anything shown here, confirm it directly on [kalshi.com](https://kalshi.com) or via the official Kalshi API.

The full disclaimer and the pre-release legal checklist live in [`DISCLAIMER.md`](DISCLAIMER.md).
