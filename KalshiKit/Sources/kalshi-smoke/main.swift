import Foundation
import Security
import KalshiKit

// A runnable validation of KalshiKit for environments without XCTest (Command
// Line Tools only). Mirrors the XCTest suite: decode the captured live fixtures
// and prove the RSA-PSS signer produces wire-verifiable signatures.
//
// Usage: swift run kalshi-smoke [fixturesDir]
//   fixturesDir defaults to the package's Tests/KalshiKitTests/Fixtures.

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
    // .../Sources/kalshi-smoke/main.swift → package root → Tests/.../Fixtures
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { root.deleteLastPathComponent() }
    return root.appendingPathComponent("Tests/KalshiKitTests/Fixtures")
}()

func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixturesDir.appendingPathComponent("\(name).json"))
}

print("KalshiKit smoke test")
print("Fixtures: \(fixturesDir.path)\n")

// MARK: - Decoding (against real captured JSON)

print("Decoding live fixtures:")
checkThrows("exchange/status → active") {
    let s = try KalshiJSON.decoder.decode(ExchangeStatus.self, from: fixture("exchange_status"))
    return s.exchangeActive == true && s.tradingActive == true
}
checkThrows("markets → non-empty, status .active, dollar prices") {
    let r = try KalshiJSON.decoder.decode(MarketListResponse.self, from: fixture("markets"))
    guard let m = r.markets.first else { return false }
    return !r.markets.isEmpty && m.status == .active && m.status.isOpen && m.yesAskDollars != nil
}
checkThrows("events → nested markets present") {
    let r = try KalshiJSON.decoder.decode(EventListResponse.self, from: fixture("events"))
    return !r.events.isEmpty && !(r.events.first?.eventTicker.isEmpty ?? true)
}
checkThrows("series → ticker + title") {
    struct W: Decodable { let series: [Series] }
    let w = try KalshiJSON.decoder.decode(W.self, from: fixture("series"))
    guard let s = w.series.first else { return false }
    return !s.ticker.isEmpty && !s.title.isEmpty
}
checkThrows("trades → count_fp + *_price_dollars strings") {
    let r = try KalshiJSON.decoder.decode(TradeListResponse.self, from: fixture("trades"))
    guard let t = r.trades.first else { return false }
    return t.countFp != nil && (t.yesPriceDollars != nil || t.noPriceDollars != nil)
}

// MARK: - Core invariants

print("\nCore invariants:")
checkThrows("KalshiDecimal parses \"0.5600\" exactly (no float error)") {
    struct B: Decodable { let v: KalshiDecimal }
    let b = try KalshiJSON.decoder.decode(B.self, from: Data(#"{"v":"0.5600"}"#.utf8))
    return b.v.value == Decimal(56) / Decimal(100)
}
checkThrows("unknown enum value falls back to .unknown") {
    struct B: Decodable { let s: MarketStatus }
    let b = try KalshiJSON.decoder.decode(B.self, from: Data(#"{"s":"future_status"}"#.utf8))
    return b.s == .unknown
}
check("production base URL correct",
      KalshiEnvironment.production.restBaseURL.absoluteString == "https://external-api.kalshi.com/trade-api/v2")

// MARK: - RSA-PSS signing (sign with KalshiSigner, verify with derived public key)

let pkcs8PEM = """
-----BEGIN PRIVATE KEY-----
MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQCNqS2yId47Wh6V
D5WUQ6GVqRyGcIEPclrDvpK7ZtKYTnCKT2T82H9VEr3hIyiz8ywVlhCwI6dmk48S
AYKjpEB/pA8HolIYVLQAWRM3PsSJ4k/dFd6lHxWJNB/l7o/dg5ZBZdYfxz1Zcl9q
SG00k5YUlrZjiXs1ckD/Db/3VI4mxiEdBvY7adX0cy73WO+BgJw9SCK542LcbLDv
1wqyr44G6+/mQyYEKANqq3pPdKjaQOaQwFiOgk3nxoolH2eEYTB1VCyTC4IbzP/e
GEnXXAQSsisDTm/lQMAeyXPfpNtW82uz7LgYBmhip0/Y7uQD96YX1jF2UZwrdEbO
LmYI3uODAgMBAAECggEAM/ud4h0dgKgcStSyLfr3Y4TwC8FjCrkK54OaMpyTsQIv
uAFUbJhBeYVsGh6dxBL63Vz4+LnMpw6E1LWrK8ONS4l3XnTJLVZ/yxTkwUQOOQ7M
AbQRxIP4kiWHgwec0UuFKrBk97pUH+uhac30DPQPgbSgbzw28zDe+vkftXHYzA8i
uZxU0VWiDx9TVX0XKIJurqGEObr1DzI6V61XWumn5gUyYep9ii6/lsuOLVYzn2vB
i/ST5gCkjQ6LGFq1NFypO0WynT2bCZZPNz6dBCyNbCvsnmw3DclZhkxj9XW7exIo
vmPwKQOFWSq3TlR3ZoNmflGyKJVK1+J78/JCERE00QKBgQC/mI8wuQMcWon8K1ZH
rvcUdzuHWBoP6p1ytTpuvkVqxvf59584yPI5tWu4rIHWiF2pf1AuWMaKocvvjo7v
TNsmFczUgFTeWA9lMU9dY7Ev8dGkya/gcXn9CJYham3q3El70Mr7kVhvTYZcWtXk
FEldqqVdItq98O0cMph6PDImSQKBgQC9R4vanHdGEE94V505R28AS330q0bvu26i
c7bsUj/j1KwdHW/TVe0CzThLaj/kLOnshV7r8QZ5QygxyjR7FGLXkMtQKiFEXNfQ
alHYvVsqjr1dyAH9VwJvKnKzBQfr3IFW2Y4CxcPNSC5ejw61fxdphkzUxSh2rvgs
vih6+yXLawKBgQCpLn+SWGyExvX9NA9V8QvAiKCKHKO21kb9mUXlsCH/7X3evmdc
byRlDOv4AGwOEhASsZcNtdprY/9+o3VXnZgOA0YBhuhqBXxisK4SGwvE+FVUm7uw
BsPfSYu4KhCxSJ+is3XpuihK8DvqpVMluTwnd53ZpgNdobbeJVc66Jin8QKBgQCh
qcUan78DuZSWvYZM0OVOxCu9WLjKszTITbrz10A4cIHckDLdtysq1Gr7hrExSuc1
G6i6Lm+QDLr84661XPEbGtF8E6+8OuwdV2G2k+yUybuVqOmCHtm2ZvP2URq16e0S
Z9hyJ8WXxMnN+7PdcsJlX86pgAeSbtkLJhNfDrj2JwKBgQCTvyY4jSE+9+jmevUk
5rgP6qgF6mehI8QK66IekkuTYsAk/UEguFmBbnBJ0Vwx7XAi9fUZjiBf0BkFGVmW
U48nBTfIGtDpZ7893c/Qa8dxGxavl+rSODvAdjE0BXD/gKSqRh/1nWMwuqn7+Ii3
7Xt+jeM23iLo+EXi9G9XqyYyZQ==
-----END PRIVATE KEY-----
"""

let pkcs1PEM = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEAjaktsiHeO1oelQ+VlEOhlakchnCBD3Jaw76Su2bSmE5wik9k
/Nh/VRK94SMos/MsFZYQsCOnZpOPEgGCo6RAf6QPB6JSGFS0AFkTNz7EieJP3RXe
pR8ViTQf5e6P3YOWQWXWH8c9WXJfakhtNJOWFJa2Y4l7NXJA/w2/91SOJsYhHQb2
O2nV9HMu91jvgYCcPUgiueNi3Gyw79cKsq+OBuvv5kMmBCgDaqt6T3So2kDmkMBY
joJN58aKJR9nhGEwdVQskwuCG8z/3hhJ11wEErIrA05v5UDAHslz36TbVvNrs+y4
GAZoYqdP2O7kA/emF9YxdlGcK3RGzi5mCN7jgwIDAQABAoIBADP7neIdHYCoHErU
si3692OE8AvBYwq5CueDmjKck7ECL7gBVGyYQXmFbBoencQS+t1c+Pi5zKcOhNS1
qyvDjUuJd150yS1Wf8sU5MFEDjkOzAG0EcSD+JIlh4MHnNFLhSqwZPe6VB/roWnN
9Az0D4G0oG88NvMw3vr5H7Vx2MwPIrmcVNFVog8fU1V9FyiCbq6hhDm69Q8yOlet
V1rpp+YFMmHqfYouv5bLji1WM59rwYv0k+YApI0OixhatTRcqTtFsp09mwmWTzc+
nQQsjWwr7J5sNw3JWYZMY/V1u3sSKL5j8CkDhVkqt05Ud2aDZn5RsiiVStfie/Py
QhERNNECgYEAv5iPMLkDHFqJ/CtWR673FHc7h1gaD+qdcrU6br5Fasb3+fefOMjy
ObVruKyB1ohdqX9QLljGiqHL746O70zbJhXM1IBU3lgPZTFPXWOxL/HRpMmv4HF5
/QiWIWpt6txJe9DK+5FYb02GXFrV5BRJXaqlXSLavfDtHDKYejwyJkkCgYEAvUeL
2px3RhBPeFedOUdvAEt99KtG77tuonO27FI/49SsHR1v01XtAs04S2o/5Czp7IVe
6/EGeUMoMco0exRi15DLUCohRFzX0GpR2L1bKo69XcgB/VcCbypyswUH69yBVtmO
AsXDzUguXo8OtX8XaYZM1MUodq74LL4oevsly2sCgYEAqS5/klhshMb1/TQPVfEL
wIigihyjttZG/ZlF5bAh/+193r5nXG8kZQzr+ABsDhIQErGXDbXaa2P/fqN1V52Y
DgNGAYboagV8YrCuEhsLxPhVVJu7sAbD30mLuCoQsUiforN16booSvA76qVTJbk8
J3ed2aYDXaG23iVXOuiYp/ECgYEAoanFGp+/A7mUlr2GTNDlTsQrvVi4yrM0yE26
89dAOHCB3JAy3bcrKtRq+4axMUrnNRuoui5vkAy6/OOutVzxGxrRfBOvvDrsHVdh
tpPslMm7lajpgh7Ztmbz9lEatentEmfYcifFl8TJzfuz3XLCZV/OqYAHkm7ZCyYT
Xw649icCgYEAk78mOI0hPvfo5nr1JOa4D+qoBepnoSPECuuiHpJLk2LAJP1BILhZ
gW5wSdFcMe1wIvX1GY4gX9AZBRlZllOPJwU3yBrQ6We/Pd3P0GvHcRsWr5fq0jg7
wHYxNAVw/4CkqkYf9Z1jMLqp+/iIt+17fo3jNt4i6PhF4vRvV6smMmU=
-----END RSA PRIVATE KEY-----
"""

func derivedPublicKey() -> SecKey? {
    let b64 = pkcs1PEM.split(separator: "\n").filter { !$0.contains("-----") }.joined()
    guard let der = Data(base64Encoded: b64) else { return nil }
    let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate]
    var err: Unmanaged<CFError>?
    guard let priv = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &err) else { return nil }
    return SecKeyCopyPublicKey(priv)
}

func verify(_ headers: [String: String], message: String) -> Bool {
    guard let pub = derivedPublicKey(),
          let b64 = headers["KALSHI-ACCESS-SIGNATURE"],
          let sig = Data(base64Encoded: b64) else { return false }
    var err: Unmanaged<CFError>?
    return SecKeyVerifySignature(pub, .rsaSignatureMessagePSSSHA256,
                                 Data(message.utf8) as CFData, sig as CFData, &err)
}

print("\nRSA-PSS signing:")
checkThrows("PKCS#8 key → signature verifies") {
    let signer = try KalshiSigner(credentials: .init(apiKeyID: "kid", privateKeyPEM: pkcs8PEM))
    let ts: Int64 = 1703123456789
    let path = "/trade-api/v2/portfolio/balance"
    let h = try signer.authHeaders(method: "GET", path: path, timestampMs: ts)
    return h["KALSHI-ACCESS-KEY"] == "kid" && verify(h, message: "\(ts)GET\(path)")
}
checkThrows("PKCS#1 key → signature verifies") {
    let signer = try KalshiSigner(credentials: .init(apiKeyID: "kid", privateKeyPEM: pkcs1PEM))
    let ts: Int64 = 1700000000000
    let path = "/trade-api/v2/portfolio/orders"
    let h = try signer.authHeaders(method: "POST", path: path, timestampMs: ts)
    return verify(h, message: "\(ts)POST\(path)")
}
checkThrows("tampered message does NOT verify") {
    let signer = try KalshiSigner(credentials: .init(apiKeyID: "kid", privateKeyPEM: pkcs8PEM))
    let ts: Int64 = 1700000000000
    let h = try signer.authHeaders(method: "GET", path: "/trade-api/v2/portfolio/balance", timestampMs: ts)
    return verify(h, message: "\(ts)GET/trade-api/v2/portfolio/positions") == false
}

// MARK: - Live network (opt-in: --live) — exercises KalshiClient transport + URL building

if CommandLine.arguments.contains("--live") {
    print("\nLive API (production, keyless):")
    let client = KalshiClient(environment: .production)
    do {
        let status = try await client.exchangeStatus()
        check("GET /exchange/status returns a value", status.exchangeActive != nil)
        let markets = try await client.markets(status: "open", limit: 3)
        check("GET /markets?status=open returns markets", !markets.markets.isEmpty)
        if let m = markets.markets.first {
            print("    e.g. \(m.ticker): yes ask \(m.yesAskDollars?.value.description ?? "—")")
        }
    } catch {
        // Network may be unavailable; report but do not fail the smoke run.
        print("  ⚠︎ live calls skipped/failed (network?): \(error)")
    }

    // The market-data WebSocket requires a SIGNED handshake (verified: keyless
    // upgrade → HTTP 401 token_authentication_failure). Without credentials we
    // can only assert the client cleanly surfaces the auth rejection rather than
    // hanging. With a real signer, the same flow would stream live ticks.
    print("\nLive WebSocket (production, keyless — expects auth rejection):")
    let socket = KalshiSocket(environment: .production)
    let stream = await socket.events()
    await socket.connect()
    if let ticker = try? await client.markets(status: "open", limit: 1).markets.first?.ticker {
        await socket.subscribe(to: [.ticker, .orderbookDelta], markets: [ticker])
        print("    subscribed to \(ticker)")
    }
    let timeout = Task { try? await Task.sleep(for: .seconds(10)); await socket.disconnect() }
    var got: [String] = []
    for await event in stream {
        switch event {
        case .connected: got.append("connected")
        case .subscribed: got.append("subscribed")
        case .ticker: got.append("ticker")
        case .orderbook: got.append("orderbook")
        case .trade: got.append("trade")
        case .serverError: got.append("serverError")
        case .disconnected: got.append("disconnected")
        case .unknown(let t): got.append("unknown(\(t))")
        }
        // Keyless: we expect a disconnect (401), not data. Stop once we see the
        // connection result so the smoke run stays fast.
        if got.contains("disconnected") || got.filter({ $0 != "connected" }).count >= 3 { break }
    }
    timeout.cancel()
    await socket.disconnect()
    // Correct behavior keyless = surfaces a disconnect and does NOT falsely report connected.
    check("WebSocket surfaces auth rejection (no false 'connected')",
          got.contains { $0 == "disconnected" || $0 == "serverError" } && !got.contains("connected"))
    print("    events: \(got.isEmpty ? "(none)" : got.joined(separator: ", "))")
    print("    note: real-time data needs a signed handshake (user API key); REST polling is the keyless fallback.")
}

print("\n\(failures == 0 ? "ALL PASSED ✅" : "\(failures) FAILED ❌")")
exit(failures == 0 ? 0 : 1)
