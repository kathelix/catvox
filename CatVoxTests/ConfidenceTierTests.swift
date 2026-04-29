import XCTest
@testable import CatVox

final class ConfidenceTierTests: XCTestCase {
    func testTRDConfidenceThresholds() {
        XCTAssertEqual(ConfidenceTier.from(score: 0.81), .high)
        XCTAssertEqual(ConfidenceTier.from(score: 0.80001), .high)

        XCTAssertEqual(ConfidenceTier.from(score: 0.80), .moderate)
        XCTAssertEqual(ConfidenceTier.from(score: 0.50), .moderate)

        XCTAssertEqual(ConfidenceTier.from(score: 0.49999), .low)
        XCTAssertEqual(ConfidenceTier.from(score: 0.0), .low)
    }
}
