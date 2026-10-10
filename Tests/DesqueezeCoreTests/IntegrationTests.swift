import XCTest
@testable import DesqueezeCore

/// Runs the real exiftool and the real Adobe DNG Converter on copies of the
/// two files in `fixtures/`. Skips when a fixture or a tool is absent.
final class IntegrationTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures")

    var folder: URL!
    var exiftool: URL!
    var converterTool: URL!

    override func setUpWithError() throws {
        let locator = ToolLocator()
        let arw = Self.fixtures.appendingPathComponent("sample.ARW")
        let dng = Self.fixtures.appendingPathComponent("sample.dng")
        guard FileManager.default.fileExists(atPath: arw.path),
              FileManager.default.fileExists(atPath: dng.path) else {
            throw XCTSkip("No fixtures. Run scripts/make_fixtures.sh with one ARW file.")
        }
        guard let exiftool = locator.exiftool(), let converterTool = locator.dngConverter() else {
            throw XCTSkip("exiftool or Adobe DNG Converter is not installed.")
        }
        self.exiftool = exiftool
        self.converterTool = converterTool
        folder = try makeTemporaryFolder(named: "Shoot with spaces")
    }

    override func tearDown() {
        if let folder { removeTemporaryFolder(folder) }
    }

    func copyFixture(_ name: String, as newName: String) throws -> URL {
        let destination = folder.appendingPathComponent(newName)
        try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(name), to: destination)
        return destination
    }

    // Tests discard backups for good. The real Trash is checked by hand.
    var backups: FileBackups { FileBackups(trash: { try FileManager.default.removeItem(at: $0) }) }
    var tag: ScaleTag { ScaleTag(exiftool: exiftool) }
    var scanner: FolderScanner { FolderScanner(tag: tag, backups: backups) }
    /// As on a Mac with Adobe DNG Converter and no dnglab. The run with both
    /// converters is in `DnglabRunIntegrationTests`.
    var job: DesqueezeJob {
        DesqueezeJob(tag: tag, converters: RawConverters(exiftool: exiftool, dnglab: nil, adobe: converterTool,
                                                         backups: backups),
                     backups: backups)
    }

    func names(withSuffix suffix: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(suffix) }.sorted()
    }

    /// Adobe DNG Converter wrote the hidden work file, and the rename gave
    /// it its name (design 13.3): the DNG is a file with bytes at
    /// `<base>.dng`, and the folder has no hidden file left.
    func assertTheDNGHasItsNameAndNoHiddenFileIsLeft(_ name: String, file: StaticString = #filePath,
                                                     line: UInt = #line) throws {
        let size = ConverterOutput.size(atPath: folder.appendingPathComponent(name).path)
        XCTAssertGreaterThan(size ?? 0, 0, "\(name) is not a file with bytes", file: file, line: line)
        // `contentsOfDirectory(atPath:)` lists hidden files too.
        let hidden = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".") }
        XCTAssertEqual(hidden, [], "a hidden file is left in the folder", file: file, line: line)
    }

    /// The tag as the file holds it now. One file, read directly: not a scan.
    func scaleOnDisk(_ name: String) throws -> Scale? {
        try tag.read(folder.appendingPathComponent(name))
    }

    /// exiftool's SHA-256 of the image data alone. A tag write must not
    /// change it.
    func imageDataHash(_ file: URL) throws -> String {
        let result = try SystemProcessRunner().run(
            exiftool, ["-api", "ImageHashType=SHA256", "-ImageDataHash", "-s3", file.path])
        let hash = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // exiftool prints nothing, and exits 0, for a file that it cannot
        // hash. Two empty strings would compare as equal.
        XCTAssertEqual(hash.count, 64, "no image data hash for \(file.lastPathComponent): \(result.stderr)")
        XCTAssertTrue(hash.allSatisfy(\.isHexDigit))
        return hash
    }

    func testARealRunConvertsTagsChecksAndClearsTheBackups() throws {
        // "already here.dng" has no ARW. "frame.ARW" has no DNG.
        _ = try copyFixture("sample.dng", as: "already here.dng")
        let arw = try copyFixture("sample.ARW", as: "frame.ARW")
        let arwBefore = try Data(contentsOf: arw)
        let factor = SqueezeFactor(1.5)!

        let first = try scanner.snapshot(of: folder)
        XCTAssertEqual(first.dngs.map(\.name), ["already here.dng"])
        XCTAssertEqual(first.pendingARWs.map(\.lastPathComponent), ["frame.ARW"])

        let summary = job.run(first, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.notes, [])

        let second = try scanner.snapshot(of: folder)
        XCTAssertEqual(second.dngs.map(\.name), ["already here.dng", "frame.dng"])
        XCTAssertEqual(second.dngs.map(\.scale?.horizontal), [1.5, 1.5])
        XCTAssertEqual(second.dngs.map(\.scale?.vertical), [1, 1])
        XCTAssertEqual(second.pendingARWs, [])
        XCTAssertEqual(try names(withSuffix: "_original"), [])
        XCTAssertEqual(try names(withSuffix: ".dng"), ["already here.dng", "frame.dng"], "no _1.dng duplicate")
        try assertTheDNGHasItsNameAndNoHiddenFileIsLeft("frame.dng")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["already here.dng", "frame.ARW", "frame.dng"], "every file of the folder, hidden files too")
        XCTAssertEqual(second.dngs.map(\.originalRawFileName), ["sample.ARW", "frame.ARW"],
                       "Adobe DNG Converter names the ARW, and not the work file")
        XCTAssertEqual(try Data(contentsOf: arw), arwBefore, "the ARW must not change")

        let rerun = job.run(second, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(rerun.skipped, 2)
        XCTAssertEqual(rerun.set, 0)
        XCTAssertEqual(rerun.converted, 0)

        let removed = job.run(second, factor: .noStretch, convert: false, trashOriginals: false)
        XCTAssertEqual(removed.set, 2)
        XCTAssertEqual(removed.failed, 0)
        XCTAssertEqual(removed.notes, [])
        XCTAssertEqual(try scanner.snapshot(of: folder).dngs.map(\.scale?.horizontal), [1, 1])
        XCTAssertEqual(try names(withSuffix: "_original"), [])
    }

    // exiftool prints the tab of a file name as a period, so the folder read
    // has no row named `tab<TAB>here.dng`. The scan finds the row by the
    // printed name. Without that, its scale is unknown, and every run writes
    // the file again and never skips it. No converter is needed: the folder
    // holds no ARW.
    func testADNGWithATabInItsNameIsSkippedOnTheSecondRun() throws {
        let name = "tab\there.dng"
        _ = try copyFixture("sample.dng", as: name)
        let job = DesqueezeJob(tag: tag, converters: .none, backups: backups)
        let factor = SqueezeFactor(1.5)!

        let first = try job.run(folder: folder, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual([first.set, first.skipped, first.failed], [1, 0, 0], "\(first.notes)")
        XCTAssertEqual(try scaleOnDisk(name), Scale(horizontal: 1.5, vertical: 1))
        XCTAssertEqual(try scanner.snapshot(of: folder).dngs.map(\.scale), [Scale(horizontal: 1.5, vertical: 1)],
                       "the scan finds the row by the printed name")

        let second = try job.run(folder: folder, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual([second.set, second.skipped, second.failed], [0, 1, 0], "\(second.notes)")
        XCTAssertEqual(try names(withSuffix: "_original"), [])
    }

    func testARenamedDNGStillClaimsItsARW() throws {
        // The fixture DNG was converted from a file named sample.ARW, so its
        // OriginalRawFileName tag is "sample.ARW".
        _ = try copyFixture("sample.dng", as: "Renamed on import 0022.dng")
        _ = try copyFixture("sample.ARW", as: "sample.ARW")
        let snapshot = try scanner.snapshot(of: folder)
        XCTAssertEqual(snapshot.dngs.first?.originalRawFileName, "sample.ARW")
        XCTAssertEqual(snapshot.pendingARWs, [])
    }

    // The two runs are the only calls. Nothing scans between them, so Remove
    // is right only when the job reads the folder itself.
    func testApplyThenRemoveWithNoScanBetweenThemLeavesEveryDNGUnstretched() throws {
        _ = try copyFixture("sample.dng", as: "already here.dng")
        _ = try copyFixture("sample.ARW", as: "frame.ARW")

        let applied = try job.run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true, trashOriginals: false)
        let removed = try job.run(folder: folder, factor: .noStretch, convert: false, trashOriginals: false)

        XCTAssertEqual(applied.converted, 1)
        XCTAssertEqual(applied.set, 2)
        XCTAssertEqual(applied.failed, 0)
        XCTAssertEqual(applied.notes, [])

        XCTAssertEqual(removed.converted, 0)
        XCTAssertEqual(removed.set, 2, "Remove must write both files, the converted one too")
        XCTAssertEqual(removed.skipped, 0)
        XCTAssertEqual(removed.failed, 0)
        XCTAssertEqual(removed.notes, [])

        XCTAssertEqual(try names(withSuffix: ".dng"), ["already here.dng", "frame.dng"])
        try assertTheDNGHasItsNameAndNoHiddenFileIsLeft("frame.dng")
        XCTAssertEqual(try scaleOnDisk("already here.dng"), .noStretch)
        XCTAssertEqual(try scaleOnDisk("frame.dng"), .noStretch)
        XCTAssertEqual(try names(withSuffix: "_original"), [])
    }

    // The note "Not changed." is true only when a failed exiftool write makes
    // no backup and leaves the file as it was. The fakes assume that. This
    // test holds the real exiftool to it.
    func testAFailedWriteAndAnOlderBackupLeaveEveryFileAsItWas() throws {
        let good = try copyFixture("sample.dng", as: "good.dng")
        let planted = try copyFixture("sample.dng", as: "planted.dng")
        let plantedBackup = folder.appendingPathComponent("planted.dng_original")
        let junk = folder.appendingPathComponent("junk.dng")
        let junkBytes = Data("not a photo".utf8)
        let backupBytes = Data("an older backup".utf8)
        try junkBytes.write(to: junk)
        try backupBytes.write(to: plantedBackup)
        let plantedBefore = try Data(contentsOf: planted)
        let hashBefore = try imageDataHash(good)

        let applied = try job.run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true, trashOriginals: false)

        XCTAssertEqual(applied.converted, 0)
        XCTAssertEqual(applied.set, 1)
        XCTAssertEqual(applied.failed, 1)
        XCTAssertEqual(applied.blocked, 1)
        XCTAssertEqual(applied.skipped, 0)
        XCTAssertEqual(applied.notes.map(\.name), ["junk.dng", "planted.dng"])
        XCTAssertEqual(applied.notes.first?.message, "Not changed.")
        XCTAssertEqual(applied.notes.first?.detail?.hasPrefix("Error"), true, "exiftool's own reason")
        XCTAssertEqual(applied.notes.last, FileNote(
            name: "planted.dng", kind: .blockedByBackup,
            message: "Blocked. An older backup, planted.dng_original, is beside this file. Move it away, then run again.",
            detail: nil))

        // The junk file: the same bytes, and no backup of it.
        XCTAssertEqual(try Data(contentsOf: junk), junkBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: junk.path + "_original"))
        // The planted pair: neither file was touched.
        XCTAssertEqual(try Data(contentsOf: planted), plantedBefore)
        XCTAssertEqual(try Data(contentsOf: plantedBackup), backupBytes)
        XCTAssertEqual(try names(withSuffix: "_original"), ["planted.dng_original"])
        XCTAssertEqual(try names(withSuffix: "_exiftool_tmp"), [])
        // The good file: the tag changed, and the image data did not.
        XCTAssertEqual(try scaleOnDisk("good.dng"), Scale(horizontal: 1.5, vertical: 1))
        XCTAssertEqual(try imageDataHash(good), hashBefore)

        // Remove, on the same folder. exiftool cannot read the junk file, so
        // its scale is unknown, and it must fail aloud. It must not be skipped.
        let removed = try job.run(folder: folder, factor: .noStretch, convert: false, trashOriginals: false)

        XCTAssertEqual(removed.set, 1)
        XCTAssertEqual(removed.failed, 1)
        XCTAssertEqual(removed.skipped, 1)
        XCTAssertEqual(removed.notes.map(\.name), ["junk.dng", "planted.dng"])
        XCTAssertEqual(removed.notes.first?.message, "Not changed.")
        XCTAssertEqual(removed.notes.last, FileNote(
            name: "planted.dng", kind: .leftoverBackup,
            message: "Already at this value. A backup, planted.dng_original, is beside this file.",
            detail: nil))
        XCTAssertEqual(try Data(contentsOf: junk), junkBytes)
        XCTAssertEqual(try Data(contentsOf: planted), plantedBefore)
        XCTAssertEqual(try Data(contentsOf: plantedBackup), backupBytes)
        XCTAssertEqual(try names(withSuffix: "_original"), ["planted.dng_original"])
        XCTAssertEqual(try scaleOnDisk("good.dng"), .noStretch)
        XCTAssertEqual(try imageDataHash(good), hashBefore)
    }

    // exiftool stopped between its two renames: the backup is there and the
    // DNG is not. A real run must say so, in Apply and in Remove, and must
    // leave the backup as it is.
    func testARealRunReportsAnOrphanBackupAndLeavesItAsItWas() throws {
        _ = try copyFixture("sample.dng", as: "good.dng")
        let orphan = try copyFixture("sample.dng", as: "lost.dng_original")
        let orphanBefore = try Data(contentsOf: orphan)
        let note = FileNote(
            name: "lost.dng_original", kind: .orphanBackup,
            message: "A backup with no DNG beside it. Rename it to lost.dng to get the photo back.", detail: nil)

        let applied = try job.run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true, trashOriginals: false)
        XCTAssertEqual(applied.notes, [note])
        XCTAssertEqual(applied.set, 1)
        XCTAssertEqual(applied.converted, 0)
        XCTAssertEqual(applied.skipped, 0)
        XCTAssertEqual(applied.failed, 0)

        let removed = try job.run(folder: folder, factor: .noStretch, convert: false, trashOriginals: false)
        XCTAssertEqual(removed.notes, [note])
        XCTAssertEqual(removed.set, 1)
        XCTAssertEqual(removed.failed, 0)

        XCTAssertEqual(try Data(contentsOf: orphan), orphanBefore)
        XCTAssertEqual(try names(withSuffix: "_original"), ["lost.dng_original"])
        XCTAssertEqual(try names(withSuffix: ".dng"), ["good.dng"], "the job must not do the rename itself")
        XCTAssertEqual(try scaleOnDisk("good.dng"), .noStretch)
    }

    // Found with the real tools: the run converted frame.ARW while frame.dng
    // was waiting as a backup, and gave two notes that said opposite things
    // about one photo.
    func testARealRunDoesNotConvertAnARWWhoseDNGIsWaitingAsAnOrphanBackup() throws {
        let orphan = try copyFixture("sample.dng", as: "frame.dng_original")
        let arw = try copyFixture("sample.ARW", as: "frame.ARW")
        let orphanBefore = try Data(contentsOf: orphan)
        let arwBefore = try Data(contentsOf: arw)

        let summary = try job.run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true, trashOriginals: false)

        var expected = RunSummary()
        expected.notes = [FileNote(
            name: "frame.dng_original", kind: .orphanBackup,
            message: "A backup with no DNG beside it. Rename it to frame.dng to get the photo back.", detail: nil)]
        XCTAssertEqual(summary, expected, "nothing converted, nothing set, and one note for the photo")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["frame.ARW", "frame.dng_original"], "no DNG was made")
        XCTAssertEqual(try Data(contentsOf: orphan), orphanBefore)
        XCTAssertEqual(try Data(contentsOf: arw), arwBefore)
    }

    // MARK: The dry run, with the real tools

    /// Every file in the folder: its bytes, and when it was last changed.
    func folderState() throws -> [String: [String]] {
        var state: [String: [String]] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
            let url = folder.appendingPathComponent(name)
            let changed = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            state[name] = [try Data(contentsOf: url).base64EncodedString(), String(describing: changed)]
        }
        return state
    }

    func testARealPlanChangesNoFileAndAgreesWithTheRunThatFollows() throws {
        _ = try copyFixture("sample.dng", as: "already here.dng")
        _ = try copyFixture("sample.dng", as: "held.dng")
        _ = try copyFixture("sample.ARW", as: "frame.ARW")
        try Data("an older backup".utf8).write(to: folder.appendingPathComponent("held.dng_original"))
        try Data("a lost photo".utf8).write(to: folder.appendingPathComponent("lost.dng_original"))
        let before = try folderState()
        XCTAssertEqual(before.count, 5)
        let factor = SqueezeFactor(1.5)!

        let plan = try job.plan(folder: folder, factor: factor, convert: true, trashOriginals: false)

        XCTAssertEqual(try folderState(), before, "a plan must change no byte, no date, and no name")
        XCTAssertEqual(plan.steps, [
            RunPlan.Step(name: "frame.ARW", action: .convert, converter: .adobe),
            RunPlan.Step(name: "already here.dng", action: .write),
            RunPlan.Step(name: "held.dng", action: .blocked),
            RunPlan.Step(name: "frame.dng", action: .write),
        ])
        XCTAssertEqual(plan.summary.notes.map(\.kind), [.orphanBackup, .blockedByBackup])

        let summary = try job.run(folder: folder, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary, plan.summary, "the run that follows gives the counts and notes of the plan")
        XCTAssertNotEqual(try folderState(), before, "the premise: a real run does change the folder")
        try assertTheDNGHasItsNameAndNoHiddenFileIsLeft("frame.dng")
    }
}
