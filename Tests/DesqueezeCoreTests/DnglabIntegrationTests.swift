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

    /// A converter with no leftover to discard: a test that has one gives
    /// its own action.
    var converter: DnglabConverter {
        DnglabConverter(executable: dnglab, exiftool: exiftool,
                        discardLeftover: { XCTFail("no leftover was expected: \($0.lastPathComponent)") })
    }

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
            distortionCorrection: 255, rawFileType: 2), "no lens-correction data, and compressed raw")
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
        // `names()` lists hidden files too: the folder holds the ARW and the
        // DNG, and nothing else.
        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng"], "no backup and no work file stays")
        XCTAssertFalse(ConverterOutput.exists(atPath: ConverterOutput.workURL(for: arw).path))
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
    // no DNG. Its own reason follows the exit code.
    func testARealDnglabOnAFileThatIsNoPhotoFailsAndLeavesNoDNG() throws {
        let junk = folder.appendingPathComponent("junk.ARW")
        try Data("not a photo".utf8).write(to: junk)
        XCTAssertThrowsError(try converter.convert(junk, facts: .none)) {
            XCTAssertEqual($0 as? ConvertError, .failed(
                "dnglab returned 7. Unsupported file: Error: No decoder found, model '', make: '', mode: ''.",
                partial: nil))
        }
        XCTAssertEqual(try names(), ["junk.ARW"])
    }

    // MARK: The work file (design 13.3)

    /// A folder that stands for the Trash, beside the photo folder.
    func makeTrash() throws -> (folder: URL, backups: FileBackups) {
        let trash = folder.deletingLastPathComponent().appendingPathComponent("Test trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return (trash, try FileBackups.fromEnvironment([FileBackups.testFolderVariable: trash.path]).backups)
    }

    // Another program makes `frame.dng` after the check before the start,
    // just before the rename. Its file must not change and must not go to
    // the Trash. dnglab's work file goes there, and no other converter gets
    // the ARW.
    func testADNGThatAnotherProgramMakesJustBeforeTheRenameIsLeftAsItIs() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let dng = folder.appendingPathComponent("frame.dng")
        let (trash, backups) = try makeTrash()
        let others = Data("another program's DNG".utf8)
        let dnglabs = DnglabConverter(
            executable: dnglab, exiftool: exiftool, discardLeftover: { try backups.trashFile($0) },
            rename: { work, name in
                FileManager.default.createFile(atPath: name.path, contents: others)
                return ExclusiveRename.system.move(work, to: name)
            })
        let adobeRunner = FakeRunner()
        let adobes = AdobeConverter(executable: URL(fileURLWithPath: "/nonexistent/Adobe DNG Converter"),
                                    runner: adobeRunner, discardLeftover: { try backups.trashFile($0) })
        let job = DesqueezeJob(
            tag: ScaleTag(exiftool: exiftool),
            converters: RawConverters(dnglab: dnglabs, adobe: adobes, facts: ARWFactsReader(exiftool: exiftool)),
            backups: backups)

        let summary = try job.run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true)

        XCTAssertEqual(try Data(contentsOf: dng), others, "the DNG of the other program has the same bytes")
        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng"], "no work file stays, hidden files counted")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), [".frame.desqueeze-work.dng"],
                       "only the work file is in the injected trash")
        // The work file was complete: dnglab's DNG, with the match in it.
        XCTAssertEqual(try read(["SubIFD:WhiteLevel", "IFD0:OriginalRawFileName"],
                                in: trash.appendingPathComponent(".frame.desqueeze-work.dng")),
                       ["16383", "frame.ARW"])
        XCTAssertEqual(adobeRunner.calls, [], "the next converter is not tried")
        XCTAssertEqual(summary.notes, [FileNote(name: "frame.ARW", kind: .notConverted, message: "Not converted.",
                                                detail: "A DNG with this name exists already. Not converted.")])
        XCTAssertEqual([summary.converted, summary.set, summary.failed, summary.unconvertedARWs], [0, 0, 1, 1])
        XCTAssertEqual(try Data(contentsOf: arw), try Data(contentsOf: IntegrationTests.fixtures
            .appendingPathComponent("sample.ARW")), "the ARW must not change")
    }

    // A run that ended hard left a cut-off work file. The real dnglab would
    // refuse to write over it. It goes to the injected trash first, and the
    // conversion then passes.
    func testARealConversionDiscardsTheLeftoverWorkFileOfAnEarlierRun() throws {
        let arw = try copyFixture(as: "frame 1.ARW")
        let work = folder.appendingPathComponent(".frame 1.desqueeze-work.dng")
        try Data("II*\u{0}".utf8).write(to: work)
        let (trash, backups) = try makeTrash()

        // The leftover is invisible to the scan: the ARW is pending, and
        // the folder has no DNG.
        let scan = try FolderScanner(tag: ScaleTag(exiftool: exiftool), backups: backups).snapshot(of: folder)
        XCTAssertEqual(scan.dngs, [])
        XCTAssertEqual(scan.pendingARWs.map(\.lastPathComponent), ["frame 1.ARW"])

        let conversion = try DnglabConverter(executable: dnglab, exiftool: exiftool,
                                             discardLeftover: { try backups.trashFile($0) })
            .convert(arw, facts: try facts(of: arw))

        XCTAssertEqual(conversion, Conversion(dng: folder.appendingPathComponent("frame 1.dng"), unmatched: nil))
        XCTAssertEqual(try names(), ["frame 1.ARW", "frame 1.dng"])
        XCTAssertEqual(try Data(contentsOf: trash.appendingPathComponent(".frame 1.desqueeze-work.dng")),
                       Data("II*\u{0}".utf8), "the leftover is in the injected trash")
        XCTAssertEqual(try read(["SubIFD:WhiteLevel", "IFD0:OriginalRawFileName"], in: conversion.dng),
                       ["16383", "frame 1.ARW"])
    }

    // A hard end during the match write left `<work file>_exiftool_tmp`.
    // With that file there, the real exiftool refuses to write the work
    // file, so before step 1 took it the ARW failed on every run. Now it
    // goes to the injected trash with the work file, and the real dnglab and
    // the real exiftool then convert and match.
    func testARealConversionDiscardsTheLeftoverOfExiftoolBesideTheWorkFile() throws {
        let arw = try copyFixture(as: "frame 1.ARW")
        let work = folder.appendingPathComponent(".frame 1.desqueeze-work.dng")
        let leftover = folder.appendingPathComponent(".frame 1.desqueeze-work.dng_exiftool_tmp")
        try Data("II*\u{0}".utf8).write(to: work)
        try Data("half a write".utf8).write(to: leftover)
        let (trash, backups) = try makeTrash()

        let conversion = try DnglabConverter(executable: dnglab, exiftool: exiftool,
                                             discardLeftover: { try backups.trashFile($0) })
            .convert(arw, facts: try facts(of: arw))

        XCTAssertEqual(conversion, Conversion(dng: folder.appendingPathComponent("frame 1.dng"), unmatched: nil))
        XCTAssertEqual(try names(), ["frame 1.ARW", "frame 1.dng"], "no hidden file stays")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path).sorted(),
                       [".frame 1.desqueeze-work.dng", ".frame 1.desqueeze-work.dng_exiftool_tmp"])
        XCTAssertEqual(try Data(contentsOf: trash.appendingPathComponent(leftover.lastPathComponent)),
                       Data("half a write".utf8))
        XCTAssertEqual(try read(["SubIFD:WhiteLevel", "IFD0:OriginalRawFileName"], in: conversion.dng),
                       ["16383", "frame 1.ARW"], "the match was written: exiftool did not refuse")
    }

    // The real dnglab returns 6 for an output that exists, and does not
    // touch it. Here the discard says yes and leaves the file. The file is
    // not reported as partial, so nothing sends it anywhere.
    func testTheRealDnglabReturnsSixForAWorkFileThatIsStillThereAndReportsNoPartial() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let work = folder.appendingPathComponent(".frame.desqueeze-work.dng")
        try Data("not this run's".utf8).write(to: work)
        let converter = DnglabConverter(executable: dnglab, exiftool: exiftool, discardLeftover: { _ in })
        XCTAssertThrowsError(try converter.convert(arw, facts: try facts(of: arw))) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("dnglab returned 6. Already exists: \(work.path).", partial: nil))
        }
        XCTAssertEqual(try Data(contentsOf: work), Data("not this run's".utf8))
        XCTAssertEqual(try names(), [".frame.desqueeze-work.dng", "frame.ARW"])
    }

    // A tab in the name of the ARW, with the real tools. exiftool prints the
    // tab as a period: in the row of the facts read, and in the read-back
    // of `OriginalRawFileName`. The ARW still gets its facts and its match.
    // The file is made here, in the temporary folder.
    func testARealConversionOfAnARWWithATabInItsNamePassesItsMatch() throws {
        let arw = try copyFixture(as: "tab\there.ARW")
        let reader = ARWFactsReader(exiftool: exiftool)
        let facts = try XCTUnwrap(reader.read([arw])["tab\there.ARW"], "the facts come back under the real name")
        XCTAssertTrue(AdobeMatch.match(facts).isFull)

        let conversion = try converter.convert(arw, facts: facts)

        XCTAssertEqual(conversion, Conversion(dng: folder.appendingPathComponent("tab\there.dng"), unmatched: nil))
        XCTAssertEqual(try names(), ["tab\there.ARW", "tab\there.dng"])
        // What the real exiftool prints for the tag, and what the file holds.
        XCTAssertEqual(try read(["SubIFD:WhiteLevel", "IFD0:OriginalRawFileName"], in: conversion.dng),
                       ["16383", "tab.here.ARW"])
        let raw = try SystemProcessRunner().run(exiftool, ["-b", "-IFD0:OriginalRawFileName", conversion.dng.path])
        XCTAssertEqual(raw.stdout, "tab\there.ARW", "the tag holds the real name")

        // A second file that prints as the same name: neither has facts.
        let twin = try copyFixture(as: "tab.here.ARW")
        XCTAssertEqual(reader.read([arw, twin]), [:])
    }

    // Why the rule is there: the real exiftool refuses to write a file that
    // has its own leftover beside it. So the app does not start a conversion
    // whose tag step could never pass.
    func testTheRealExiftoolRefusesToWriteBesideItsOwnLeftoverSoTheARWIsNotConverted() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let leftover = folder.appendingPathComponent("frame.dng_exiftool_tmp")
        try Data("half a write".utf8).write(to: leftover)

        XCTAssertThrowsError(try converter.convert(arw, facts: try facts(of: arw))) {
            XCTAssertEqual($0 as? ConvertError, .failedForAll(
                "A leftover file, frame.dng_exiftool_tmp, is beside this photo. Delete it, then run again."))
        }
        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng_exiftool_tmp"], "no DNG and no work file was made")

        // The fact behind the rule, on a DNG that is put there by hand.
        let dng = folder.appendingPathComponent("frame.dng")
        try FileManager.default.copyItem(at: IntegrationTests.fixtures.appendingPathComponent("sample.dng"), to: dng)
        let before = try Data(contentsOf: dng)
        XCTAssertThrowsError(try ScaleTag(exiftool: exiftool).write(SqueezeFactor(1.5)!, to: dng)) {
            guard case TagError.toolFailed(let words) = $0 else { return XCTFail("\($0)") }
            XCTAssertTrue(words.contains("Temporary file already exists"), words)
        }
        XCTAssertEqual(try Data(contentsOf: dng), before)
        XCTAssertEqual(try Data(contentsOf: leftover), Data("half a write".utf8))
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
///
/// Both paths are the ones of design 13.3: the converter writes the hidden
/// work file, dnglab's match goes into it, and the rename gives it the name
/// `<base>.dng`. So the check also fails when a new dnglab, a new exiftool
/// or a new Adobe DNG Converter does not take the work file's name (for
/// Adobe: its `-o` option), or when the rename does not leave the DNG at
/// its name with no work file beside it.
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

        let adobes = try AdobeConverter(
            executable: adobe, discardLeftover: { XCTFail("no leftover was expected: \($0.lastPathComponent)") }
        ).convert(forAdobe).dng
        let facts = try facts(of: forDnglab)
        let ours = try converter.convert(forDnglab, facts: facts)
        XCTAssertNil(ours.unmatched, "the fixture is a full match: \(facts)")
        // The work-file path: the DNG is at its name, it is the file that
        // the tags are read from below, and no work file is left. The
        // listing has hidden files too.
        XCTAssertEqual(ours.dng, dnglabFolder.appendingPathComponent("frame.dng"))
        XCTAssertEqual(try files.contentsOfDirectory(atPath: dnglabFolder.path).sorted(), ["frame.ARW", "frame.dng"],
                       "the dnglab DNG is at <base>.dng, with no work file left")
        // The same for Adobe DNG Converter: its DNG is at `<base>.dng`, and
        // no hidden file is left. Without `-o` honoured, the work file would
        // not be there, and the conversion would have failed above.
        XCTAssertEqual(adobes, adobeFolder.appendingPathComponent("frame.dng"))
        XCTAssertEqual(try files.contentsOfDirectory(atPath: adobeFolder.path).sorted(), ["frame.ARW", "frame.dng"],
                       "Adobe's DNG is at <base>.dng, with no work file and no second DNG left")
        XCTAssertEqual(Self.matchedTags.count, 9, "all nine tags of the match are compared")

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

/// A real run with dnglab first. The fixture is a full match, so Adobe DNG
/// Converter is never started here, also when it is installed.
final class DnglabRunIntegrationTests: RealDnglabTestCase {
    // Tests discard backups for good. The real Trash is checked by hand.
    var backups: FileBackups { FileBackups(trash: { try FileManager.default.removeItem(at: $0) }) }
    var tag: ScaleTag { ScaleTag(exiftool: exiftool) }

    /// - Parameter withAdobe: gives the job Adobe DNG Converter when this Mac
    ///   has it. With no Adobe on this Mac, the job has dnglab alone.
    func job(withAdobe: Bool) -> DesqueezeJob {
        DesqueezeJob(tag: tag, converters: RawConverters(
            exiftool: exiftool, dnglab: dnglab, adobe: withAdobe ? ToolLocator().dngConverter() : nil,
            backups: backups),
            backups: backups)
    }

    func testARealPlanAndRunWithDnglabFirstConvertMatchTagAndClearTheBackups() throws {
        let sampleDNG = IntegrationTests.fixtures.appendingPathComponent("sample.dng")
        guard FileManager.default.fileExists(atPath: sampleDNG.path) else {
            throw XCTSkip("No fixtures. Run scripts/make_fixtures.sh with one ARW file.")
        }
        try FileManager.default.copyItem(at: sampleDNG, to: folder.appendingPathComponent("already here.dng"))
        let arw = try copyFixture(as: "frame.ARW")
        let arwBefore = try Data(contentsOf: arw)
        let factor = SqueezeFactor(1.5)!
        let job = job(withAdobe: true)

        let plan = try job.plan(folder: folder, factor: factor, convert: true)
        XCTAssertEqual(try names(), ["already here.dng", "frame.ARW"], "a plan makes no file")
        XCTAssertEqual(plan.steps, [
            RunPlan.Step(name: "frame.ARW", action: .convert, converter: .dnglab),
            RunPlan.Step(name: "already here.dng", action: .write),
            RunPlan.Step(name: "frame.dng", action: .write),
        ])

        let summary = try job.run(folder: folder, factor: factor, convert: true)
        XCTAssertEqual(summary, plan.summary, "the run gives the counts and the notes of the plan")
        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.convertedByAdobe], [1, 1, 0])
        XCTAssertEqual([summary.set, summary.failed], [2, 0])
        XCTAssertEqual(summary.notes, [])
        XCTAssertEqual(try names(), ["already here.dng", "frame.ARW", "frame.dng"],
                       "no backup stays, and no second DNG")
        XCTAssertEqual(try Data(contentsOf: arw), arwBefore, "the ARW must not change")

        // The match is in the DNG, and the stretch too: the tag step ran on
        // the file that the match wrote.
        let dng = folder.appendingPathComponent("frame.dng")
        XCTAssertEqual(try read(["SubIFD:WhiteLevel", "IFD0:BaselineExposure", "IFD0:OriginalRawFileName"], in: dng),
                       ["16383", "0.15", "frame.ARW"])
        XCTAssertEqual(try tag.read(dng), Scale(horizontal: 1.5, vertical: 1))
        let validate = try SystemProcessRunner().run(exiftool, ["-validate", "-s3", dng.path])
        XCTAssertEqual(validate.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "OK", validate.stderr)

        // A second run finds the ARW claimed, and both files at the value.
        let rerun = try job.run(folder: folder, factor: factor, convert: true)
        XCTAssertEqual([rerun.converted, rerun.set, rerun.skipped, rerun.unconvertedARWs], [0, 0, 2, 0])

        let removed = try job.run(folder: folder, factor: .noStretch, convert: false, remove: true)
        XCTAssertEqual([removed.set, removed.failed], [2, 0])
        XCTAssertEqual(try tag.read(dng), .noStretch)
        XCTAssertEqual(try read(["SubIFD:WhiteLevel"], in: dng), ["16383"], "Remove keeps the match")
    }

    // dnglab alone, and a file that is no photo: failed, with dnglab's words.
    // dnglab made no DNG, so the folder holds what it held.
    func testARealRunWithDnglabAloneReportsAFileThatDnglabCannotRead() throws {
        _ = try copyFixture(as: "frame.ARW")
        try Data("not a photo".utf8).write(to: folder.appendingPathComponent("junk.ARW"))

        let summary = try job(withAdobe: false).run(folder: folder, factor: .noStretch, convert: true)

        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.failed, summary.unconvertedARWs],
                       [1, 1, 1, 1])
        XCTAssertEqual(summary.notes, [FileNote(
            name: "junk.ARW", kind: .notConverted, message: "Not converted.",
            detail: "dnglab returned 7. Unsupported file: Error: No decoder found, model '', make: '', mode: ''.")])
        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng", "junk.ARW"])
    }
}
