> **Unofficial & not affiliated.** `KalshiKit` is an independent, open-source library. It is **not** affiliated with, authorized, endorsed by, or sponsored by Kalshi or KalshiEX LLC. The name "Kalshi" (including in the package name `KalshiKit`) is used **only descriptively** to indicate compatibility — not as a claim of affiliation. See the [Disclaimer](#disclaimer).

# KalshiKit

A typed Swift SDK for the [Kalshi](https://kalshi.com) trade API (v2) — market data, websocket, and trading. Built for **Swift 6** strict concurrency; the client is an `actor`.

> **Status: early work in progress.** Public API may change before `1.0`.

## Requirements

- macOS 14+
- Swift 6 / Xcode 16+
- No third-party runtime dependencies

## Install

KalshiKit currently lives inside the [`tessera`](https://github.com/ivankuria/tessera)
monorepo (under `KalshiKit/`), so it isn't yet consumable via a remote
`.package(url:)` — Swift Package Manager expects a package's `Package.swift` at the
repository root. Until it's split into its own repo, use a **local checkout**:

```sh
git clone https://github.com/ivankuria/tessera.git
```

Then reference the package by path from your own `Package.swift`:

```swift
dependencies: [
    .package(path: "../tessera/KalshiKit")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "KalshiKit", package: "KalshiKit")]
    )
]
```

Or in Xcode: **File ▸ Add Package Dependencies… ▸ Add Local…** and select the
`tessera/KalshiKit` folder.

> **Want it as a standalone package?** Open an issue on the
> [tessera repo](https://github.com/ivankuria/tessera/issues). Splitting KalshiKit
> into its own repository (so `.package(url:)` works) is planned — it's already
> dependency-free and self-contained.

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
| **WebSocket** | 🚧 planned / in progress | live tickers & orderbook streaming |
| **Trading** | 🔑 requires your key | `balance`, `positions`, `orders`, `createOrder`, `cancelOrder` |

### Public surface

- `KalshiClient` — the API entry point (an `actor`)
- `KalshiEnvironment` — `.production`, `.demo`, or `.custom(rest:webSocket:)`
- `KalshiCredentials` — your key id + RSA private key
- `KalshiSigner` — request signer built from credentials
- `RequestSigning` — protocol for custom signers
- Model types — `Series`, `Event`, `Market`, `Trade`, `Candlestick`, `Orderbook`, and portfolio types

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
