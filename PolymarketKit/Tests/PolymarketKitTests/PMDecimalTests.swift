import XCTest
@testable import PolymarketKit

final class PMDecimalTests: XCTestCase {
    private struct Box: Decodable { let v: PMDecimal }

    func testParsesDecimalStringExactly() throws {
        let b = try PMJSON.decoder.decode(Box.self, from: Data(#"{"v":"0.52"}"#.utf8))
        XCTAssertEqual(b.v.value, Decimal(52) / Decimal(100))
    }

    func testParsesNumericValue() throws {
        let b = try PMJSON.decoder.decode(Box.self, from: Data(#"{"v":0.52}"#.utf8))
        XCTAssertEqual(b.v.value, Decimal(52) / Decimal(100))
    }

    func testParsesLargeStringDecimal() throws {
        let b = try PMJSON.decoder.decode(Box.self, from: Data(#"{"v":"828622.70"}"#.utf8))
        XCTAssertEqual(b.v.value, Decimal(string: "828622.70"))
    }

    func testInitFromInvalidStringFails() {
        XCTAssertNil(PMDecimal(string: "not-a-number"))
    }

    func testCentsRoundedHalfUp() {
        XCTAssertEqual(PMDecimal(Decimal(string: "0.525")!).centsRounded, 53)
        XCTAssertEqual(PMDecimal(Decimal(string: "0.62")!).centsRounded, 62)
        XCTAssertEqual(PMDecimal(Decimal(string: "0.005")!).centsRounded, 1)
        XCTAssertEqual(PMDecimal(Decimal(string: "0.0")!).centsRounded, 0)
        XCTAssertEqual(PMDecimal(Decimal(string: "1.0")!).centsRounded, 100)
    }

    func testComparable() {
        XCTAssertTrue(PMDecimal(Decimal(string: "0.48")!) < PMDecimal(Decimal(string: "0.52")!))
        XCTAssertFalse(PMDecimal(Decimal(string: "0.52")!) < PMDecimal(Decimal(string: "0.52")!))
    }

    func testEncodeRoundTripsAsString() throws {
        let original = PMDecimal(Decimal(string: "0.52")!)
        let data = try PMJSON.encoder.encode(original)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"0.52\"")
        let back = try PMJSON.decoder.decode(PMDecimal.self, from: data)
        XCTAssertEqual(back, original)
    }
}
