import XCTest
@testable import KalshiKit

final class MarketDataServiceTests: XCTestCase {

    // MARK: - centsRounded helper

    func testCentsRoundedWholeDollar() {
        XCTAssertEqual(KalshiDecimal(Decimal(string: "1.00")!).centsRounded, 100)
    }

    func testCentsRoundedTypicalPrice() {
        XCTAssertEqual(KalshiDecimal(Decimal(string: "0.56")!).centsRounded, 56)
    }

    func testCentsRoundedZero() {
        XCTAssertEqual(KalshiDecimal(Decimal(0)).centsRounded, 0)
    }

    func testCentsRoundedHalfCentRoundsUp() {
        // 0.005 dollars == 0.5 cents -> rounds half-up to 1.
        XCTAssertEqual(KalshiDecimal(Decimal(string: "0.005")!).centsRounded, 1)
    }

    func testCentsRoundedRoundsDownBelowHalf() {
        // 0.0049 dollars == 0.49 cents -> rounds to 0.
        XCTAssertEqual(KalshiDecimal(Decimal(string: "0.0049")!).centsRounded, 0)
    }

    func testCentsRoundedLargeValue() {
        XCTAssertEqual(KalshiDecimal(Decimal(string: "1234.00")!).centsRounded, 123400)
    }

    func testCentsRoundedSubCentRoundsToNearest() {
        // 0.567 dollars == 56.7 cents -> 57.
        XCTAssertEqual(KalshiDecimal(Decimal(string: "0.567")!).centsRounded, 57)
    }

    // MARK: - Construction

    func testServiceConstructsWithDefaultEnvironment() {
        let service = MarketDataService()
        XCTAssertNotNil(service)
    }

    func testServiceConstructsWithDemoEnvironment() {
        let service = MarketDataService(environment: .demo)
        XCTAssertNotNil(service)
    }
}
