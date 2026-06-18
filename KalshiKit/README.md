> **Unofficial & not affiliated.** `KalshiKit` is an independent, open-source library. It is **not** affiliated with, authorized, endorsed by, or sponsored by Kalshi or KalshiEX LLC. The name "Kalshi" (including in the package name `KalshiKit`) is used **only descriptively** to indicate compatibility — not as a claim of affiliation. See the [Disclaimer](#disclaimer).

# KalshiKit

A typed Swift SDK for the [Kalshi](https://kalshi.com) trade API (v2) — market data, websocket, and trading. Built for **Swift 6** strict concurrency; the client is an `actor`.

> **Status: v1.0.0.** First public release, shipped alongside the Tessera app.

## Requirements

- macOS 14+
- Swift 6 / Xcode 16+
- No third-party runtime dependencies

## Install

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/IvanKuria/KalshiKit.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "KalshiKit", package: "KalshiKit")]
    )
]
```

Or in Xcode: **File ▸ Add Package Dependencies…** and paste
`https://github.com/IvanKuria/KalshiKit.git`.

> **Where the code lives.** KalshiKit is developed in the
> [`tessera`](https://github.com/IvanKuria/tessera) monorepo (under `KalshiKit/`)
> alongside the Tessera app, and published to the standalone
> [`KalshiKit`](https://github.com/IvanKuria/KalshiKit) repo for distribution. The
> monorepo is canonical; please file issues and PRs there.

## Quick start (keyless — market data)

Market-data endpoints require **no credentials**:

```swift
import KalshiKit

let client = KalshiClient(environment: .demo)

let markets = try await client.markets(status: "open")

for market in markets.prefix(10) {
    // `yesBid` is in cents (1–99); divide by 100 for an implied probability.
    let impliedPct = Double(market.yesBid) / 100.0 * 100.0
    print("\(market.ticker): \(market.title) — ~\(Int(impliedPct))%")
}
```

> Use `.demo` while developing; switch to `.production` for live data.

## Authenticated usage (trading) — sketch

Authenticated endpoints (balance, positions, orders, trading) require **your own**
Kalshi API key: a **key id** plus an **RSA private key**. Build a `KalshiSigner`
from `KalshiCredentials` and hand it to the client. Keys should be loaded from a
secure store (e.g. the macOS Keychain) — never hard-code them.

```swift
import KalshiKit

let credentials = KalshiCredentials(
    keyId: "<your-key-id>",
    privateKeyPEM: "<your-RSA-private-key-PEM>"   // load from Keychain
)

let signer = try KalshiSigner(credentials: credentials)

let client = KalshiClient(environment: .production, signer: signer)
// or, at runtime: await client.setSigner(signer)

let balance = try await client.balance()
print("Balance: \(balance)")
```

`KalshiSigner` conforms to the `RequestSigning` protocol, so you can supply your
own signing implementation if you need to (e.g. backing the private key with the
Secure Enclave or a custom Keychain access policy).

## Capabilities

| Area | Status | Selected methods |
| --- | --- | --- |
| **Market data** | ✅ keyless | `series`, `events`, `markets`, `market(_:)`, `trades`, `candlesticks`, `exchangeStatus`, `orderbook` |
| **WebSocket** | ✅ keyless / keyed | live ticker & orderbook streaming |
| **Trading** | 🔑 requires your key | `balance`, `positions`, `orders`, `createOrder`, `cancelOrder` |
| **Scanner engine** | ✅ pure | `DetectionEngine`, detectors, `Opportunity` model, fee + VWAP/depth math |

### Scanner detection engine

`Sources/KalshiKit/Scanner/` is a **pure, reusable mispricing-detection engine** —
no I/O, all money in `Decimal`, fully unit-tested. Given a value-type market/orderbook
snapshot it returns ranked `Opportunity` values across two lanes — **Locks** (provable
multi-outcome arbitrage) and **Edges** (scored ladder-monotonicity / spread / stale
signals) — with **net-of-fee, depth-aware (Level-2 VWAP walk), annualized** economics.

```swift
let opportunities = DetectionEngine.scan(snapshot)   // [Opportunity], ranked
```

It is the same engine that powers Tessera's Scanner. It computes economics only; it
does **not** place orders, give advice, or guarantee profit (execution is non-atomic).

### Public surface

- `KalshiClient` — the API entry point (an `actor`)
- `KalshiEnvironment` — `.production`, `.demo`, or `.custom(rest:webSocket:)`
- `KalshiCredentials` — your key id + RSA private key
- `KalshiSigner` — request signer built from credentials
- `RequestSigning` — protocol for custom signers
- Model types — `Series`, `Event`, `Market`, `Trade`, `Candlestick`, `Orderbook`, and portfolio types
- `DetectionEngine` + `Opportunity` — the pure Scanner mispricing-detection engine (see above)

## License

[MIT](LICENSE). KalshiKit ships standalone under the same terms as the parent project.

---

## Disclaimer

- **Not affiliated.** Not affiliated with, authorized, endorsed by, or sponsored by Kalshi or KalshiEX LLC. No Kalshi logo, wordmark, brand colors, or trademarks are bundled. "Kalshi" is used only to describe API compatibility.
- **Informational only — not financial advice.** Data returned may be delayed, incomplete, or wrong. Nothing here is financial, investment, legal, or tax advice.
- **AS IS, no warranty.** Provided "AS IS" without warranty of any kind; use at your own risk (see [LICENSE](LICENSE)).
- **You supply your own key.** Trading requires your own Kalshi API key. You are solely responsible for keeping it secure and for any orders placed.
- **Always verify on Kalshi.** Confirm anything important directly on [kalshi.com](https://kalshi.com) or via the official API before acting on it.

> Before any public release, the maintainer must read Kalshi's **API Developer Agreement** in a browser and confirm its terms (commercial use, data redistribution, required disclaimers, trademark use). See the parent project's [`DISCLAIMER.md`](../DISCLAIMER.md).
