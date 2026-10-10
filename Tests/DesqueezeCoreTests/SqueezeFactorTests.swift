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

    // The tool and the MCP server refuse a factor with this one sentence.
    func testTheMessageForAFactorThatBreaksTheRule() {
        XCTAssertEqual(SqueezeFactor.errorMessage(got: "5"),
                       "The factor must be a number from 1 to 4, with at most four decimal places. It was \"5\".")
        XCTAssertEqual(SqueezeFactor.errorMessage(got: "1.23456"),
                       "The factor must be \(SqueezeFactor.ruleText). It was \"1.23456\".")
    }

    // The text is in quotes, so the sentence reads correctly for any text:
    // one that ends with a comma or a period, one with a space in it, and
    // no text at all. Without the quotes, "1.5," gave "It was 1.5,. Use a
    // period", and no text gave "It was .".
    func testTheMessageReadsCorrectlyForAnyText() {
        let rule = "The factor must be a number from 1 to 4, with at most four decimal places."
        XCTAssertEqual(SqueezeFactor.errorMessage(got: "1.5,"),
                       "\(rule) It was \"1.5,\". Use a period for the decimal point.")
        XCTAssertEqual(SqueezeFactor.errorMessage(got: "1."), "\(rule) It was \"1.\".")
        XCTAssertEqual(SqueezeFactor.errorMessage(got: ""), "\(rule) It was \"\".")
        XCTAssertEqual(SqueezeFactor.errorMessage(got: " "), "\(rule) It was \" \".")
        XCTAssertEqual(SqueezeFactor.errorMessage(got: "one and a half"), "\(rule) It was \"one and a half\".")
        for text in ["1.5,", "1.", "", " ", "1,5", "5", "1,5.", "?"] {
            let message = SqueezeFactor.errorMessage(got: text)
            XCTAssertFalse(message.contains(",."), "\(text): \(message)")
            XCTAssertFalse(message.contains(".."), "\(text): \(message)")
            XCTAssertFalse(message.contains(" ."), "\(text): \(message)")
        }
    }

    // "1,5" breaks the rule, and the rule alone does not say how. Every
    // front end adds these words, from here.
    func testAFactorWithACommaGetsTheHintAboutThePeriod() {
        XCTAssertEqual(SqueezeFactor.errorMessage(got: "1,5"),
                       "The factor must be a number from 1 to 4, with at most four decimal places. "
                           + "It was \"1,5\". Use a period for the decimal point.")
        XCTAssertEqual(SqueezeFactor.decimalPointHint, "Use a period for the decimal point.")
        XCTAssertEqual(SqueezeFactor.hint(for: "1,5"), " Use a period for the decimal point.")
        XCTAssertEqual(SqueezeFactor.hint(for: " 1,33 "), " Use a period for the decimal point.")
        for text in ["5", "1.5", "abc", "", "1 5", "1.33333"] {
            XCTAssertEqual(SqueezeFactor.hint(for: text), "", "no comma in \"\(text)\"")
            XCTAssertFalse(SqueezeFactor.errorMessage(got: text).contains("period"), text)
        }
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
