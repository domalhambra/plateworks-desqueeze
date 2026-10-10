import XCTest
@testable import DesqueezeCore

/// The real dnglab and the real exiftool, on copies of `fixtures/sample.ARW`
/// in a temporary folder. Skips when a tool or the fixture is absent.
///
/// The fixture can be any Sony ARW. No test here holds a number of one
/// frame: each value that a test expects comes from the frame itself, from
/// its facts and from what `AdobeMatch` gives for them. A test of the match
/// needs a frame that the match table covers (design 13.4). With another
/// frame it skips, and says so (`factsOfACoveredFrame`).
class RealDnglabTestCase: XCTestCase {
    /// What a test of the match says when the frame in `fixtures/` is one
    /// that the match table does not cover.
    static let needsACoveredFrame = "This test needs a frame that the match table covers: "
        + "a Sony A7S III, compressed raw, ISO 50 or 80 to 12800, adapted lens."

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

    /// The facts of `arw`, for a test of the match. Skips the test when the
    /// match table does not cover the frame: the photo in `fixtures/` is the
    /// reader's own, and it can be any Sony ARW.
    ///
    /// Whether the table covers the frame is decided with no code of the
    /// product. The five values come from exiftool, each tag read alone
    /// (`value(of:in:)`), and the five rules of design 13.4 are spelled
    /// here, against the data file. `ARWFactsReader` and `AdobeMatch` are
    /// not asked. So a reader or a rule that breaks fails an assertion
    /// below for a frame that the table covers. It does not turn the test
    /// into a skip, and the drift check cannot pass by not running.
    ///
    /// A new camera needs its own data file here: this helper reads the one
    /// of the A7S III, and it skips for every other model.
    ///
    /// - Returns: the facts as exiftool gave them. A test goes on with the
    ///   true facts, also when the product's reader gave others.
    func factsOfACoveredFrame(_ arw: URL, file: StaticString = #filePath, line: UInt = #line) throws -> ARWFacts {
        let model = try value(of: "IFD0:Model", in: arw)
        let iso = try value(of: "ExifIFD:ISO", in: arw)
        let levels = (try value(of: "SR2SubIFD:WB_RGBLevelsDaylight", in: arw) ?? "")
            .split(separator: " ").map { Int($0) }
        let lens = try value(of: "SubIFD:DistortionCorrection", in: arw)
        let raw = try value(of: "SubIFD:SonyRawFileType", in: arw)
        let table = try JSONDecoder().decode(AdobeMatchTests.DataFile.self,
                                             from: Data(contentsOf: AdobeMatchTests.dataFile))
        guard model == table.model,
              let iso, table.byISO[iso] != nil, let isoNumber = Int(iso),
              levels.count == 3, let red = levels[0], let green = levels[1], let blue = levels[2],
              green == table.daylightReference.green, red > 0, blue > 0,
              lens == "255", raw == "2"
        else { throw XCTSkip(Self.needsACoveredFrame, file: file, line: line) }

        let truth = ARWFacts(model: model, iso: isoNumber,
                             daylightLevels: ARWFacts.DaylightLevels(red: red, green: green, blue: blue),
                             distortionCorrection: 255, rawFileType: 2)
        XCTAssertEqual(ARWFactsReader(exiftool: exiftool).read([arw])[arw.lastPathComponent], truth,
                       "the product's reader must give what exiftool prints for each tag alone", file: file,
                       line: line)
        XCTAssertTrue(AdobeMatch.match(truth).isFull, "the table covers this frame, so it is a full match: \(truth)",
                      file: file, line: line)
        return truth
    }

    /// The value that the match writes into `tag` for an ARW with these
    /// facts: Adobe's value for this frame, as the table gives it.
    func matchValue(_ tag: String, for facts: ARWFacts, file: StaticString = #filePath,
                    line: UInt = #line) throws -> String {
        try XCTUnwrap(AdobeMatch.match(facts).tags.first { $0.name == tag }?.value, "the match has no \(tag)",
                      file: file, line: line)
    }

    /// Reads `tags` from `dng` and holds each one to the value of the match
    /// for these facts. Numbers are compared as numbers.
    func assertTheMatch(of tags: [String], isIn dng: URL, for facts: ARWFacts, file: StaticString = #filePath,
                        line: UInt = #line) throws {
        for (tag, value) in zip(tags, try read(tags, in: dng)) {
            let wanted = try matchValue(tag, for: facts, file: file, line: line)
            XCTAssertTrue(AdobeMatch.sameNumbers(wanted, value), "\(tag): \(value), not \(wanted)", file: file,
                          line: line)
        }
    }

    /// What `file` holds for one tag, read alone. Nil for "no such tag".
    func value(of tag: String, in file: URL) throws -> String? {
        let value = try read([tag], in: file)[0]
        return value == "-" ? nil : value
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
    // The facts of the fixture, whatever frame it is. The reader makes one
    // read for all five. Here exiftool is asked for each tag alone, and the
    // reader must give the same: a reader that asks for a wrong tag, or
    // takes a column for another, fails.
    func testARealReadGivesWhatExiftoolPrintsForEachTagAlone() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let facts = try facts(of: arw)
        XCTAssertNotNil(facts.model, "exiftool reads the fixture: \(facts)")
        XCTAssertEqual(facts.model, try value(of: "IFD0:Model", in: arw))
        XCTAssertEqual(facts.iso.map(String.init), try value(of: "ExifIFD:ISO", in: arw))
        XCTAssertEqual(facts.daylightLevels.map { "\($0.red) \($0.green) \($0.blue)" },
                       try value(of: "SR2SubIFD:WB_RGBLevelsDaylight", in: arw))
        XCTAssertEqual(facts.distortionCorrection.map(String.init),
                       try value(of: "SubIFD:DistortionCorrection", in: arw))
        XCTAssertEqual(facts.rawFileType.map(String.init), try value(of: "SubIFD:SonyRawFileType", in: arw))
    }

    // One read for a list: a photo, and a file that exiftool cannot read.
    // The photo gets the facts that a read of it alone gives.
    func testARealReadGivesFactsForAPhotoAndNoneForAFileThatIsNoPhoto() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let junk = folder.appendingPathComponent("junk.ARW")
        try Data("not a photo".utf8).write(to: junk)
        let before = try Data(contentsOf: arw)
        let alone = try facts(of: arw)
        XCTAssertNotNil(alone.model, "exiftool reads the fixture: \(alone)")

        let read = ARWFactsReader(exiftool: exiftool).read([arw, junk])

        XCTAssertEqual(read["frame.ARW"], alone)
        XCTAssertEqual(read["junk.ARW"], ARWFacts.none)
        XCTAssertEqual(try names(), ["frame.ARW", "junk.ARW"], "the read makes no file")
        XCTAssertEqual(try Data(contentsOf: arw), before, "the read changes no file")
    }

    func testARealConversionWritesTheMatchAndTheDNGIsValid() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let facts = try factsOfACoveredFrame(arw)
        let arwBefore = try Data(contentsOf: arw)

        let conversion = try converter.convert(arw, facts: facts)

        let dng = folder.appendingPathComponent("frame.dng")
        XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: nil))
        // `names()` lists hidden files too: the folder holds the ARW and the
        // DNG, and nothing else.
        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng"], "no backup and no work file stays")
        XCTAssertFalse(ConverterOutput.exists(atPath: ConverterOutput.workURL(for: arw).path))
        XCTAssertEqual(try Data(contentsOf: arw), arwBefore, "the ARW must not change")

        // All nine tags, read back from the file: Adobe's values for this
        // frame, as the table gives them for its facts.
        XCTAssertEqual(Self.matchedTags.count, 9)
        try assertTheMatch(of: Self.matchedTags, isIn: dng, for: facts)
        XCTAssertEqual(try read(["IFD0:OriginalRawFileName"], in: dng), ["frame.ARW"],
                       "the pending rule needs the file name")

        // dnglab embeds the whole ARW by default. `--embed-raw false` stops
        // that. The tag is the proof. The size of the DNG is none: it
        // depends on the photo, and a DNG with no ARW inside can be larger
        // than its ARW.
        XCTAssertEqual(try read(["IFD0:OriginalRawFileData"], in: dng), ["-"], "no embedded raw")

        let validate = try SystemProcessRunner().run(exiftool, ["-validate", "-s3", dng.path])
        XCTAssertEqual(validate.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "OK", validate.stderr)

        // The DNG claims its ARW by the tag, also under another name.
        let renamed = folder.appendingPathComponent("Renamed on import 0022.dng")
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
        // What dnglab alone writes for this frame, with no step of the app:
        // the same command, into a folder beside the photo folder.
        let plain = folder.deletingLastPathComponent().appendingPathComponent("dnglab alone.dng")
        let alone = try SystemProcessRunner().run(dnglab, ["convert", "--embed-raw", "false", arw.path, plain.path])
        XCTAssertEqual(alone.exitCode, 0, alone.stderr)
        let own = try read(Self.matchedTags, in: plain)
        XCTAssertNotEqual(own[0], "-", "dnglab writes a white level of its own")

        let values = try read(Self.matchedTags + ["IFD0:OriginalRawFileName"], in: dng)
        XCTAssertEqual(Array(values[0..<9]), own, "each tag of the match is as dnglab alone leaves it")
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
        // A full match: dnglab gets the ARW first, and Adobe is the next.
        let facts = try factsOfACoveredFrame(arw)
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

        let summary = try job.run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true, trashOriginals: false)

        XCTAssertEqual(try Data(contentsOf: dng), others, "the DNG of the other program has the same bytes")
        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng"], "no work file stays, hidden files counted")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), [".frame.desqueeze-work.dng"],
                       "only the work file is in the injected trash")
        // The work file was complete: dnglab's DNG, with the match in it.
        let work = trash.appendingPathComponent(".frame.desqueeze-work.dng")
        try assertTheMatch(of: ["SubIFD:WhiteLevel"], isIn: work, for: facts)
        XCTAssertEqual(try read(["IFD0:OriginalRawFileName"], in: work), ["frame.ARW"])
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
        let facts = try factsOfACoveredFrame(arw)
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
            .convert(arw, facts: facts)

        XCTAssertEqual(conversion, Conversion(dng: folder.appendingPathComponent("frame 1.dng"), unmatched: nil))
        XCTAssertEqual(try names(), ["frame 1.ARW", "frame 1.dng"])
        XCTAssertEqual(try Data(contentsOf: trash.appendingPathComponent(".frame 1.desqueeze-work.dng")),
                       Data("II*\u{0}".utf8), "the leftover is in the injected trash")
        try assertTheMatch(of: ["SubIFD:WhiteLevel"], isIn: conversion.dng, for: facts)
        XCTAssertEqual(try read(["IFD0:OriginalRawFileName"], in: conversion.dng), ["frame 1.ARW"])
    }

    // A hard end during the match write left `<work file>_exiftool_tmp`.
    // With that file there, the real exiftool refuses to write the work
    // file, so before step 1 took it the ARW failed on every run. Now it
    // goes to the injected trash with the work file, and the real dnglab and
    // the real exiftool then convert and match.
    func testARealConversionDiscardsTheLeftoverOfExiftoolBesideTheWorkFile() throws {
        let arw = try copyFixture(as: "frame 1.ARW")
        let facts = try factsOfACoveredFrame(arw)
        let work = folder.appendingPathComponent(".frame 1.desqueeze-work.dng")
        let leftover = folder.appendingPathComponent(".frame 1.desqueeze-work.dng_exiftool_tmp")
        try Data("II*\u{0}".utf8).write(to: work)
        try Data("half a write".utf8).write(to: leftover)
        let (trash, backups) = try makeTrash()

        let conversion = try DnglabConverter(executable: dnglab, exiftool: exiftool,
                                             discardLeftover: { try backups.trashFile($0) })
            .convert(arw, facts: facts)

        XCTAssertEqual(conversion, Conversion(dng: folder.appendingPathComponent("frame 1.dng"), unmatched: nil))
        XCTAssertEqual(try names(), ["frame 1.ARW", "frame 1.dng"], "no hidden file stays")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path).sorted(),
                       [".frame 1.desqueeze-work.dng", ".frame 1.desqueeze-work.dng_exiftool_tmp"])
        XCTAssertEqual(try Data(contentsOf: trash.appendingPathComponent(leftover.lastPathComponent)),
                       Data("half a write".utf8))
        // The match was written: exiftool did not refuse.
        try assertTheMatch(of: ["SubIFD:WhiteLevel"], isIn: conversion.dng, for: facts)
        XCTAssertEqual(try read(["IFD0:OriginalRawFileName"], in: conversion.dng), ["frame 1.ARW"])
    }

    // The real dnglab returns 6 for an output that exists, and does not
    // touch it. Here the discard says yes and leaves the file. The file is
    // not reported as partial, so nothing sends it anywhere. The real dnglab
    // prints the whole path of the file, and the sentence has its name.
    func testTheRealDnglabReturnsSixForAWorkFileThatIsStillThereAndReportsNoPartial() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let work = folder.appendingPathComponent(".frame.desqueeze-work.dng")
        try Data("not this run's".utf8).write(to: work)
        let converter = DnglabConverter(executable: dnglab, exiftool: exiftool, discardLeftover: { _ in })
        XCTAssertThrowsError(try converter.convert(arw, facts: try facts(of: arw))) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("dnglab returned 6. Already exists: .frame.desqueeze-work.dng.", partial: nil))
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
        XCTAssertNotNil(reader.read([arw])["tab\there.ARW"], "the facts come back under the real name")
        let facts = try factsOfACoveredFrame(arw)

        let conversion = try converter.convert(arw, facts: facts)

        XCTAssertEqual(conversion, Conversion(dng: folder.appendingPathComponent("tab\there.dng"), unmatched: nil))
        XCTAssertEqual(try names(), ["tab\there.ARW", "tab\there.dng"])
        // What the real exiftool prints for the tag, and what the file holds.
        try assertTheMatch(of: ["SubIFD:WhiteLevel"], isIn: conversion.dng, for: facts)
        XCTAssertEqual(try read(["IFD0:OriginalRawFileName"], in: conversion.dng), ["tab.here.ARW"])
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

        // The fact behind the rule, on a DNG that is put there by hand. It
        // needs the fixture DNG. With the ARW alone in `fixtures/`, the
        // test skips here, as every test does that lacks a fixture: it
        // does not fail.
        let sample = IntegrationTests.fixtures.appendingPathComponent("sample.dng")
        guard FileManager.default.fileExists(atPath: sample.path) else {
            throw XCTSkip("No fixture DNG. Run scripts/make_fixtures.sh with one ARW file.")
        }
        let dng = folder.appendingPathComponent("frame.dng")
        try FileManager.default.copyItem(at: sample, to: dng)
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
/// there, and when the frame in `fixtures/` is one that the match table does
/// not cover: such a frame has no match to compare. It starts Adobe DNG
/// Converter once, and not at all when it skips.
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
        // Before the first converter starts: with a frame that the table
        // does not cover, the test skips here.
        let facts = try factsOfACoveredFrame(forDnglab)

        let adobes = try AdobeConverter(
            executable: adobe, discardLeftover: { XCTFail("no leftover was expected: \($0.lastPathComponent)") }
        ).convert(forAdobe).dng
        let ours = try converter.convert(forDnglab, facts: facts)
        XCTAssertNil(ours.unmatched, "the frame is a full match: \(facts)")
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

/// A real run with dnglab first. A frame that the match table covers goes to
/// dnglab, so Adobe DNG Converter is never started here, also when it is
/// installed.
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
        // A full match: with both converters, dnglab gets the ARW.
        let facts = try factsOfACoveredFrame(arw)
        let arwBefore = try Data(contentsOf: arw)
        let factor = SqueezeFactor(1.5)!
        let job = job(withAdobe: true)

        let plan = try job.plan(folder: folder, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(try names(), ["already here.dng", "frame.ARW"], "a plan makes no file")
        XCTAssertEqual(plan.steps, [
            RunPlan.Step(name: "frame.ARW", action: .convert, converter: .dnglab),
            RunPlan.Step(name: "already here.dng", action: .write),
            RunPlan.Step(name: "frame.dng", action: .write),
        ])

        let summary = try job.run(folder: folder, factor: factor, convert: true, trashOriginals: false)
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
        try assertTheMatch(of: ["SubIFD:WhiteLevel", "IFD0:BaselineExposure"], isIn: dng, for: facts)
        XCTAssertEqual(try read(["IFD0:OriginalRawFileName"], in: dng), ["frame.ARW"])
        XCTAssertEqual(try tag.read(dng), Scale(horizontal: 1.5, vertical: 1))
        let validate = try SystemProcessRunner().run(exiftool, ["-validate", "-s3", dng.path])
        XCTAssertEqual(validate.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "OK", validate.stderr)

        // A second run finds the ARW claimed, and both files at the value.
        let rerun = try job.run(folder: folder, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual([rerun.converted, rerun.set, rerun.skipped, rerun.unconvertedARWs], [0, 0, 2, 0])

        let removed = try job.run(folder: folder,
                                  factor: .noStretch, convert: false, trashOriginals: false, remove: true)
        XCTAssertEqual([removed.set, removed.failed], [2, 0])
        XCTAssertEqual(try tag.read(dng), .noStretch)
        try assertTheMatch(of: ["SubIFD:WhiteLevel"], isIn: dng, for: facts) // Remove keeps the match.
    }

    /// Starts each program for real, and keeps the name of each one.
    final class RecordingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []

        var programs: [String] {
            lock.lock()
            defer { lock.unlock() }
            return names
        }

        func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
            lock.lock()
            names.append(executable.lastPathComponent)
            lock.unlock()
            return try SystemProcessRunner().run(executable, arguments)
        }
    }

    // A real photo under a name of 223 letters (design 13.9): the first
    // length that is too long. exiftool's temporary file beside the work
    // file would have 256 units, and a file name can have 255. Before the
    // rule of 2026-10-10, dnglab converted this photo, and exiftool then
    // failed in the match with the system's words. Now no converter
    // starts: only exiftool runs, for the scan and for the facts.
    func testARealRunStartsNoConverterForAnARWWithANameThatIsTooLong() throws {
        let longName = String(repeating: "n", count: 223) + ".ARW"
        let arw = try copyFixture(as: longName)
        let arwBefore = try Data(contentsOf: arw)
        let runner = RecordingRunner()
        let job = DesqueezeJob(
            tag: ScaleTag(exiftool: exiftool, runner: runner),
            converters: RawConverters(exiftool: exiftool, dnglab: dnglab, adobe: ToolLocator().dngConverter(),
                                      runner: runner, backups: backups),
            backups: backups)

        let summary = try job.run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true, trashOriginals: false)

        XCTAssertEqual(summary.notes, [FileNote(
            name: longName, kind: .notConverted, message: "Not converted.",
            detail: "The file name is too long. Shorten it, then run again.")])
        XCTAssertEqual([summary.converted, summary.set, summary.failed, summary.unconvertedARWs], [0, 0, 1, 1])
        XCTAssertEqual(Set(runner.programs), ["exiftool"], "no converter starts: \(runner.programs)")
        XCTAssertEqual(try names(), [longName], "the folder holds what it held")
        XCTAssertEqual(try Data(contentsOf: arw), arwBefore, "the ARW must not change")
    }

    // The longest name that converts, with the real dnglab and the real
    // exiftool: a base of 222 letters. The work file has 242 units, and
    // exiftool's temporary file beside it has 255, the most that a file
    // name can have. The photo converts, gets the name of its ARW and the
    // stretch, and nothing is left beside the two files. dnglab alone: no
    // Adobe DNG Converter starts here.
    func testARealPhotoWithTheLongestNameConvertsAndIsTaggedAndLeavesNoFile() throws {
        let base = String(repeating: "n", count: 222)
        let arw = try copyFixture(as: base + ".ARW")
        let arwBefore = try Data(contentsOf: arw)
        XCTAssertEqual(ConverterOutput.exiftoolLeftoverURL(for: ConverterOutput.workURL(for: arw))
            .lastPathComponent.utf16.count, 255)
        let runner = RecordingRunner()
        let tag = ScaleTag(exiftool: exiftool, runner: runner)
        let job = DesqueezeJob(
            tag: tag,
            converters: RawConverters(exiftool: exiftool, dnglab: dnglab, adobe: nil, runner: runner,
                                      backups: backups),
            backups: backups)

        let summary = try job.run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true, trashOriginals: false)

        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.set, summary.failed,
                        summary.unconvertedARWs], [1, 1, 1, 0, 0], "\(summary.notes)")
        XCTAssertEqual(summary.notes.filter { $0.kind != .convertedUnmatched }, [],
                       "only a frame that the table does not cover has a note")
        XCTAssertTrue(runner.programs.contains("dnglab"), "\(runner.programs)")
        let dng = folder.appendingPathComponent(base + ".dng")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       [base + ".ARW", base + ".dng"], "no work file, no temporary file and no backup is left")
        XCTAssertEqual(try read(["IFD0:OriginalRawFileName"], in: dng), [base + ".ARW"])
        XCTAssertEqual(try tag.read(dng), Scale(horizontal: 1.5, vertical: 1))
        XCTAssertEqual(try Data(contentsOf: arw), arwBefore, "the ARW must not change")
    }

    // MARK: The originals, on request (design 14)

    /// A folder that stands for the Trash, beside the photo folder, and
    /// backups that move each discarded file into it. Nothing is removed.
    func makeTrash() throws -> (folder: URL, backups: FileBackups) {
        let trash = folder.deletingLastPathComponent().appendingPathComponent("Test trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return (trash, try FileBackups.fromEnvironment([FileBackups.testFolderVariable: trash.path]).backups)
    }

    /// dnglab alone, so Adobe DNG Converter is never started here.
    func job(movingTo backups: FileBackups) -> DesqueezeJob {
        DesqueezeJob(tag: tag,
                     converters: RawConverters(exiftool: exiftool, dnglab: dnglab, adobe: nil, backups: backups),
                     backups: backups)
    }

    // The real tools, and the real disk for lines 4 and 5: after a run with
    // the option on, the folder holds the DNG and no ARW of it, and the file
    // in the injected trash has the bytes of the source ARW.
    func testARealRunWithTheOptionOnLeavesTheDNGAndMovesItsARWToTheInjectedTrash() throws {
        let source = IntegrationTests.fixtures.appendingPathComponent("sample.ARW")
        let sampleDNG = IntegrationTests.fixtures.appendingPathComponent("sample.dng")
        guard FileManager.default.fileExists(atPath: sampleDNG.path) else {
            throw XCTSkip("No fixtures. Run scripts/make_fixtures.sh with one ARW file.")
        }
        let arw = try copyFixture(as: "frame.ARW")
        // A full match, so the DNG that dnglab makes is complete (line 2).
        _ = try factsOfACoveredFrame(arw)
        // A file that is not the app's: it stays.
        try Data("sidecar".utf8).write(to: folder.appendingPathComponent("frame.xmp"))
        // An ARW that an earlier run converted: its DNG claims it, so this
        // run does not convert it, and it stays (design 14.1).
        try FileManager.default.copyItem(at: sampleDNG, to: folder.appendingPathComponent("earlier.dng"))
        try Data("an ARW of an earlier run".utf8).write(to: folder.appendingPathComponent("earlier.ARW"))
        // An ARW whose conversion fails: it stays.
        try Data("not a photo".utf8).write(to: folder.appendingPathComponent("junk.ARW"))
        let (trash, backups) = try makeTrash()
        let factor = SqueezeFactor(1.5)!

        let plan = try job(movingTo: backups).plan(folder: folder, factor: factor, convert: true,
                                                   trashOriginals: true)
        // The junk file has no facts, so the plan gives it a conversion
        // with no full match, and no step for its original.
        XCTAssertEqual(plan.steps.filter { $0.action == .trashOriginal }.map(\.name), ["frame.ARW"])
        XCTAssertEqual(plan.summary.notes.map(\.kind), [.convertedUnmatched, .originalKept])
        XCTAssertEqual(try names(), ["earlier.ARW", "earlier.dng", "frame.ARW", "frame.xmp", "junk.ARW"],
                       "a plan moves nothing")

        let summary = try job(movingTo: backups).run(folder: folder, factor: factor, convert: true,
                                                     trashOriginals: true)

        // `contentsOfDirectory(atPath:)` lists hidden files too.
        XCTAssertEqual(try names(), ["earlier.ARW", "earlier.dng", "frame.dng", "frame.xmp", "junk.ARW"],
                       "the DNG, and no ARW of it. Every other file is where it was")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path).sorted(),
                       ["earlier.dng_original", "frame.ARW", "frame.dng_original"])
        XCTAssertEqual(try Data(contentsOf: trash.appendingPathComponent("frame.ARW")), try Data(contentsOf: source),
                       "the file in the trash has the bytes of the source ARW")
        XCTAssertTrue(summary.trashOriginals)
        XCTAssertEqual(summary.originalsInTrash, 1)
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 1 of 1.")
        XCTAssertEqual([summary.converted, summary.set, summary.failed], [1, 2, 1])
        XCTAssertEqual(summary.notes.map(\.kind), [.notConverted], "an ARW that failed gets no second note")
        XCTAssertEqual(try tag.read(folder.appendingPathComponent("frame.dng")), Scale(horizontal: 1.5, vertical: 1))
        XCTAssertEqual(try read(["IFD0:OriginalRawFileName"], in: folder.appendingPathComponent("frame.dng")),
                       ["frame.ARW"])
    }

    // The same run with the option off: the ARW is where it was, with its
    // bytes, and only the backups went to the injected trash.
    func testARealRunWithTheOptionOffLeavesTheARW() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let before = try Data(contentsOf: arw)
        let (trash, backups) = try makeTrash()

        let summary = try job(movingTo: backups).run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true,
                                                     trashOriginals: false)

        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng"])
        XCTAssertEqual(try Data(contentsOf: arw), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), ["frame.dng_original"])
        XCTAssertEqual(summary.originalsInTrash, 0)
        XCTAssertNil(summary.originalsLine)
    }

    // The real disk for line 4: the ARW is written again while its DNG is
    // tagged, after its conversion. It is not the file that was converted,
    // so it stays.
    func testARealARWThatChangesAfterItsConversionStays() throws {
        let arw = try copyFixture(as: "frame.ARW")
        _ = try factsOfACoveredFrame(arw)
        let (trash, backups) = try makeTrash()
        // The backup of the tag step goes to the trash before step 5. At
        // that moment the ARW gets one byte more.
        let changing = FileBackups(trash: { file in
            if file.lastPathComponent == "frame.dng_original" {
                let handle = try FileHandle(forWritingTo: arw)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data([0]))
                try handle.close()
            }
            try backups.trashFile(file)
        })

        let summary = try job(movingTo: changing).run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true,
                                                      trashOriginals: true)

        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng"], "the ARW stays")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), ["frame.dng_original"])
        XCTAssertEqual(summary.notes, [FileNote(
            name: "frame.ARW", kind: .originalKept, message: "The original changed during the run, so it stays.",
            detail: nil)])
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 0 of 1.")
    }

    /// True once, from any thread.
    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func first() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    // The case of the review of 2026-10-10, with the real tools (design
    // 14.2, line 6). After the conversion, an outside rename puts the DNG
    // of another `frame.ARW` at `frame.dng`. That DNG names `frame.ARW`,
    // and the tag step gives it the chosen factor, so line 5 passes for it.
    // Before line 6, the ARW moved, though its own DNG was gone. Now it
    // stays: the DNG at the name is not the file that this run made.
    //
    // The hook is the job's read of the disk. The rename comes directly
    // after the first record of the DNG, so it is between the conversion
    // and the tag step.
    func testARealDNGOfAnotherFrameThatTakesTheNameAfterTheConversionKeepsTheARW() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let facts = try factsOfACoveredFrame(arw)
        let before = try Data(contentsOf: arw)
        // Another conversion of a file with the same name, in another
        // folder: a second DNG that names `frame.ARW`.
        let elsewhere = folder.deletingLastPathComponent().appendingPathComponent("Another shoot")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let other = try converter.convert(try copyFixture(as: "frame.ARW", into: elsewhere), facts: facts).dng
        let otherNumber = try XCTUnwrap(FileRecord.read(atPath: other.path)).fileNumber
        let (trash, backups) = try makeTrash()
        let dng = folder.appendingPathComponent("frame.dng")
        let once = Once()
        let job = DesqueezeJob(
            tag: tag,
            converters: RawConverters(exiftool: exiftool, dnglab: dnglab, adobe: nil, backups: backups),
            backups: backups,
            fileRecord: { path in
                let record = FileRecord.read(atPath: path)
                let url = URL(fileURLWithPath: path)
                if url.lastPathComponent == "frame.dng", url.deletingLastPathComponent().lastPathComponent
                    == "Shoot with spaces", once.first() {
                    // The outside rename. It replaces the run's own DNG.
                    _ = rename(other.path, path)
                }
                return record
            })

        let summary = try job.run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true, trashOriginals: true)

        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng"], "the ARW stays")
        XCTAssertEqual(try Data(contentsOf: arw), before, "with its bytes")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), ["frame.dng_original"],
                       "only the backup of the tag step went to the injected trash")
        XCTAssertEqual(summary.notes, [FileNote(
            name: "frame.ARW", kind: .originalKept,
            message: "The original stays, because its DNG changed during the run.", detail: nil)])
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 0 of 1.")
        // The DNG at the name is tagged as any DNG in the folder is.
        XCTAssertEqual([summary.converted, summary.set, summary.failed], [1, 1, 0])
        XCTAssertEqual(try tag.read(dng), Scale(horizontal: 1.5, vertical: 1))
        // It is the other frame's DNG, in the file that exiftool wrote from
        // it: the backup in the trash is the file that was renamed in.
        XCTAssertEqual(FileRecord.read(atPath: trash.appendingPathComponent("frame.dng_original").path)?.fileNumber,
                       otherNumber)
        // Line 5 alone holds for it. Only line 6 keeps the ARW.
        XCTAssertEqual(DNGCheck.check("frame.dng", record: FileRecord.read(atPath: dng.path), arw: "frame.ARW",
                                      factor: SqueezeFactor(1.5)!, tags: { try self.tag.readOriginalCheck(dng) }),
                       .passed)
    }

    // dnglab alone, and a file that is no photo: failed, with dnglab's words.
    // dnglab made no DNG, so the folder holds what it held.
    //
    // dnglab alone converts the photo whatever frame it is. A frame with no
    // full match counts as converted, and gets the note of design 13.4.
    func testARealRunWithDnglabAloneReportsAFileThatDnglabCannotRead() throws {
        let arw = try copyFixture(as: "frame.ARW")
        let facts = try facts(of: arw)
        try Data("not a photo".utf8).write(to: folder.appendingPathComponent("junk.ARW"))

        let summary = try job(withAdobe: false).run(folder: folder,
                                                    factor: .noStretch, convert: true, trashOriginals: false)

        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.failed, summary.unconvertedARWs],
                       [1, 1, 1, 1])
        let unmatched = AdobeMatch.match(facts).failed.map {
            [FileNote.convertedUnmatched("frame.dng", rule: $0, facts: facts)]
        } ?? []
        XCTAssertEqual(summary.notes, unmatched + [FileNote(
            name: "junk.ARW", kind: .notConverted, message: "Not converted.",
            detail: "dnglab returned 7. Unsupported file: Error: No decoder found, model '', make: '', mode: ''.")])
        XCTAssertEqual(try names(), ["frame.ARW", "frame.dng", "junk.ARW"])
    }
}
