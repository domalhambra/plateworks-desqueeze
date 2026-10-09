import XCTest
@testable import DesqueezeCore

final class SqueezeFactorTests: XCTestCase {
    func testPresetsAreTheFourLensFactorsInOrder() {
        XCTAssertEqual(SqueezeFactor.presets.map(\.label), ["1.33", "1.5", "1.8", "2"])
    }

    func testTagValueIsFactorThenOne() {
        XCTAssertEqual(SqueezeFactor(1.5)?.tagValue, "1.5 1")
        XCTAssertEqual(SqueezeFactor(2)?.tagValue, "2 1")
        XCTAssertEqual(SqueezeFactor(1.3333)?.tagValue, "1.3333 1")
        XCTAssertEqual(SqueezeFactor.noStretch.tagValue, "1 1")
    }

    func testRangeIsOneToFourInclusive() {
        XCTAssertNotNil(SqueezeFactor(1))
        XCTAssertNotNil(SqueezeFactor(4))
        XCTAssertNil(SqueezeFactor(0.99))
        XCTAssertNil(SqueezeFactor(4.01))
        XCTAssertNil(SqueezeFactor(0))
    }

    func testTextAcceptsPlainDecimals() {
        XCTAssertEqual(SqueezeFactor(text: "1.6")?.label, "1.6")
        XCTAssertEqual(SqueezeFactor(text: " 1.6 ")?.label, "1.6")
        XCTAssertEqual(SqueezeFactor(text: "2")?.label, "2")
        XCTAssertEqual(SqueezeFactor(text: "1.3333")?.label, "1.3333")
    }

    func testTextRejectsEverythingElse() {
        for bad in ["", "abc", "1,5", "-2", "5", "0.5", "2.", ".5", "1.33333", "1.5x", "1 5"] {
            XCTAssertNil(SqueezeFactor(text: bad), "accepted \(bad)")
        }
    }

    // Each front end puts its own first words before this, and a period after.
    func testTheRuleInWords() {
        XCTAssertEqual(SqueezeFactor.ruleText, "a number from 1 to 4, with at most four decimal places")
    }

    func testMatchesTellsAdjacentFactorsApart() {
        let factor = SqueezeFactor(1.5)!
        XCTAssertTrue(factor.matches(horizontal: 1.5, vertical: 1))
        XCTAssertTrue(factor.matches(horizontal: 1.50004, vertical: 1))
        XCTAssertFalse(factor.matches(horizontal: 1.5001, vertical: 1))
        XCTAssertFalse(factor.matches(horizontal: 1.4999, vertical: 1))
        XCTAssertFalse(factor.matches(horizontal: 1.5, vertical: 2))
        XCTAssertFalse(SqueezeFactor(2)!.matches(horizontal: 2.0001, vertical: 1))
    }

    func testValueIsRoundedSoEqualLabelsAreEqualFactors() {
        XCTAssertEqual(SqueezeFactor(text: "1.5"), SqueezeFactor(1.5))
        XCTAssertEqual(SqueezeFactor(1.50001), SqueezeFactor(1.5))
        XCTAssertEqual(SqueezeFactor(1.50001)?.value, 1.5)
        XCTAssertEqual(SqueezeFactor(1.23456)?.label, "1.2346")
    }

    func testAnUnknownScaleMatchesNoFactor() {
        XCTAssertFalse(SqueezeFactor.noStretch.matches(nil))
        XCTAssertFalse(SqueezeFactor(1.5)!.matches(nil))
        XCTAssertTrue(SqueezeFactor.noStretch.matches(Scale.noStretch))
        XCTAssertTrue(SqueezeFactor(1.5)!.matches(Scale(horizontal: 1.5, vertical: 1)))
        XCTAssertFalse(SqueezeFactor(1.5)!.matches(Scale.noStretch))
    }
}
