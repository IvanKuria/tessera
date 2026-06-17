import XCTest
import Foundation
import Security
@testable import KalshiKit

/// Verifies the RSA-PSS signer produces signatures that actually verify against
/// the matching public key with Kalshi's exact PSS parameters (SHA-256, MGF1,
/// salt = digest length). This proves both the PKCS#8→PKCS#1 import path and the
/// signing-string construction are wire-correct. Throwaway 2048-bit test keypair.
final class SignerTests: XCTestCase {

    // PKCS#8 form (-----BEGIN PRIVATE KEY-----)
    static let pkcs8PEM = """
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

    // PKCS#1 form (-----BEGIN RSA PRIVATE KEY-----) — same key, traditional encoding.
    static let pkcs1PEM = """
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

    /// Imports the public key derived from the PKCS#1 private key, for verification.
    private func publicKey() throws -> SecKey {
        let b64 = Self.pkcs1PEM
            .split(separator: "\n")
            .filter { !$0.contains("-----") }
            .joined()
        let der = try XCTUnwrap(Data(base64Encoded: b64))
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        let priv = try XCTUnwrap(SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &error),
                                 "private import failed")
        return try XCTUnwrap(SecKeyCopyPublicKey(priv), "public derive failed")
    }

    private func verify(headers: [String: String], message: String) throws -> Bool {
        let pub = try publicKey()
        let sig = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(headers["KALSHI-ACCESS-SIGNATURE"])))
        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(
            pub, .rsaSignatureMessagePSSSHA256,
            Data(message.utf8) as CFData, sig as CFData, &error
        )
    }

    func testSignsAndVerifiesFromPKCS8() throws {
        let signer = try KalshiSigner(credentials: .init(apiKeyID: "test-key-id", privateKeyPEM: Self.pkcs8PEM))
        let ts: Int64 = 1703123456789
        let path = "/trade-api/v2/portfolio/balance"
        let headers = try signer.authHeaders(method: "GET", path: path, timestampMs: ts)
        XCTAssertEqual(headers["KALSHI-ACCESS-KEY"], "test-key-id")
        XCTAssertEqual(headers["KALSHI-ACCESS-TIMESTAMP"], "1703123456789")
        XCTAssertTrue(try verify(headers: headers, message: "\(ts)GET\(path)"))
    }

    func testSignsAndVerifiesFromPKCS1() throws {
        let signer = try KalshiSigner(credentials: .init(apiKeyID: "kid2", privateKeyPEM: Self.pkcs1PEM))
        let ts: Int64 = 1700000000000
        let path = "/trade-api/v2/portfolio/orders"
        let headers = try signer.authHeaders(method: "POST", path: path, timestampMs: ts)
        XCTAssertTrue(try verify(headers: headers, message: "\(ts)POST\(path)"))
    }

    func testWrongMessageFailsVerification() throws {
        let signer = try KalshiSigner(credentials: .init(apiKeyID: "kid", privateKeyPEM: Self.pkcs8PEM))
        let ts: Int64 = 1700000000000
        let headers = try signer.authHeaders(method: "GET", path: "/trade-api/v2/portfolio/balance", timestampMs: ts)
        // Tampered message must NOT verify.
        XCTAssertFalse(try verify(headers: headers, message: "\(ts)GET/trade-api/v2/portfolio/positions"))
    }
}
