import XCTest
@testable import DesqueezeCore

/// The table of design 13.4, one test for each row.
final class ConverterChoiceTests: XCTestCase {
    func order(fullMatch: Bool, dnglab: Bool, adobe: Bool) -> [ConverterKind] {
        ConverterChoice.order(fullMatch: fullMatch, dnglabInstalled: dnglab, adobeInstalled: adobe)
    }

    // The name that a sentence gives each converter. The JSON has the raw
    // values, `dnglab` and `adobe`.
    func testEachConverterHasTheNameThatASentenceGivesIt() {
        XCTAssertEqual(ConverterKind.dnglab.name, "dnglab")
        XCTAssertEqual(ConverterKind.adobe.name, "Adobe DNG Converter")
        XCTAssertEqual(ConverterKind.allCases.map(\.rawValue), ["dnglab", "adobe"])
    }

    // "dnglab, matched", and "Adobe, then failed if Adobe fails too" when
    // dnglab or its match failed: Adobe is second in the list.
    func testAFullMatchWithBothInstalledGoesToDnglabThenToAdobe() {
        XCTAssertEqual(order(fullMatch: true, dnglab: true, adobe: true), [.dnglab, .adobe])
    }

    // "dnglab, matched". When it fails, the ARW failed: no one is next.
    func testAFullMatchWithOnlyDnglabGoesToDnglab() {
        XCTAssertEqual(order(fullMatch: true, dnglab: true, adobe: false), [.dnglab])
    }

    func testAFullMatchWithOnlyAdobeGoesToAdobe() {
        XCTAssertEqual(order(fullMatch: true, dnglab: false, adobe: true), [.adobe])
    }

    func testAFullMatchWithNeitherIsNotConverted() {
        XCTAssertEqual(order(fullMatch: true, dnglab: false, adobe: false), [])
    }

    // Adobe gives the file that Lightroom makes. dnglab is not asked, also
    // not after Adobe failed.
    func testNoFullMatchWithBothInstalledGoesToAdobeOnly() {
        XCTAssertEqual(order(fullMatch: false, dnglab: true, adobe: true), [.adobe])
    }

    // "dnglab, matched as far as the table goes, with a note".
    func testNoFullMatchWithOnlyDnglabGoesToDnglab() {
        XCTAssertEqual(order(fullMatch: false, dnglab: true, adobe: false), [.dnglab])
    }

    func testNoFullMatchWithOnlyAdobeGoesToAdobe() {
        XCTAssertEqual(order(fullMatch: false, dnglab: false, adobe: true), [.adobe])
    }

    func testNoFullMatchWithNeitherIsNotConverted() {
        XCTAssertEqual(order(fullMatch: false, dnglab: false, adobe: false), [])
    }

    // MARK: From the facts

    let adapted = ARWFacts(model: "ILCE-7SM3", iso: 800,
                           daylightLevels: ARWFacts.DaylightLevels(red: 2597, green: 1024, blue: 1556),
                           saysNoLensCorrection: true)

    func testTheFactsDecideWhatAFullMatchIs() {
        func order(_ facts: ARWFacts) -> [ConverterKind] {
            ConverterChoice.order(for: facts, dnglabInstalled: true, adobeInstalled: true)
        }
        XCTAssertEqual(order(adapted), [.dnglab, .adobe])
        let lens = ARWFacts(model: "ILCE-7SM3", iso: 800, daylightLevels: adapted.daylightLevels,
                            saysNoLensCorrection: false)
        XCTAssertEqual(order(lens), [.adobe])
        let iso1250 = ARWFacts(model: "ILCE-7SM3", iso: 1250, daylightLevels: adapted.daylightLevels,
                               saysNoLensCorrection: true)
        // Rule 5: an ARW that is not compressed raw has no full match.
        for kind in [0, nil] as [Int?] {
            let other = ARWFacts(model: "ILCE-7SM3", iso: 800, daylightLevels: adapted.daylightLevels,
                                 saysNoLensCorrection: true, rawFileType: kind)
            XCTAssertEqual(ConverterChoice.order(for: other, dnglabInstalled: true, adobeInstalled: true), [.adobe])
            XCTAssertEqual(ConverterChoice.order(for: other, dnglabInstalled: true, adobeInstalled: false), [.dnglab])
        }
        XCTAssertEqual(order(iso1250), [.adobe])
        XCTAssertEqual(order(.none), [.adobe], "a file with no facts has no full match")
    }

    // The sentences about who converts are made once, here. The help of the
    // tool and the MCP descriptions say them (design 13.5).
    func testTheSentencesAboutWhoConvertsAreMadeOnce() {
        XCTAssertEqual(ConverterText.whoConverts,
                       "dnglab converts each photo that it can match. "
                           + "Adobe DNG Converter, when it is installed, converts the others.")
        XCTAssertEqual(ConverterText.matchedValues,
                       "Each DNG that dnglab makes gets the values that Adobe DNG Converter writes, "
                           + "so Lightroom shows the same photo.")
        // The short form is not the rule: the table sends a photo with no
        // full match to Adobe, and dnglab is not tried.
        XCTAssertFalse(ConverterText.whoConverts.contains("first"))
    }

    func testTheJSONNamesOfTheTwoConverters() {
        XCTAssertEqual(ConverterKind.allCases.map(\.rawValue), ["dnglab", "adobe"])
    }
}
