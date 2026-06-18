> **Unofficial & not affiliated.** `PolymarketKit` is an independent, open-source library. It is **not** affiliated with, authorized, endorsed by, or sponsored by Polymarket. The name "Polymarket" (including in the package name `PolymarketKit`) is used **only descriptively** to indicate compatibility — not as a claim of affiliation. See the [Disclaimer](#disclaimer).

# PolymarketKit

A typed Swift SDK for Polymarket's public market-data APIs — the **Gamma** metadata API (markets & events) and the **CLOB** order-book API (books, prices, midpoints). Built for **Swift 6** strict concurrency; the shared client is an `actor`. No API key required.

> **Status: v1.0.0.** First public release.

## Requirements

- macOS 14+
- Swift 6 / Xcode 16+
- No third-party runtime dependencies

## Install

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/IvanKuria/PolymarketKit.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "PolymarketKit", package: "PolymarketKit")]
    )
]
```

Or in Xcode: **File ▸ Add Package Dependencies…** and paste
`https://github.com/IvanKuria/PolymarketKit.git`.

## Quick start

```swift
import PolymarketKit

let client = PMClient()                 // keyless; always sends a User-Agent
let gamma  = GammaService(client: client)
let clob   = ClobService(client: client)

// Open markets (Gamma returns a bare JSON array; PolymarketKit unwraps the
// JSON-string-encoded `outcomes` / `outcomePrices` / `clobTokenIds` for you).
let markets = try await gamma.markets(closed: false, limit: 20)
for m in markets {
    print(m.question, m.outcomes, m.outcomePrices.map(\.value))
}

// Live order book for an outcome token.
if let token = markets.first?.clobTokenIds.first {
    let book = try await clob.book(tokenID: token)
    print("best bid \(book.bestBid ?? 0) / best ask \(book.bestAsk ?? 0)")

    let mid = try await clob.midpoint(tokenID: token)
    print("midpoint \(mid)")
}
```

## Design notes

- **Money is `Decimal`.** Prices, volumes and sizes decode through `PMDecimal`
  (string-or-number → `Decimal`, POSIX locale), never `Double`. Polymarket
  prices live in `0...1`; `PMDecimal.centsRounded` projects to integer cents.
- **JSON-string arrays.** Gamma encodes `outcomes`, `outcomePrices` and
  `clobTokenIds` as JSON *strings* containing arrays. `PMMarket` unwraps them
  into real Swift arrays during decoding.
- **No top-level category.** Gamma markets have no `category` field; `PMMarket.category`
  is a best-effort value derived from the first nested event's title (may be `nil`).
- **Defensive best bid/ask.** CLOB bids can arrive ascending, so `bestBid` is
  computed via `max` and `bestAsk` via `min` rather than assuming order.
- **Resilient transport.** `PMClient` retries `429` and `5xx` responses with
  jittered exponential backoff.

## Smoke test

`swift run pm-smoke` decodes the captured fixtures and checks the invariants
above. Add `--live` to also hit the network:

```sh
swift run --package-path PolymarketKit pm-smoke --live
```

## Disclaimer

`PolymarketKit` is provided "as is", without warranty of any kind. It is an
unofficial library that talks to Polymarket's public HTTP endpoints; those
endpoints may change without notice. It is not affiliated with, authorized,
endorsed by, or sponsored by Polymarket. Use at your own risk and in accordance
with Polymarket's terms of service.

## License

MIT — see [LICENSE](LICENSE).
