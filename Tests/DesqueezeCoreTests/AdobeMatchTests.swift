import XCTest
@testable import DesqueezeCore

final class AdobeMatchTests: XCTestCase {
    typealias Tag = AdobeMatch.Tag

    /// An adapted lens, as every anamorphic frame has: full match.
    func adapted(iso: Int? = 800, model: String? = "ILCE-7SM3", red: Int = 2597, green: Int = 1024, blue: Int = 1556,
                 noLensCorrection: Bool = true) -> ARWFacts {
        ARWFacts(model: model, iso: iso, daylightLevels: ARWFacts.DaylightLevels(red: red, green: green, blue: blue),
                 saysNoLensCorrection: noLensCorrection)
    }

    /// A lens that reports itself (Sony FE 24-105mm): other daylight levels.
    func lens(iso: Int? = 80) -> ARWFacts {
        adapted(iso: iso, red: 2496, blue: 1617, noLensCorrection: false)
    }

    func value(_ name: String, in match: AdobeMatch.Match) -> String? {
        match.tags.first { $0.name == name }?.value
    }

    // MARK: A full match

    func testAFullMatchGivesEveryTagWithItsGroupInTheOrderOfTheDesign() {
        let match = AdobeMatch.match(adapted(iso: 800))
        XCTAssertNil(match.failed)
        XCTAssertTrue(match.isFull)
        XCTAssertEqual(match.tags, [
            Tag(name: "SubIFD:WhiteLevel", value: "16383"),
            Tag(name: "IFD0:BaselineExposure", value: "0.15"),
            Tag(name: "IFD0:CameraCalibration1", value: "0.9888 0 0 0 1 0 0 0 0.9955"),
            Tag(name: "IFD0:CameraCalibration2", value: "0.9888 0 0 0 1 0 0 0 0.9955"),
            Tag(name: "IFD0:NoiseProfile",
                value: "9.17112993057145e-05 1.80963827089821e-07 0.000132825207904173 1.86198019692823e-07 "
                    + "6.88838025482567e-05 1.77853114759923e-07"),
            Tag(name: "IFD0:BaselineNoise", value: "0.6"),
            Tag(name: "IFD0:BaselineSharpness", value: "1.25"),
            Tag(name: "SubIFD:AntiAliasStrength", value: "1"),
            Tag(name: "SubIFD:BayerGreenSplit", value: "250"),
        ])
    }

    // ISO 50 is the one row with another exposure value.
    func testISO50HasItsOwnBaselineExposure() {
        let match = AdobeMatch.match(adapted(iso: 50))
        XCTAssertTrue(match.isFull)
        XCTAssertEqual(value("IFD0:BaselineExposure", in: match), "-0.85")
        XCTAssertEqual(value("IFD0:NoiseProfile", in: match),
                       "4.21530479896239e-06 1.74264502949702e-09 5.01258869306477e-06 1.72900219262726e-09 "
                           + "3.51529716945144e-06 1.67897845743815e-09")
        XCTAssertEqual(value("IFD0:BaselineExposure", in: AdobeMatch.match(adapted(iso: 80))), "0.15")
    }

    // The two results that the measured files gave (design 13.2).
    func testTheCalibrationIsTheReferenceOverTheDaylightLevelsRoundedToFourPlaces() {
        // The daylight reference of the A7S III, as it was measured.
        let reference = ARWFacts.DaylightLevels(red: 2568, green: 1024, blue: 1549)
        XCTAssertEqual(AdobeMatch.calibration(red: 2597, blue: 1556, reference: reference),
                       "0.9888 0 0 0 1 0 0 0 0.9955")
        XCTAssertEqual(AdobeMatch.calibration(red: 2496, blue: 1617, reference: reference),
                       "1.0288 0 0 0 1 0 0 0 0.9579")
        // The levels of the reference itself give no change.
        XCTAssertEqual(AdobeMatch.calibration(red: 2568, blue: 1549, reference: reference),
                       "1.0000 0 0 0 1 0 0 0 1.0000")
    }

    // The reference is the camera's, and the caller names it: a camera with
    // another reference gets another value for the same levels.
    func testTheCalibrationUsesTheReferenceThatItIsGiven() {
        let other = ARWFacts.DaylightLevels(red: 2000, green: 1024, blue: 2334)
        XCTAssertEqual(AdobeMatch.calibration(red: 2597, blue: 1556, reference: other),
                       "0.7701 0 0 0 1 0 0 0 1.5000")
    }

    func testTheRoundingIsToTheNearestTenThousandth() {
        // 2568 / 2597 = 0.98883…, down. 1549 / 1556 = 0.99550…, down.
        XCTAssertEqual(AdobeMatch.ratio(2568, over: 2597), "0.9888")
        XCTAssertEqual(AdobeMatch.ratio(1549, over: 1556), "0.9955")
        // 2568 / 2496 = 1.02884…, down. 1549 / 1617 = 0.95794…, down.
        XCTAssertEqual(AdobeMatch.ratio(2568, over: 2496), "1.0288")
        XCTAssertEqual(AdobeMatch.ratio(1549, over: 1617), "0.9579")
        // 2 / 3 = 0.66666…, up. 1 / 3 = 0.33333…, down.
        XCTAssertEqual(AdobeMatch.ratio(2, over: 3), "0.6667")
        XCTAssertEqual(AdobeMatch.ratio(1, over: 3), "0.3333")
        // A half goes up: 1 / 20000 = 0.00005.
        XCTAssertEqual(AdobeMatch.ratio(1, over: 20_000), "0.0001")
        XCTAssertEqual(AdobeMatch.ratio(3, over: 2), "1.5000")
        XCTAssertEqual(AdobeMatch.ratio(2568, over: 1), "2568.0000")
    }

    func testEveryISOOfTheTableIsAFullMatchWithTheNumbersOfItsRow() {
        let isos = [50, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1600, 2000, 2500, 3200, 4000,
                    5000, 6400, 8000, 10000, 12800]
        XCTAssertEqual(AdobeMatch.ilce7SM3.byISO.keys.sorted(), isos, "50, and 80 to 12800 with no 1250")
        for iso in isos {
            let match = AdobeMatch.match(adapted(iso: iso))
            XCTAssertTrue(match.isFull, "ISO \(iso)")
            XCTAssertEqual(match.tags.count, 9, "ISO \(iso)")
            XCTAssertEqual(value("IFD0:NoiseProfile", in: match),
                           AdobeMatch.ilce7SM3.byISO[iso]?.noiseProfile.joined(separator: " "), "ISO \(iso)")
        }
    }

    // MARK: No full match

    // Rule 1.
    func testAModelWithNoRowWritesNoTag() {
        for model in ["ILCE-7M4", "ilce-7sm3", "ILCE-7SM3 ", "", nil] as [String?] {
            let match = AdobeMatch.match(adapted(model: model))
            XCTAssertEqual(match.failed, .model, "\(model ?? "nil")")
            XCTAssertEqual(match.tags, [], "\(model ?? "nil")")
            XCTAssertFalse(match.isFull)
        }
    }

    // Rule 2. The camera has ISO 1250, and no file was measured there.
    func testAnISOWithNoRowWritesNoTag() {
        for iso in [1250, 40, 64, 16000, 102_400, 0, nil] as [Int?] {
            let match = AdobeMatch.match(adapted(iso: iso))
            XCTAssertEqual(match.failed, .iso, "\(String(describing: iso))")
            XCTAssertEqual(match.tags, [])
        }
    }

    // Rule 3.
    func testMissingDaylightLevelsWriteNoTag() {
        let none = ARWFacts(model: "ILCE-7SM3", iso: 800, daylightLevels: nil, saysNoLensCorrection: true)
        XCTAssertEqual(AdobeMatch.match(none), AdobeMatch.Match(tags: [], failed: .daylightLevels))
    }

    func testDaylightLevelsWithAnotherGreenOrNoRedOrBlueWriteNoTag() {
        for facts in [adapted(green: 1023), adapted(green: 2048), adapted(red: 0), adapted(blue: 0),
                      adapted(red: -2597)] {
            XCTAssertEqual(AdobeMatch.match(facts), AdobeMatch.Match(tags: [], failed: .daylightLevels),
                           "\(String(describing: facts.daylightLevels))")
        }
    }

    // Rule 4 alone: "matched as far as the table goes". Every tag is written,
    // with the calibration of that lens's daylight levels.
    func testALensFrameGetsEveryTagAndIsNoFullMatch() {
        let match = AdobeMatch.match(lens(iso: 80))
        XCTAssertEqual(match.failed, .noLensCorrection)
        XCTAssertFalse(match.isFull)
        XCTAssertEqual(match.tags.map(\.name), AdobeMatch.match(adapted(iso: 80)).tags.map(\.name))
        XCTAssertEqual(value("IFD0:CameraCalibration1", in: match), "1.0288 0 0 0 1 0 0 0 0.9579")
        XCTAssertEqual(value("IFD0:CameraCalibration2", in: match), "1.0288 0 0 0 1 0 0 0 0.9579")
        XCTAssertEqual(value("SubIFD:WhiteLevel", in: match), "16383")
    }

    // MARK: Rule 5: compressed raw only (design 13.4)

    // The values of the table were measured on compressed raw. Another kind,
    // or an ARW that does not say its kind, gets no tag of the table.
    func testAnARWThatIsNotCompressedRawWritesNoTag() {
        let levels = ARWFacts.DaylightLevels(red: 2597, green: 1024, blue: 1556)
        for kind in [0, 1, 3, 4, nil] as [Int?] {
            let facts = ARWFacts(model: "ILCE-7SM3", iso: 800, daylightLevels: levels, distortionCorrection: 255,
                                 rawFileType: kind)
            XCTAssertEqual(AdobeMatch.match(facts), AdobeMatch.Match(tags: [], failed: .compressedRaw),
                           "\(String(describing: kind))")
            XCTAssertFalse(AdobeMatch.match(facts).isFull)
        }
        let compressed = ARWFacts(model: "ILCE-7SM3", iso: 800, daylightLevels: levels, distortionCorrection: 255,
                                  rawFileType: 2)
        XCTAssertTrue(AdobeMatch.match(compressed).isFull)
        XCTAssertEqual(AdobeMatch.match(compressed).tags.count, 9)
    }

    // A lens frame that is not compressed raw: rule 5 is the reason, and no
    // tag is written. "Matched as far as the table goes" needs rule 5.
    func testALensFrameThatIsNotCompressedRawGetsNoTagAndRule5IsTheReason() {
        let facts = ARWFacts(model: "ILCE-7SM3", iso: 80,
                             daylightLevels: ARWFacts.DaylightLevels(red: 2496, green: 1024, blue: 1617),
                             distortionCorrection: 17, rawFileType: 0)
        XCTAssertEqual(AdobeMatch.match(facts), AdobeMatch.Match(tags: [], failed: .compressedRaw))
        // The lens fact alone, with no value: rule 4, with every tag.
        let silent = ARWFacts(model: "ILCE-7SM3", iso: 80,
                              daylightLevels: ARWFacts.DaylightLevels(red: 2496, green: 1024, blue: 1617),
                              distortionCorrection: nil, rawFileType: 2)
        XCTAssertEqual(AdobeMatch.match(silent).failed, .noLensCorrection)
        XCTAssertEqual(AdobeMatch.match(silent).tags.count, 9)
    }

    // The first rule that fails is the reason. Rules 1 to 3 come before
    // rule 5, and rule 5 before the lens.
    func testTheReasonIsTheFirstRuleThatFails() {
        XCTAssertEqual(AdobeMatch.match(.none).failed, .model)
        XCTAssertEqual(AdobeMatch.match(ARWFacts(model: "ILCE-7SM3", iso: nil, daylightLevels: nil,
                                                 saysNoLensCorrection: false)).failed, .iso)
        XCTAssertEqual(AdobeMatch.match(ARWFacts(model: "ILCE-7SM3", iso: 800, daylightLevels: nil,
                                                 saysNoLensCorrection: false)).failed, .daylightLevels)
        XCTAssertEqual(AdobeMatch.match(lens(iso: 1250)), AdobeMatch.Match(tags: [], failed: .iso),
                       "a lens frame at an ISO with no row gets no tag")
        let uncompressed = { (iso: Int?, levels: ARWFacts.DaylightLevels?) in
            ARWFacts(model: "ILCE-7SM3", iso: iso, daylightLevels: levels, distortionCorrection: 255, rawFileType: 0)
        }
        XCTAssertEqual(AdobeMatch.match(uncompressed(1250, nil)).failed, .iso)
        XCTAssertEqual(AdobeMatch.match(uncompressed(800, nil)).failed, .daylightLevels)
        XCTAssertEqual(AdobeMatch.match(ARWFacts(model: "ILCE-1", iso: 800, daylightLevels: nil,
                                                 distortionCorrection: 255, rawFileType: 0)).failed, .model)
        XCTAssertEqual(AdobeMatch.Rule.allCases.map(\.rawValue), [1, 2, 3, 4, 5], "the numbers of design 13.4")
        XCTAssertEqual(AdobeMatch.Rule.compressedRaw.rawValue, 5)
    }

    // MARK: The table and the data file

    struct DataFile: Decodable {
        struct Reference: Decodable {
            let red: Int
            let green: Int
            let blue: Int
        }

        struct Row: Decodable {
            let baselineExposure: Double
            let noiseProfile: [String]
        }

        let model: String
        let whiteLevel: Double
        let baselineNoise: Double
        let baselineSharpness: Double
        let antiAliasStrength: Double
        let bayerGreenSplit: Double
        let daylightReference: Reference
        let byISO: [String: Row]
    }

    static let dataFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/superpowers/specs/2026-10-09-ilce-7sm3-adobe-values.json")

    // The table is a copy of the data file. This fails when the two differ.
    func testTheTableIsTheDataFile() throws {
        let file = try JSONDecoder().decode(DataFile.self, from: Data(contentsOf: Self.dataFile))
        let table = AdobeMatch.ilce7SM3
        XCTAssertEqual(AdobeMatch.cameras.map(\.model), [file.model], "version 1 has one camera")
        XCTAssertEqual(table.model, file.model)
        XCTAssertEqual(Double(table.whiteLevel), file.whiteLevel)
        XCTAssertEqual(Double(table.baselineNoise), file.baselineNoise)
        XCTAssertEqual(Double(table.baselineSharpness), file.baselineSharpness)
        XCTAssertEqual(Double(table.antiAliasStrength), file.antiAliasStrength)
        XCTAssertEqual(Double(table.bayerGreenSplit), file.bayerGreenSplit)
        XCTAssertEqual([table.daylightReference.red, table.daylightReference.green, table.daylightReference.blue],
                       [file.daylightReference.red, file.daylightReference.green, file.daylightReference.blue])

        XCTAssertEqual(table.byISO.count, 23)
        XCTAssertEqual(Set(table.byISO.keys.map(String.init)), Set(file.byISO.keys))
        for (iso, row) in table.byISO {
            let measured = try XCTUnwrap(file.byISO[String(iso)], "ISO \(iso)")
            XCTAssertEqual(Double(row.baselineExposure), measured.baselineExposure, "ISO \(iso)")
            // As text: the digits of the file, with no pass through `Double`.
            XCTAssertEqual(row.noiseProfile, measured.noiseProfile, "ISO \(iso)")
            XCTAssertEqual(row.noiseProfile.count, 6, "ISO \(iso)")
        }
    }

    // MARK: The read-back compare

    func testNumbersCompareAsNumbers() {
        XCTAssertTrue(AdobeMatch.sameNumbers("16383", "16383"))
        XCTAssertTrue(AdobeMatch.sameNumbers("1", "1.0"))
        XCTAssertTrue(AdobeMatch.sameNumbers("1.0000 0 0 0 1 0 0 0 1.0000", "1 0 0 0 1 0 0 0 1"))
        XCTAssertTrue(AdobeMatch.sameNumbers("0.000132825207904173", "1.32825207904173e-04"))
        XCTAssertTrue(AdobeMatch.sameNumbers("-0.85", "-0.85"))
        XCTAssertTrue(AdobeMatch.sameNumbers("0.15", "0.1500000001"), "the last digit of a rational")
    }

    func testAnotherNumberAnotherCountOrNoNumberIsNotTheSame() {
        XCTAssertFalse(AdobeMatch.sameNumbers("16383", "15360"), "dnglab's own white level")
        XCTAssertFalse(AdobeMatch.sameNumbers("0.15", "-0.85"))
        XCTAssertFalse(AdobeMatch.sameNumbers("0.15", "0"))
        XCTAssertFalse(AdobeMatch.sameNumbers("0", "0.15"))
        XCTAssertFalse(AdobeMatch.sameNumbers("0.9888 0 0 0 1 0 0 0 0.9955", "0.9889 0 0 0 1 0 0 0 0.9955"),
                       "the next value of the rounding")
        XCTAssertFalse(AdobeMatch.sameNumbers("0.9888 0 0 0 1 0 0 0 0.9955", "0.9888 0 0 0 1 0 0 0"))
        XCTAssertFalse(AdobeMatch.sameNumbers("1 1", "1"))
        XCTAssertFalse(AdobeMatch.sameNumbers("1", "-"), "exiftool's sign for no value")
        XCTAssertFalse(AdobeMatch.sameNumbers("1", ""))
        XCTAssertFalse(AdobeMatch.sameNumbers("", ""), "no number is not a match")
        XCTAssertFalse(AdobeMatch.sameNumbers("1", "nan"))
        XCTAssertFalse(AdobeMatch.sameNumbers("nan", "nan"))
        XCTAssertFalse(AdobeMatch.sameNumbers("inf", "inf"))
    }

    // The tolerance must never take one row of the table for another.
    func testTheToleranceCannotHideAWrongTableRow() {
        let rows = AdobeMatch.ilce7SM3.byISO
        var pairs = 0
        for (iso, row) in rows {
            for (other, otherRow) in rows where other != iso {
                XCTAssertFalse(AdobeMatch.sameNumbers(row.noiseProfile.joined(separator: " "),
                                                      otherRow.noiseProfile.joined(separator: " ")),
                               "ISO \(iso) and ISO \(other)")
                pairs += 1
            }
            XCTAssertTrue(AdobeMatch.sameNumbers(row.noiseProfile.joined(separator: " "),
                                                 row.noiseProfile.joined(separator: " ")))
        }
        XCTAssertEqual(pairs, 23 * 22)
        // Two calibration values that differ differ by one ten-thousandth or more.
        XCTAssertFalse(AdobeMatch.sameNumbers("2.9999", "3.0000"))
        XCTAssertFalse(AdobeMatch.sameNumbers("0.0001", "0.0002"))
    }
}
