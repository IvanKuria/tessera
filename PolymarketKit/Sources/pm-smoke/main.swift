import Foundation
import PolymarketKit

// A runnable validation of PolymarketKit for environments without XCTest
// (Command Line Tools only). Mirrors the XCTest suite: decode the captured live
// fixtures and assert the tricky JSON-string-array unwrapping and Decimal
// parsing hold. With `--live` it also fetches a few open markets and an order
// book from the network.
//
// Usage: swift run pm-smoke [fixturesDir] [--live]
//   fixturesDir defaults to the package's Tests/PolymarketKitTests/Fixtures.

var failures = 0
@MainActor func record(_ label: String, _ ok: Bool) {
    if ok { print("  \u{2713} \(label)") }
    else { print("  \u{2717} \(label)"); failures += 1 }
}
@MainActor func check(_ label: String, _ cond: Bool) { record(label, cond) }
@MainActor func checkThrows(_ label: String, _ body: () throws -> Bool) {
    do { record(label, try body()) }
    catch { print("  \u{2717} \(label) — threw \(error)"); failures += 1 }
}

// MARK: - Locate fixtures

let fixturesDir: URL = {
    if let dir = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) {
        return URL(fileURLWithPath: dir)
    }
    // .../Sources/pm-smoke/main.swift → package root → Tests/.../Fixtures
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { root.deleteLastPathComponent() }
    return root.appendingPathComponent("Tests/PolymarketKitTests/Fixtures")
}()

func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixturesDir.appendingPathComponent("\(name).json"))
}

print("PolymarketKit smoke test")
print("Fixtures: \(fixturesDir.path)\n")

// MARK: - Decoding (against real captured JSON)

print("Decoding live fixtures:")
checkThrows("gamma /markets → non-empty, JSON-string arrays unwrapped") {
    let markets = try PMJSON.decoder.decode([PMMarket].self, from: fixture("gamma_markets"))
    guard let m = markets.first else { return false }
    return !markets.isEmpty
        && m.outcomes.count >= 2
        && m.outcomePrices.count == m.outcomes.count
        && m.clobTokenIds.count == m.outcomes.count
        && m.clobTokenIds.allSatisfy { !$0.isEmpty }
        && m.conditionId.hasPrefix("0x")
        && m.endDate != nil
        && m.closed == false
}
checkThrows("gamma /markets → outcomePrices are Decimals in 0...1") {
    let markets = try PMJSON.decoder.decode([PMMarket].self, from: fixture("gamma_markets"))
    guard let m = markets.first else { return false }
    return m.outcomePrices.allSatisfy { $0.value >= 0 && $0.value <= 1 }
}

// Decode the book fixture via the same DTO shape ClobService maps internally.
struct LevelW: Decodable { let price: PMDecimal; let size: PMDecimal }
struct BookW: Decodable { let bids: [LevelW]; let asks: [LevelW] }
checkThrows("clob /book → bids/asks present, prices in 0...1") {
    let b = try PMJSON.decoder.decode(BookW.self, from: fixture("clob_book"))
    let book = PMOrderbook(
        bids: b.bids.map { PMLevel(price: $0.price.value, size: $0.size.value) },
        asks: b.asks.map { PMLevel(price: $0.price.value, size: $0.size.value) }
    )
    guard let bid = book.bestBid, let ask = book.bestAsk else { return false }
    let pricesOK = (book.bids + book.asks).allSatisfy { $0.price >= 0 && $0.price <= 1 }
    return !book.bids.isEmpty && !book.asks.isEmpty && pricesOK
        && bid >= 0 && bid <= 1 && ask >= 0 && ask <= 1
}
checkThrows("clob /price → Decimal in 0...1") {
    struct W: Decodable { let price: PMDecimal }
    let w = try PMJSON.decoder.decode(W.self, from: fixture("clob_price"))
    return w.price.value >= 0 && w.price.value <= 1
}

// MARK: - Core invariants

print("\nCore invariants:")
checkThrows("PMDecimal parses \"0.52\" exactly (no float error)") {
    struct B: Decodable { let v: PMDecimal }
    let b = try PMJSON.decoder.decode(B.self, from: Data(#"{"v":"0.52"}"#.utf8))
    return b.v.value == Decimal(52) / Decimal(100)
}
checkThrows("PMDecimal parses numeric 0.52") {
    struct B: Decodable { let v: PMDecimal }
    let b = try PMJSON.decoder.decode(B.self, from: Data(#"{"v":0.52}"#.utf8))
    return b.v.value == Decimal(52) / Decimal(100)
}
check("centsRounded: 0.525 → 53 (half up)", PMDecimal(Decimal(string: "0.525")!).centsRounded == 53)
check("centsRounded: 0.005 → 1", PMDecimal(Decimal(string: "0.005")!).centsRounded == 1)
check("PMEnvironment gamma base URL correct",
      PMEnvironment.gammaBaseURL.absoluteString == "https://gamma-api.polymarket.com")

// MARK: - Live network (opt-in: --live)

if CommandLine.arguments.contains("--live") {
    print("\nLive API (keyless):")
    let client = PMClient()
    let gamma = GammaService(client: client)
    let clob = ClobService(client: client)
    do {
        let markets = try await gamma.markets(closed: false, limit: 5)
        check("GET gamma /markets returns markets", !markets.isEmpty)
        for m in markets.prefix(3) {
            let prices = m.outcomePrices.map { $0.value.description }.joined(separator: "/")
            print("    \(m.question)")
            print("      outcomes \(m.outcomes) @ \(prices)")
        }
        if let m = markets.first(where: { !$0.clobTokenIds.isEmpty }),
           let token = m.clobTokenIds.first {
            let book = try await clob.book(tokenID: token)
            print("    book for first token: bid \(book.bestBid?.description ?? "—") / ask \(book.bestAsk?.description ?? "—")")
            check("GET clob /book returns levels", !book.bids.isEmpty || !book.asks.isEmpty)
            let mid = try await clob.midpoint(tokenID: token)
            print("    midpoint: \(mid)")
        }
    } catch {
        print("  ⚠︎ live calls skipped/failed (network?): \(error)")
    }
}

print("\n\(failures == 0 ? "ALL PASSED ✅" : "\(failures) FAILED ❌")")
exit(failures == 0 ? 0 : 1)
