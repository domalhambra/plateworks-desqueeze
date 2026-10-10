import XCTest
@testable import DesqueezeCore

/// The real dnglab and the real exiftool, on copies of `fixtures/sample.ARW`
/// in a temporary folder. Skips when a tool or the fixture is absent.
///
/// The fixture is a frame from an adapted lens at ISO 800: the ARW says that
/// it has no lens-correction data, so it is a full match (design 13.4).
class RealDnglabTestCase: XCTestCase {
    /// The nine tags of the match, in the order of design 13.2.
    static let matchedTags = [
        "SubIFD:WhiteLevel", "IFD0:BaselineExposure", "IFD0:CameraCalibration1", "IFD0:CameraCalibration2",
        "IFD0:NoiseProfile", "IFD0:BaselineNoise", "IFD0:BaselineSharpness", "SubIFD:AntiAliasStrength",
        "SubIFD:BayerGreenSplit",
    ]

    var folder: URL!
    var exiftool: URL!
    var dnglab: URL!

    override func setUpWithError() throws {
        let locator = ToolLocator()
        guard FileManager.default.fileExists(atPath: IntegrationTests.fixtures.appendingPathComponent("sample.ARW").path)
        else { throw XCTSkip("No fixtures. Run scripts/make_fixtures.sh with one ARW file.") }
        guard let exiftool = locator.exiftool(), let dnglab = locator.dnglab() else {
            throw XCTSkip("exiftool or dnglab is not installed.")
        }
        self.exiftool = exiftool
        self.dnglab = dnglab
        folder = try makeTemporaryFolder(named: "Shoot with spaces")
    }

    override func tearDown() {
        if let folder { removeTemporaryFolder(folder) }
    }

    func copyFixture(as newName: String, into directory: URL? = nil) throws -> URL {
        let destination = (directory ?? folder).appendingPathComponent(newName)
        try FileManager.default.copyItem(at: IntegrationTests.fixtures.appendingPathComponent("sample.ARW"),
                                         to: destination)
        return destination
    }

    var converter: DnglabConverter { DnglabConverter(executable: dnglab, exiftool: exiftool) }

    func facts(of arw: URL) throws -> ARWFacts {
        try XCTUnwrap(ARWFactsReader(exiftool: exiftool).read([arw])[arw.lastPathComponent])
    }

    /// The values of `tags` in `file`, as exiftool prints them with `-n`.
    /// `-` is "no such tag".
    func read(_ tags: [String], in file: URL) throws -> [String] {
        let result = try SystemProcessRunner().run(exiftool, ["-m", "-n", "-T"] + tags.map { "-\($0)" } + [file.path])
        let row = result.stdout.split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
        let cells = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(cells.count, tags.count, "exiftool gave no row for \(file.lastPathComponent): \(result.stderr)")
        return cells
    }

    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }
}

final class DnglabIntegrationTests: RealDnglabTestCase {
    func testTheFixtureIsAFrameFromAnAdaptedLensWithAFullMatch() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let facts = try facts(of: arw)
        XCTAssertEqual(facts, ARWFacts(
            model: "ILCE-7SM3", iso: 800,
            daylightLevels: ARWFacts.DaylightLevels(red: 2597, green: 1024, blue: 1556),
            saysNoLensCorrection: true))
        XCTAssertTrue(AdobeMatch.match(facts).isFull)
    }

    // One read for a list: a photo, and a file that exiftool cannot read.
    func testARealReadGivesFactsForAPhotoAndNoneForAFileThatIsNoPhoto() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let junk = folder.appendingPathComponent("junk.ARW")
        try Data("not a photo".utf8).write(to: junk)
        let before = try Data(contentsOf: arw)

        let read = ARWFactsReader(exiftool: exiftool).read([arw, junk])

        XCTAssertEqual(read["frame.ARW"]?.iso, 800)
        XCTAssertEqual(read["junk.ARW"], ARWFacts.none)
        XCTAssertEqual(try names(), ["frame.ARW", "junk.ARW"], "the read makes no file")
        XCTAssertEqual(try Data(contentsOf: arw), before, "the read changes no file")
    }

    func testARealConversionWritesTheMatchAndTheDNGIsValid() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let arwBefore = try Data(contentsOf: arw)

        let conversion = try converter.convert(arw, facts: try facts(of: arw))

        let dng = folder.appendingPathComponent("frame.dng")
        XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: nil))
        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng"], "no backup and no work file stays")
        XCTAssertEqual(try Data(contentsOf: arw), arwBefore, "the ARW must not change")

        // The tags, read back from the file. Adobe's values for this frame.
        let values = try read(Self.matchedTags + ["IFD0:OriginalRawFileName"], in: dng)
        let expected = [
            "16383", "0.15", "0.9888 0 0 0 1 0 0 0 0.9955", "0.9888 0 0 0 1 0 0 0 0.9955",
            "9.17112993057145e-05 1.80963827089821e-07 0.000132825207904173 1.86198019692823e-07 "
                + "6.88838025482567e-05 1.77853114759923e-07",
            "0.6", "1.25", "1", "250",
        ]
        for (tag, (value, wanted)) in zip(Self.matchedTags, zip(values, expected)) {
            XCTAssertTrue(AdobeMatch.sameNumbers(wanted, value), "\(tag): \(value), not \(wanted)")
        }
        XCTAssertEqual(values.last, "frame.ARW", "the pending rule needs the file name")

        // dnglab embeds the whole ARW by default. `--embed-raw false` stops that.
        XCTAssertEqual(try read(["IFD0:OriginalRawFileData"], in: dng), ["-"], "no embedded raw")
        let size = try XCTUnwrap(ConverterOutput.size(atPath: dng.path))
        XCTAssertLessThan(size, arwBefore.count, "a DNG with the ARW inside is larger than the ARW")

        let validate = try SystemProcessRunner().run(exiftool, ["-validate", "-s3", dng.path])
        XCTAssertEqual(validate.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "OK", validate.stderr)

        // The DNG claims its ARW by the tag, also under another name.
        let renamed = folder.appendingPathComponent("261004 Backyard Photos 0022.dng")
        try FileManager.default.moveItem(at: dng, to: renamed)
        let backups = FileBackups(trash: { try FileManager.default.removeItem(at: $0) })
        let snapshot = try FolderScanner(tag: ScaleTag(exiftool: exiftool), backups: backups).snapshot(of: folder)
        XCTAssertEqual(snapshot.dngs.map(\.originalRawFileName), ["frame.ARW"])
        XCTAssertEqual(snapshot.dngs.map(\.scale), [.noStretch], "dnglab writes no stretch")
        XCTAssertEqual(snapshot.pendingARWs, [])
    }

    // With no table row, the levels stay dnglab's own. The file name is
    // written all the same.
    func testARealConversionWithNoFactsWritesOnlyTheFileName() throws {
        let arw = try copyFixture(as: "frame.ARW")

        let conversion = try converter.convert(arw, facts: .none)

        let dng = folder.appendingPathComponent("frame.dng")
        XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: .model))
        let values = try read(Self.matchedTags + ["IFD0:OriginalRawFileName"], in: dng)
        XCTAssertEqual(values.first, "15360", "dnglab's own white level")
        XCTAssertEqual(Array(values[1..<9]), Array(repeating: "-", count: 8), "no other tag of the match")
        XCTAssertEqual(values.last, "frame.ARW")
        let validate = try SystemProcessRunner().run(exiftool, ["-validate", "-s3", dng.path])
        XCTAssertEqual(validate.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "OK", validate.stderr)
    }

    // dnglab's exit code is the truth: 7 for a file that it cannot read, and
    // no DNG.
    func testARealDnglabOnAFileThatIsNoPhotoFailsAndLeavesNoDNG() throws {
        let junk = folder.appendingPathComponent("junk.ARW")
        try Data("not a photo".utf8).write(to: junk)
        XCTAssertThrowsError(try converter.convert(junk, facts: .none)) {
            XCTAssertEqual($0 as? ConvertError, .failed("dnglab returned 7.", partial: nil))
        }
        XCTAssertEqual(try names(), ["junk.ARW"])
    }

    func testARealConverterLeavesADNGThatIsThereAlreadyAsItIs() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let dng = folder.appendingPathComponent("frame.dng")
        try Data("an older DNG".utf8).write(to: dng)
        XCTAssertThrowsError(try converter.convert(arw, facts: try facts(of: arw))) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("A DNG with this name exists already. Not converted.", partial: nil))
        }
        XCTAssertEqual(try Data(contentsOf: dng), Data("an older DNG".utf8))
        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng"])
    }
}

/// The drift check (design 13.8).
///
/// Converts the fixture with the real Adobe DNG Converter and with the app's
/// dnglab path, and compares every tag of the match. It fails when a new
/// Adobe version, a new dnglab version, or new camera firmware changes a
/// value. Skips unless dnglab, Adobe DNG Converter and the fixtures are all
/// there. It starts Adobe DNG Converter once.
final class AdobeDriftTests: RealDnglabTestCase {
    func testEveryMatchedTagOfADnglabDNGEqualsAdobeDNGConverters() throws {
        guard let adobe = ToolLocator().dngConverter() else {
            throw XCTSkip("Adobe DNG Converter is not installed.")
        }
        let files = FileManager.default
        let adobeFolder = folder.appendingPathComponent("Adobe")
        let dnglabFolder = folder.appendingPathComponent("dnglab")
        try files.createDirectory(at: adobeFolder, withIntermediateDirectories: false)
        try files.createDirectory(at: dnglabFolder, withIntermediateDirectories: false)
        let forAdobe = try copyFixture(as: "frame.ARW", into: adobeFolder)
        let forDnglab = try copyFixture(as: "frame.ARW", into: dnglabFolder)

        let adobes = try AdobeConverter(executable: adobe).convert(forAdobe).dng
        let facts = try facts(of: forDnglab)
        let ours = try converter.convert(forDnglab, facts: facts)
        XCTAssertNil(ours.unmatched, "the fixture is a full match: \(facts)")

        let wanted = try read(Self.matchedTags, in: adobes)
        let found = try read(Self.matchedTags, in: ours.dng)
        for (tag, (adobeValue, ourValue)) in zip(Self.matchedTags, zip(wanted, found)) {
            XCTAssertNotEqual(adobeValue, "-", "Adobe DNG Converter no longer writes \(tag)")
            XCTAssertTrue(AdobeMatch.sameNumbers(adobeValue, ourValue),
                          "\(tag) drifted. Adobe DNG Converter: \(adobeValue). The match: \(ourValue).")
        }
        // Both name the ARW, so each DNG claims it.
        XCTAssertEqual(try read(["IFD0:OriginalRawFileName"], in: adobes), ["frame.ARW"])
        XCTAssertEqual(try read(["IFD0:OriginalRawFileName"], in: ours.dng), ["frame.ARW"])
    }
}
