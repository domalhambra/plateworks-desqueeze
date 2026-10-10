import XCTest
@testable import DesqueezeCore

final class DesqueezeJobTests: XCTestCase {
    let folder = URL(fileURLWithPath: "/tmp/Shoot 1")
    let factor = SqueezeFactor(1.5)!
    var log: CallLog!
    var backups: FakeBackups!
    var tag: FakeTag!
    /// Adobe DNG Converter. Its log entries start with "convert".
    var converter: FakeConverter!
    /// dnglab. Its log entries start with "dnglab".
    var dnglab: FakeConverter!
    var facts: FakeFacts!

    override func setUp() {
        log = CallLog()
        backups = FakeBackups(log: log)
        tag = FakeTag(log: log, backups: backups)
        converter = FakeConverter(log: log)
        dnglab = FakeConverter(log: log, label: "dnglab", name: "dnglab", reportsTheMatch: true)
        facts = FakeFacts(log: log)
    }

    func dng(_ name: String, at horizontal: Double = 1) -> DNGFile {
        DNGFile(url: folder.appendingPathComponent(name), scale: Scale(horizontal: horizontal, vertical: 1),
                originalRawFileName: nil, hasBackup: false)
    }

    /// A DNG that the scan could not read: junk, or a file with no tag.
    func unread(_ name: String) -> DNGFile {
        DNGFile(url: folder.appendingPathComponent(name), scale: nil, originalRawFileName: nil, hasBackup: false)
    }

    func snapshot(dngs: [DNGFile], pending: [String] = [], orphans: [String] = [],
                  writable: Bool = true) -> FolderSnapshot {
        FolderSnapshot(folder: folder, dngs: dngs,
                       pendingARWs: pending.map { folder.appendingPathComponent($0) },
                       orphanBackups: orphans.map { folder.appendingPathComponent($0) }, isWritable: writable)
    }

    /// - Parameters:
    ///   - withConverter: Adobe DNG Converter is installed.
    ///   - withDnglab: dnglab is installed. Off by default, so a test that
    ///     does not name it runs as on a Mac with Adobe's converter alone.
    func job(withConverter: Bool = true, withDnglab: Bool = false) -> DesqueezeJob {
        DesqueezeJob(tag: tag, converters: RawConverters(dnglab: withDnglab ? dnglab : nil,
                                                         adobe: withConverter ? converter : nil, facts: facts),
                     backups: backups)
    }

    func testConvertsEveryPendingARWFirstThenTagsEveryDNG() {
        let summary = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, [
            "convert X.ARW",
            "write 1.5 1 A.dng", "read A.dng", "trash A.dng",
            "write 1.5 1 X.dng", "read X.dng", "trash X.dng",
        ])
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.notes, [])
    }

    // The names are chosen so that name order (A, Z) is not run order (Z, A).
    func testNewDNGFilesAreTaggedLastNotInNameOrder() {
        let summary = job().run(snapshot(dngs: [dng("Z.dng")], pending: ["A.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, [
            "convert A.ARW",
            "write 1.5 1 Z.dng", "read Z.dng", "trash Z.dng",
            "write 1.5 1 A.dng", "read A.dng", "trash A.dng",
        ])
        XCTAssertEqual(summary.set, 2)
    }

    func testAFileAlreadyAtTheFactorGetsNoCall() {
        let summary = job().run(snapshot(dngs: [dng("A.dng", at: 1.5)]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.notes, [])
    }

    func testAFileWithAnExistingBackupIsBlockedWithANote() {
        backups.existing = ["A.dng"]
        let summary = job().run(snapshot(dngs: [dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(summary.blocked, 1)
        XCTAssertEqual(summary.skipped, 0, "skipped means only: already at this value")
        XCTAssertEqual(summary.notes.map(\.name), ["A.dng"])
        XCTAssertTrue(summary.notes[0].message.hasPrefix("Blocked."))
        XCTAssertTrue(backups.existing.contains("A.dng"), "the old backup must stay")
    }

    // The backup may be the only copy of the file as it was before a run that
    // died. The count stays "skipped", and the user is told.
    func testAFileAlreadyAtTheFactorWithALeftoverBackupIsSkippedWithANote() {
        backups.existing = ["A.dng"]
        let summary = job().run(snapshot(dngs: [dng("A.dng", at: 1.5), dng("B.dng", at: 1.5)]),
                                factor: factor, convert: true)
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(summary.skipped, 2)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "A.dng", kind: .leftoverBackup,
            message: "Already at this value. A backup, A.dng_original, is beside this file.", detail: nil)])
        XCTAssertTrue(backups.existing.contains("A.dng"), "the backup must stay")
    }

    func testAFailedWriteWithNoBackupDoesNotRestore() {
        tag.failWrites = ["A.dng"]
        let summary = job().run(snapshot(dngs: [dng("A.dng"), dng("B.dng")]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, [
            "write 1.5 1 A.dng",
            "write 1.5 1 B.dng", "read B.dng", "trash B.dng",
        ])
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.notes, [FileNote(name: "A.dng", kind: .failed, message: "Not changed.", detail: "Error: write failed")])
    }

    func testAFailedCheckRestoresTheBackup() {
        tag.wrongReadBack = ["A.dng"]
        let summary = job().run(snapshot(dngs: [dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["write 1.5 1 A.dng", "read A.dng", "restore A.dng"])
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.set, 0)
        XCTAssertEqual(summary.notes.map(\.message), ["Not changed. The backup was restored."])
    }

    func testAFailedCheckWithAFailedRestoreSaysSoAndKeepsBothErrors() {
        tag.wrongReadBack = ["A.dng"]
        backups.restoreError = NamedError(text: "The volume refused the rename.")
        let summary = job().run(snapshot(dngs: [dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["write 1.5 1 A.dng", "read A.dng", "restore A.dng"])
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.set, 0)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "A.dng", kind: .failed,
            message: "The change failed, and the backup could not be restored. The backup is A.dng_original.",
            detail: "The tag did not read back as 1.5 1.\nRestore: The volume refused the rename.")])
        XCTAssertTrue(backups.existing.contains("A.dng"), "the backup must stay")
    }

    func testAReadBackThatThrowsAfterAGoodWriteCountsAsFailedAndRestores() {
        tag.failReads = ["A.dng"]
        let summary = job().run(snapshot(dngs: [dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["write 1.5 1 A.dng", "read A.dng", "restore A.dng"])
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.set, 0)
        XCTAssertEqual(summary.notes, [FileNote(name: "A.dng", kind: .failed, message: "Not changed. The backup was restored.",
                                                detail: "Error: read failed")])
        XCTAssertFalse(backups.existing.contains("A.dng"), "the restore consumes the backup")
    }

    func testAReadBackWithNoTagAfterAGoodWriteCountsAsFailedAndRestores() {
        tag.noReadBack = ["A.dng"]
        let summary = job().run(snapshot(dngs: [dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["write 1.5 1 A.dng", "read A.dng", "restore A.dng"])
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.set, 0)
        XCTAssertEqual(summary.notes, [FileNote(name: "A.dng", kind: .failed, message: "Not changed. The backup was restored.",
                                                detail: "The tag did not read back as 1.5 1.")])
        XCTAssertFalse(backups.existing.contains("A.dng"), "the restore consumes the backup")
    }

    func testARefusedTrashCountsAsSetAndKeepsTheBackup() {
        backups.trashError = CocoaError(.fileWriteVolumeReadOnly)
        let summary = job().run(snapshot(dngs: [dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.notes.map(\.name), ["A.dng"])
        XCTAssertTrue(summary.notes[0].message.hasPrefix("Done."))
        XCTAssertTrue(backups.existing.contains("A.dng"))
    }

    func testRemoveWritesOneOneAndNeverConverts() {
        let files = [dng("A.dng", at: 1.5), dng("B.dng", at: 1)]
        let summary = job().run(snapshot(dngs: files, pending: ["X.ARW"]), factor: .noStretch, convert: false,
                                remove: true)
        XCTAssertEqual(log.entries, ["write 1 1 A.dng", "read A.dng", "trash A.dng"])
        XCTAssertEqual(summary.converted, 0)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.skipped, 1)
    }

    // Remove writes 1 1. A factor that rides along beside `remove` is ignored,
    // so no caller can make Remove write a stretch.
    func testRemoveWritesOneOneWhateverFactorItWasGiven() {
        let files = [dng("A.dng", at: 1.5), dng("B.dng", at: 1), dng("C.dng", at: 2)]
        let summary = job().run(snapshot(dngs: files), factor: factor, convert: false, remove: true)
        XCTAssertEqual(log.entries, [
            "write 1 1 A.dng", "read A.dng", "trash A.dng",
            "write 1 1 C.dng", "read C.dng", "trash C.dng",
        ])
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.failed, 0)
    }

    // "Unknown" is not "1 1". Remove must not skip a file that was never read.
    func testRemoveWritesAFileWhoseScaleIsUnknown() {
        let summary = job().run(snapshot(dngs: [unread("A.dng"), dng("B.dng", at: 1)]),
                                factor: .noStretch, convert: false)
        XCTAssertEqual(log.entries, ["write 1 1 A.dng", "read A.dng", "trash A.dng"])
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.notes, [])
    }

    func testRemoveReportsAJunkFileAsFailed() {
        tag.failWrites = ["junk.dng"]
        let summary = job().run(snapshot(dngs: [unread("junk.dng")]), factor: .noStretch, convert: false)
        XCTAssertEqual(log.entries, ["write 1 1 junk.dng"])
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.notes, [FileNote(name: "junk.dng", kind: .failed, message: "Not changed.",
                                                detail: "Error: write failed")])
    }

    func testApplyWritesAFileWhoseScaleIsUnknownAndReportsAJunkFileAsFailed() {
        tag.failWrites = ["junk.dng"]
        let summary = job().run(snapshot(dngs: [unread("A.dng"), unread("junk.dng")]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, [
            "write 1.5 1 A.dng", "read A.dng", "trash A.dng",
            "write 1.5 1 junk.dng",
        ])
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.notes, [FileNote(name: "junk.dng", kind: .failed, message: "Not changed.",
                                                detail: "Error: write failed")])
    }

    // The job does not read a DNG that it just converted. The converter
    // writes no stretch, so a run at factor 1 has nothing to write.
    func testADNGTheJobJustConvertedHasAKnownScaleOfNoStretch() {
        let summary = job().run(snapshot(dngs: [], pending: ["X.ARW"]), factor: .noStretch, convert: true)
        XCTAssertEqual(log.entries, ["convert X.ARW"])
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.set, 0)
    }

    func testAFailedConversionIsReportedAndTheRunContinues() {
        converter.fail = ["X.ARW"]
        let summary = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW", "Y.ARW"]),
                                factor: factor, convert: true)
        XCTAssertEqual(log.entries.filter { $0.hasPrefix("convert") }, ["convert X.ARW", "convert Y.ARW"])
        XCTAssertFalse(log.entries.contains { $0.hasPrefix("trashFile") }, "no partial DNG, nothing to discard")
        XCTAssertFalse(log.entries.contains("write 1.5 1 X.dng"))
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(summary.notes, [FileNote(name: "X.ARW", kind: .notConverted, message: "Not converted.", detail: "made no DNG")])
    }

    // A conversion that failed after it started may have left a partial DNG.
    // The ARW keeps its `failed` note, and the note says where the file went.
    func testAPartialDNGFromAFailedConversionGoesToTheTrashAndTheNoteSaysSo() {
        converter.failWithPartial = ["X.ARW"]
        let summary = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW", "Y.ARW"]),
                                factor: factor, convert: true)
        XCTAssertEqual(log.entries.filter { $0.hasPrefix("convert") || $0.hasPrefix("trashFile") }, [
            "convert X.ARW", "trashFile X.dng", "convert Y.ARW",
        ], "the run continues with the next ARW")
        XCTAssertFalse(log.entries.contains("write 1.5 1 X.dng"), "a failed conversion is never tagged")
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.unconvertedARWs, 1, "the ARW whose conversion failed is still unconverted")
        XCTAssertEqual(summary.notes, [FileNote(
            name: "X.ARW", kind: .notConverted, message: "Not converted.",
            detail: "Adobe DNG Converter returned 1. The partial DNG was moved to the Trash.")])
    }

    func testARefusedTrashForAPartialDNGNamesTheFileToDelete() {
        converter.failWithPartial = ["X.ARW"]
        backups.trashFileError = NamedError(text: "The Trash refused it.")
        let summary = job().run(snapshot(dngs: [], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["convert X.ARW", "trashFile X.dng"])
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.unconvertedARWs, 1)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "X.ARW", kind: .notConverted, message: "Not converted.",
            detail: "Adobe DNG Converter returned 1. A partial DNG, X.dng, is beside the ARW. Delete it, then run again.")])
    }

    // The second lock. The converter proves that the partial DNG is its own.
    // The job does not take its word: it moves a file only when the file is
    // the output of that ARW, and no DNG that the scan found.
    func testAPartialDNGThatTheScanFoundIsNotMovedAndTheNoteNamesIt() {
        converter.failWithPartial = ["X.ARW"]
        converter.reportedPartial = folder.appendingPathComponent("X.dng")
        // The scan found X.dng, and X.ARW is pending all the same: a state
        // that the scan never makes, and the one that the lock is for.
        let summary = job().run(snapshot(dngs: [dng("X.dng", at: 1.5)], pending: ["X.ARW"]),
                                factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["convert X.ARW"], "no file was moved")
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "X.ARW", kind: .notConverted, message: "Not converted.",
            detail: "Adobe DNG Converter returned 1. "
                + "A file, X.dng, was reported as the partial DNG. It is not this run's file, and it was not moved.")])
    }

    func testAPartialDNGThatIsNotTheOutputOfItsARWIsNotMovedAndTheNoteNamesIt() {
        converter.failWithPartial = ["X.ARW"]
        converter.reportedPartial = folder.appendingPathComponent("A.dng")
        let summary = job().run(snapshot(dngs: [], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["convert X.ARW"], "no file was moved")
        XCTAssertEqual(summary.notes.map(\.detail), [
            "Adobe DNG Converter returned 1. "
                + "A file, A.dng, was reported as the partial DNG. It is not this run's file, and it was not moved.",
        ])

        // The same name in another folder is another file.
        log.entries = []
        converter.reportedPartial = URL(fileURLWithPath: "/tmp/Shoot 2/X.dng")
        let other = job().run(snapshot(dngs: [], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["convert X.ARW"], "no file was moved")
        XCTAssertEqual(other.failed, 1)
    }

    func testAFailedConversionWithNoPartialDNGDiscardsNothing() {
        converter.fail = ["X.ARW"]
        _ = job().run(snapshot(dngs: [], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["convert X.ARW"])
    }

    // The whole path on real files: an AdobeConverter on a fake runner that
    // leaves an empty DNG, a real folder, and a Trash that is a temporary
    // folder. The empty file must move there, and the ARW must not change.
    func testAnEmptyDNGFromAConversionReallyMovesToTheInjectedTrash() throws {
        let shoot = try makeTemporaryFolder()
        defer { removeTemporaryFolder(shoot) }
        let trash = shoot.deletingLastPathComponent().appendingPathComponent("Test trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let arw = shoot.appendingPathComponent("a.ARW")
        try Data("raw bytes".utf8).write(to: arw)

        let runner = FakeRunner()
        runner.handler = { _ in
            FileManager.default.createFile(atPath: shoot.appendingPathComponent("a.dng").path, contents: Data())
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        let environment = [FileBackups.testFolderVariable: trash.path]
        let files = try FileBackups.fromEnvironment(environment).backups
        let adobe = AdobeConverter(executable: URL(fileURLWithPath: "/nonexistent/Adobe DNG Converter"), runner: runner)
        let realJob = DesqueezeJob(tag: tag, converters: RawConverters(dnglab: nil, adobe: adobe, facts: nil),
                                   backups: files)

        let summary = realJob.run(
            FolderSnapshot(folder: shoot, dngs: [], pendingARWs: [arw], orphanBackups: [], isWritable: true),
            factor: factor, convert: true)

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shoot.path), ["a.ARW"])
        XCTAssertEqual(try Data(contentsOf: arw), Data("raw bytes".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), ["a.dng"])
        XCTAssertEqual(try Data(contentsOf: trash.appendingPathComponent("a.dng")), Data())
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.unconvertedARWs, 1)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "a.ARW", kind: .notConverted, message: "Not converted.",
            detail: "Adobe DNG Converter made an empty DNG. The partial DNG was moved to the Trash.")])
        XCTAssertEqual(log.entries, [], "the job tagged nothing")
    }

    // MARK: Two converters (design 13.4)

    /// The entries of the log that are no tag work.
    var conversionLog: [String] {
        log.entries.filter { !$0.hasPrefix("write ") && !$0.hasPrefix("read ") && !$0.hasPrefix("trash ") }
    }

    func testAFullMatchGoesToDnglabAndAdobeIsNotStarted() {
        facts.facts = ["X.ARW": .adapted]
        let summary = job(withDnglab: true).run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW"]),
                                                factor: factor, convert: true)
        XCTAssertEqual(log.entries, [
            "facts X.ARW", "dnglab X.ARW",
            "write 1.5 1 A.dng", "read A.dng", "trash A.dng",
            "write 1.5 1 X.dng", "read X.dng", "trash X.dng",
        ])
        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.convertedByAdobe], [1, 1, 0])
        XCTAssertEqual([summary.set, summary.failed, summary.unconvertedARWs], [2, 0, 0])
        XCTAssertEqual(summary.notes, [])
        XCTAssertEqual(dnglab.facts, ["X.ARW": .adapted], "the converter gets the facts of its ARW")
    }

    // One read for every pending ARW, before the first conversion.
    func testTheFactsOfAllPendingARWFilesAreReadWithOneCall() {
        facts.facts = ["X.ARW": .adapted, "Y.ARW": .adapted, "Z.ARW": .adapted]
        _ = job(withDnglab: true).run(snapshot(dngs: [], pending: ["X.ARW", "Y.ARW", "Z.ARW"]),
                                      factor: .noStretch, convert: true)
        XCTAssertEqual(log.entries, ["facts X.ARW Y.ARW Z.ARW", "dnglab X.ARW", "dnglab Y.ARW", "dnglab Z.ARW"])
    }

    // dnglab failed, so the next converter gets the ARW. It converts: the
    // ARW is not failed, and it has no note.
    func testWhenDnglabFailsAdobeConvertsAndTheARWIsNotFailed() {
        facts.facts = ["X.ARW": .adapted]
        dnglab.fail = ["X.ARW"]
        let summary = job(withDnglab: true).run(snapshot(dngs: [], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, [
            "facts X.ARW", "dnglab X.ARW", "convert X.ARW",
            "write 1.5 1 X.dng", "read X.dng", "trash X.dng",
        ])
        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.convertedByAdobe], [1, 0, 1])
        XCTAssertEqual([summary.set, summary.failed, summary.unconvertedARWs], [1, 0, 0])
        XCTAssertEqual(summary.notes, [])
        XCTAssertFalse(summary.needsAttention)
    }

    // dnglab's partial DNG goes to the Trash before Adobe DNG Converter
    // starts: left there, the name would be taken.
    func testThePartialDNGOfDnglabIsDiscardedBeforeAdobeGetsTheARW() {
        facts.facts = ["X.ARW": .adapted]
        dnglab.failWithPartial = ["X.ARW"]
        let summary = job(withDnglab: true).run(snapshot(dngs: [], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(conversionLog, ["facts X.ARW", "dnglab X.ARW", "trashFile X.dng", "convert X.ARW"])
        XCTAssertEqual([summary.convertedByAdobe, summary.failed], [1, 0])
        XCTAssertEqual(summary.notes, [])
    }

    // The ARW is failed only when the last converter failed. The detail has
    // each converter's own words, one line for each.
    func testWhenDnglabAndAdobeBothFailTheARWIsFailedWithALineForEachConverter() {
        facts.facts = ["X.ARW": .adapted, "Y.ARW": .adapted]
        dnglab.failWithPartial = ["X.ARW"]
        converter.fail = ["X.ARW"]
        let summary = job(withDnglab: true).run(snapshot(dngs: [], pending: ["X.ARW", "Y.ARW"]),
                                                factor: factor, convert: true)
        XCTAssertEqual(conversionLog, [
            "facts X.ARW Y.ARW", "dnglab X.ARW", "trashFile X.dng", "convert X.ARW", "dnglab Y.ARW",
        ], "the run goes on with the next ARW")
        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.convertedByAdobe], [1, 1, 0])
        XCTAssertEqual([summary.failed, summary.unconvertedARWs, summary.set], [1, 1, 1])
        XCTAssertEqual(summary.notes, [FileNote(
            name: "X.ARW", kind: .notConverted, message: "Not converted.",
            detail: "dnglab returned 1. The partial DNG was moved to the Trash.\nmade no DNG")])
        XCTAssertFalse(log.entries.contains("write 1.5 1 X.dng"), "a failed conversion is never tagged")
    }

    func testWhenDnglabFailsAndThereIsNoAdobeTheARWIsFailed() {
        facts.facts = ["X.ARW": .adapted]
        dnglab.failWithPartial = ["X.ARW"]
        let summary = job(withConverter: false, withDnglab: true)
            .run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(conversionLog, ["facts X.ARW", "dnglab X.ARW", "trashFile X.dng"])
        XCTAssertEqual([summary.converted, summary.failed, summary.unconvertedARWs, summary.set], [0, 1, 1, 1])
        XCTAssertEqual(summary.notes, [FileNote(
            name: "X.ARW", kind: .notConverted, message: "Not converted.",
            detail: "dnglab returned 1. The partial DNG was moved to the Trash.")])
    }

    // No full match, and both installed: Adobe DNG Converter gives the file
    // that Lightroom makes. dnglab is not started.
    func testWithNoFullMatchAndBothInstalledOnlyAdobeIsStarted() {
        facts.facts = ["lens.ARW": .lens, "iso.ARW": .iso1250]
        let summary = job(withDnglab: true).run(
            snapshot(dngs: [], pending: ["iso.ARW", "lens.ARW", "unread.ARW"]), factor: .noStretch, convert: true)
        XCTAssertEqual(log.entries, [
            "facts iso.ARW lens.ARW unread.ARW", "convert iso.ARW", "convert lens.ARW", "convert unread.ARW",
        ])
        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.convertedByAdobe], [3, 0, 3])
        XCTAssertEqual(summary.notes, [], "Adobe's DNG needs no note")
    }

    // dnglab is not the backup of the backup.
    func testWithNoFullMatchAndBothInstalledAnAdobeThatFailsIsNotFollowedByDnglab() {
        facts.facts = ["lens.ARW": .lens]
        converter.fail = ["lens.ARW"]
        let summary = job(withDnglab: true).run(snapshot(dngs: [], pending: ["lens.ARW"]), factor: factor,
                                                convert: true)
        XCTAssertEqual(log.entries, ["facts lens.ARW", "convert lens.ARW"])
        XCTAssertEqual([summary.converted, summary.failed], [0, 1])
        XCTAssertEqual(summary.notes, [FileNote(name: "lens.ARW", kind: .notConverted, message: "Not converted.",
                                                detail: "made no DNG")])
    }

    // No full match, and dnglab alone: converted, with the note. The file is
    // tagged as every converted file is.
    func testWithNoFullMatchAndDnglabAloneTheARWIsConvertedWithANote() {
        facts.facts = ["lens.ARW": .lens, "iso.ARW": .iso1250, "full.ARW": .adapted]
        let summary = job(withConverter: false, withDnglab: true).run(
            snapshot(dngs: [], pending: ["full.ARW", "iso.ARW", "lens.ARW", "unread.ARW"]),
            factor: factor, convert: true)
        XCTAssertEqual(conversionLog, [
            "facts full.ARW iso.ARW lens.ARW unread.ARW",
            "dnglab full.ARW", "dnglab iso.ARW", "dnglab lens.ARW", "dnglab unread.ARW",
        ])
        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.convertedByAdobe], [4, 4, 0])
        XCTAssertEqual([summary.set, summary.failed, summary.blocked, summary.unconvertedARWs], [4, 0, 0, 0])
        let ending = "Install Adobe DNG Converter for the same file that Lightroom makes."
        XCTAssertEqual(summary.notes, [
            FileNote(name: "iso.dng", kind: .convertedUnmatched,
                     message: "Converted. The levels are dnglab's own. \(ending)",
                     detail: "The table of Adobe's values has no row for ISO 1250."),
            FileNote(name: "lens.dng", kind: .convertedUnmatched,
                     message: "Converted. The DNG has no built-in lens correction. \(ending)",
                     detail: "The ARW holds lens-correction data, and dnglab does not write it into the DNG."),
            FileNote(name: "unread.dng", kind: .convertedUnmatched,
                     message: "Converted. The levels are dnglab's own. \(ending)",
                     detail: "The camera model could not be read from the ARW."),
        ], "no note for the full match")
        XCTAssertFalse(summary.needsAttention, "converted, not failed and not blocked")
        XCTAssertEqual(dnglab.facts["unread.ARW"], ARWFacts.none)
    }

    // The note of the conversion comes before the note of the tag step.
    func testADNGWithNoFullMatchThatThenFailsItsTagHasBothNotes() {
        facts.facts = ["lens.ARW": .lens]
        tag.failWrites = ["lens.dng"]
        let summary = job(withConverter: false, withDnglab: true)
            .run(snapshot(dngs: [], pending: ["lens.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(summary.notes.map(\.kind), [.convertedUnmatched, .failed])
        XCTAssertEqual(summary.notes.map(\.name), ["lens.dng", "lens.dng"])
        XCTAssertEqual([summary.converted, summary.failed], [1, 1])
    }

    // With Adobe alone, no fact changes the choice, so no one reads them.
    func testWithAdobeAloneNoFactsAreReadAndEveryARWGoesToAdobe() {
        facts.facts = ["X.ARW": .adapted]
        let summary = job().run(snapshot(dngs: [], pending: ["X.ARW"]), factor: .noStretch, convert: true)
        XCTAssertEqual(log.entries, ["convert X.ARW"])
        XCTAssertEqual([summary.convertedByDnglab, summary.convertedByAdobe], [0, 1])
        XCTAssertEqual(converter.facts, ["X.ARW": ARWFacts.none])
    }

    func testWithNeitherConverterTheARWFilesWaitAndNoFactsAreRead() {
        facts.facts = ["X.ARW": .adapted]
        let summary = job(withConverter: false).run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW"]),
                                                    factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["write 1.5 1 A.dng", "read A.dng", "trash A.dng"])
        XCTAssertEqual([summary.converted, summary.failed, summary.unconvertedARWs, summary.set], [0, 0, 1, 1])
        XCTAssertEqual(summary.notes, [], "a missing converter is not a failed file")
    }

    func testARunThatConvertsNothingReadsNoFacts() {
        let state = snapshot(dngs: [dng("A.dng", at: 1.5)], pending: ["X.ARW"])
        _ = job(withDnglab: true).run(state, factor: factor, convert: false)
        _ = job(withDnglab: true).run(state, factor: .noStretch, convert: true, remove: true)
        _ = job(withDnglab: true).run(snapshot(dngs: [dng("A.dng", at: 1.5)]), factor: factor, convert: true)
        _ = job(withDnglab: true).run(snapshot(dngs: [], pending: ["X.ARW"], writable: false), factor: factor,
                                      convert: true)
        XCTAssertFalse(log.entries.contains { $0.hasPrefix("facts") || $0.hasPrefix("dnglab") }, "\(log.entries)")
    }

    // Three files, three ways: the two counts add up to `converted`.
    func testEachConversionIsCountedForTheConverterThatMadeTheDNG() {
        facts.facts = ["X.ARW": .adapted, "Y.ARW": .lens, "Z.ARW": .adapted]
        dnglab.fail = ["Z.ARW"]
        let summary = job(withDnglab: true).run(snapshot(dngs: [], pending: ["X.ARW", "Y.ARW", "Z.ARW"]),
                                                factor: .noStretch, convert: true)
        XCTAssertEqual(log.entries, [
            "facts X.ARW Y.ARW Z.ARW", "dnglab X.ARW", "convert Y.ARW", "dnglab Z.ARW", "convert Z.ARW",
        ])
        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.convertedByAdobe], [3, 1, 2])
        XCTAssertEqual([summary.skipped, summary.failed, summary.unconvertedARWs], [3, 0, 0])
    }

    // A DNG appeared after the scan. Each converter refuses the name with the
    // same sentence, and the note says it once.
    func testANameThatBothConvertersRefuseGivesOneLine() {
        facts.facts = ["X.ARW": .adapted]
        dnglab.refuse = ["X.ARW"]
        converter.refuse = ["X.ARW"]
        let summary = job(withDnglab: true).run(snapshot(dngs: [], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["facts X.ARW", "dnglab X.ARW", "convert X.ARW"], "nothing is moved")
        XCTAssertEqual(summary.notes, [FileNote(name: "X.ARW", kind: .notConverted, message: "Not converted.",
                                                detail: "A DNG with this name exists already. Not converted.")])
        XCTAssertEqual(summary.failed, 1)
    }

    // The Trash refused dnglab's partial DNG, so the name is taken when
    // Adobe DNG Converter is asked. Both lines stay: each says its own thing.
    func testARefusedTrashForTheDnglabPartialNamesTheFileAndAdobeThenRefusesTheName() {
        facts.facts = ["X.ARW": .adapted]
        dnglab.failWithPartial = ["X.ARW"]
        converter.refuse = ["X.ARW"]
        backups.trashFileError = NamedError(text: "The Trash refused it.")
        let summary = job(withDnglab: true).run(snapshot(dngs: [], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["facts X.ARW", "dnglab X.ARW", "trashFile X.dng", "convert X.ARW"])
        XCTAssertEqual(summary.notes.map(\.detail), [
            "dnglab returned 1. A partial DNG, X.dng, is beside the ARW. Delete it, then run again.\n"
                + "A DNG with this name exists already. Not converted.",
        ])
    }

    // The second lock holds for each converter's partial DNG.
    func testTheSecondLockHoldsForAPartialDNGThatDnglabReports() {
        facts.facts = ["X.ARW": .adapted]
        dnglab.failWithPartial = ["X.ARW"]
        dnglab.reportedPartial = folder.appendingPathComponent("A.dng")
        let summary = job(withConverter: false, withDnglab: true)
            .run(snapshot(dngs: [dng("A.dng", at: 1.5)], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["facts X.ARW", "dnglab X.ARW"], "no file was moved")
        XCTAssertEqual(summary.notes.map(\.detail), [
            "dnglab returned 1. "
                + "A file, A.dng, was reported as the partial DNG. It is not this run's file, and it was not moved.",
        ])
    }

    // One step for each ARW, whatever the number of converters that it took.
    func testProgressCountsOneStepForAnARWThatTookTwoConverters() {
        facts.facts = ["X.ARW": .adapted, "Y.ARW": .adapted]
        dnglab.fail = ["X.ARW", "Y.ARW"]
        converter.fail = ["Y.ARW"]
        var updates: [RunProgress] = []
        _ = job(withDnglab: true).run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW", "Y.ARW"]), factor: factor,
                                      convert: true) { updates.append($0) }
        XCTAssertEqual(updates.map(\.name), ["X.ARW", "Y.ARW", "A.dng", "X.dng"])
        XCTAssertEqual(updates.map(\.completed), [1, 2, 3, 4])
        XCTAssertEqual(updates.map(\.total), [5, 4, 4, 4], "Y.ARW made no DNG, so its tag step is gone")
    }

    func testCancelDuringADnglabConversionStopsBeforeTheNextARW() {
        facts.facts = ["X.ARW": .adapted, "Y.ARW": .adapted]
        let flag = CancelFlag()
        dnglab.onConvert = { flag.cancel() }
        let summary = job(withDnglab: true).run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW", "Y.ARW"]),
                                                factor: factor, convert: true, cancel: flag)
        XCTAssertEqual(log.entries, ["facts X.ARW Y.ARW", "dnglab X.ARW"])
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual([summary.convertedByDnglab, summary.unconvertedARWs, summary.set], [1, 1, 0])
    }

    // A cancel arrives while dnglab works on an ARW, and dnglab fails. Adobe
    // DNG Converter is the next converter of that ARW, and it must not
    // start: the person asked the run to stop. The partial DNG still goes
    // to the Trash, and the ARW is listed with dnglab's words.
    func testACancelWhileDnglabFailsDoesNotStartAdobeForTheSameARW() {
        facts.facts = ["X.ARW": .adapted, "Y.ARW": .adapted]
        let flag = CancelFlag()
        dnglab.failWithPartial = ["X.ARW"]
        dnglab.onConvert = { flag.cancel() }
        var updates: [RunProgress] = []
        let summary = job(withDnglab: true).run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW", "Y.ARW"]),
                                                factor: factor, convert: true, cancel: flag) { updates.append($0) }
        XCTAssertEqual(log.entries, ["facts X.ARW Y.ARW", "dnglab X.ARW", "trashFile X.dng"],
                       "no Adobe DNG Converter, no next ARW, no tag")
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual([summary.converted, summary.failed, summary.unconvertedARWs, summary.set], [0, 1, 2, 0])
        XCTAssertEqual(summary.notes, [FileNote(
            name: "X.ARW", kind: .notConverted, message: "Not converted.",
            detail: "dnglab returned 1. The partial DNG was moved to the Trash.")])
        XCTAssertEqual(updates.map(\.name), ["X.ARW"])
    }

    // The same on the last ARW, with no DNG to tag. Nothing comes after the
    // ARW, and the run is still stopped: a converter was left untried.
    func testACancelWhileDnglabFailsOnTheLastARWIsAStoppedRun() {
        facts.facts = ["X.ARW": .adapted]
        let flag = CancelFlag()
        dnglab.fail = ["X.ARW"]
        dnglab.onConvert = { flag.cancel() }
        let summary = job(withDnglab: true).run(snapshot(dngs: [], pending: ["X.ARW"]), factor: factor,
                                                convert: true, cancel: flag)
        XCTAssertEqual(log.entries, ["facts X.ARW", "dnglab X.ARW"])
        XCTAssertTrue(summary.cancelled, "Adobe DNG Converter was not tried, so work is left undone")
        XCTAssertEqual([summary.converted, summary.failed, summary.unconvertedARWs], [0, 1, 1])
        XCTAssertEqual(summary.notes.map(\.detail), ["made no DNG"])
    }

    // With dnglab alone there is no next converter. The cancel then follows
    // the rule of every last file: nothing is left undone.
    func testACancelWhileDnglabFailsWithNoOtherConverterLeavesNothingUntried() {
        facts.facts = ["X.ARW": .adapted]
        let flag = CancelFlag()
        dnglab.fail = ["X.ARW"]
        dnglab.onConvert = { flag.cancel() }
        let summary = job(withConverter: false, withDnglab: true)
            .run(snapshot(dngs: [], pending: ["X.ARW"]), factor: factor, convert: true, cancel: flag)
        XCTAssertFalse(summary.cancelled)
        XCTAssertEqual([summary.failed, summary.unconvertedARWs], [1, 1])
    }

    // The whole path on real files with the real `DnglabConverter` on a fake
    // runner: dnglab leaves a cut-off DNG and is ended by a signal, the file
    // moves to the injected Trash, and Adobe DNG Converter then converts.
    func testACutOffDnglabDNGReallyMovesToTheInjectedTrashAndAdobeThenConverts() throws {
        let shoot = try makeTemporaryFolder()
        defer { removeTemporaryFolder(shoot) }
        let trash = shoot.deletingLastPathComponent().appendingPathComponent("Test trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let arw = shoot.appendingPathComponent("a.ARW")
        try Data("raw bytes".utf8).write(to: arw)
        let dngPath = shoot.appendingPathComponent("a.dng").path

        let dnglabRunner = FakeRunner()
        dnglabRunner.handler = { _ in
            FileManager.default.createFile(atPath: dngPath, contents: Data("II*".utf8))
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        dnglabRunner.failure = ProcessSignalError(signal: 9, stdout: "", stderr: "")
        let adobeRunner = FakeRunner()
        adobeRunner.handler = { _ in
            FileManager.default.createFile(atPath: dngPath, contents: Data("Adobe's DNG".utf8))
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        facts.facts = ["a.ARW": .adapted]
        let tool = URL(fileURLWithPath: "/nonexistent/tool")
        let converters = RawConverters(
            dnglab: DnglabConverter(executable: tool, exiftool: tool, runner: dnglabRunner),
            adobe: AdobeConverter(executable: tool, runner: adobeRunner), facts: facts)
        let files = try FileBackups.fromEnvironment([FileBackups.testFolderVariable: trash.path]).backups

        let summary = DesqueezeJob(tag: tag, converters: converters, backups: files).run(
            FolderSnapshot(folder: shoot, dngs: [], pendingARWs: [arw], orphanBackups: [], isWritable: true),
            factor: .noStretch, convert: true)

        XCTAssertEqual(dnglabRunner.calls.count, 1, "no match write after a signal")
        XCTAssertEqual(adobeRunner.calls.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), ["a.dng"])
        XCTAssertEqual(try Data(contentsOf: trash.appendingPathComponent("a.dng")), Data("II*".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: dngPath)), Data("Adobe's DNG".utf8))
        XCTAssertEqual(try Data(contentsOf: arw), Data("raw bytes".utf8))
        XCTAssertEqual([summary.converted, summary.convertedByAdobe, summary.failed], [1, 1, 0])
        XCTAssertEqual(summary.notes, [])
    }

    func testWithNoConverterTheARWFilesWaitAndTheDNGFilesRun() {
        let summary = job(withConverter: false).run(
            snapshot(dngs: [dng("A.dng")], pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["write 1.5 1 A.dng", "read A.dng", "trash A.dng"])
        XCTAssertEqual(summary.converted, 0)
        XCTAssertEqual(summary.set, 1)
    }

    func testCancelStopsBeforeTheNextFile() {
        let flag = CancelFlag()
        tag.onWrite = { flag.cancel() }
        let summary = job().run(snapshot(dngs: [dng("A.dng"), dng("B.dng")]), factor: factor,
                                convert: true, cancel: flag)
        XCTAssertEqual(log.entries, ["write 1.5 1 A.dng", "read A.dng", "trash A.dng"])
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(summary.set, 1)
    }

    func testCancelDuringTheConvertPhaseStopsBeforeTheNextARW() {
        let flag = CancelFlag()
        converter.onConvert = { flag.cancel() }
        let summary = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW", "Y.ARW"]), factor: factor,
                                convert: true, cancel: flag)
        XCTAssertEqual(log.entries, ["convert X.ARW"])
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.set, 0)
    }

    func testCancelDuringTheLastConversionStopsBeforeTheFirstTag() {
        let flag = CancelFlag()
        converter.onConvert = { flag.cancel() }
        let summary = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW"]), factor: factor,
                                convert: true, cancel: flag)
        XCTAssertEqual(log.entries, ["convert X.ARW"])
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.set, 0)
    }

    // `cancelled` means the run left work undone (design 12.1). The flag is
    // read before each file, never after the last one.
    func testCancelDuringTheLastTagLeavesNothingUndoneSoTheRunIsComplete() {
        let flag = CancelFlag()
        tag.onWrite = { if self.log.entries.contains("write 1.5 1 B.dng") { flag.cancel() } }
        let summary = job().run(snapshot(dngs: [dng("A.dng"), dng("B.dng")]), factor: factor,
                                convert: true, cancel: flag)
        XCTAssertTrue(flag.isCancelled, "the cancel did arrive, during the last file")
        XCTAssertFalse(summary.cancelled)
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(log.entries, [
            "write 1.5 1 A.dng", "read A.dng", "trash A.dng",
            "write 1.5 1 B.dng", "read B.dng", "trash B.dng",
        ])
    }

    func testCancelDuringTheLastTagOfAConvertedFileLeavesNothingUndone() {
        let flag = CancelFlag()
        tag.onWrite = { if self.log.entries.contains("write 1.5 1 X.dng") { flag.cancel() } }
        let summary = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW"]), factor: factor,
                                convert: true, cancel: flag)
        XCTAssertFalse(summary.cancelled)
        XCTAssertEqual([summary.converted, summary.set, summary.failed, summary.unconvertedARWs], [1, 2, 0, 0])
    }

    func testCancelDuringTheLastConversionWithDNGFilesToTagIsStopped() {
        let flag = CancelFlag()
        converter.onConvert = { if self.log.entries.contains("convert Y.ARW") { flag.cancel() } }
        let summary = job().run(snapshot(dngs: [dng("A.dng"), dng("B.dng")], pending: ["X.ARW", "Y.ARW"]),
                                factor: factor, convert: true, cancel: flag)
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(summary.converted, 2)
        XCTAssertEqual(summary.set, 0, "every DNG was still to tag")
        XCTAssertEqual(log.entries, ["convert X.ARW", "convert Y.ARW"])
    }

    func testTheJobDoesNotTouchAnOrphanBackup() {
        let summary = job().run(snapshot(dngs: [dng("A.dng")], orphans: ["gone.dng_original"]),
                                factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["write 1.5 1 A.dng", "read A.dng", "trash A.dng"])
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.failed, 0)
    }

    func testAReadOnlyFolderChangesNothing() {
        let summary = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW"], writable: false),
                                factor: factor, convert: true)
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(summary.notes.map(\.message), ["This folder is read-only. No file was changed."])
    }

    func testProgressCountsEveryStepUpToTheTotal() {
        var updates: [RunProgress] = []
        _ = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW"]), factor: factor, convert: true) {
            updates.append($0)
        }
        XCTAssertEqual(updates.map(\.completed), [1, 2, 3])
        XCTAssertEqual(updates.map(\.total), [3, 3, 3])
        XCTAssertEqual(updates.map(\.name), ["X.ARW", "A.dng", "X.dng"])
    }

    // A failed conversion makes no DNG, so the run loses that file's tag step.
    func testAFailedConversionTakesItsTagStepOutOfTheTotal() {
        converter.fail = ["X.ARW"]
        var updates: [RunProgress] = []
        _ = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW", "Y.ARW"]), factor: factor, convert: true) {
            updates.append($0)
        }
        XCTAssertEqual(updates.map(\.completed), [1, 2, 3, 4])
        XCTAssertEqual(updates.map(\.total), [4, 4, 4, 4])
        XCTAssertEqual(updates.map(\.name), ["X.ARW", "Y.ARW", "A.dng", "Y.dng"])
    }

    // MARK: Orphan backups in the result

    func orphanNote(_ backup: String, dng: String) -> FileNote {
        FileNote(name: backup, kind: .orphanBackup,
                 message: "A backup with no DNG beside it. Rename it to \(dng) to get the photo back.",
                 detail: nil)
    }

    func testARunReportsEachOrphanBackupFirstAndTouchesNone() {
        tag.failWrites = ["A.dng"]
        let summary = job().run(
            snapshot(dngs: [dng("A.dng"), dng("B.dng")], pending: ["X.ARW"],
                     orphans: ["gone.dng_original", "LOUD.DNG_ORIGINAL"]),
            factor: factor, convert: true)

        XCTAssertEqual(summary.notes, [
            orphanNote("gone.dng_original", dng: "gone.dng"),
            orphanNote("LOUD.DNG_ORIGINAL", dng: "LOUD.DNG"),
            FileNote(name: "A.dng", kind: .failed, message: "Not changed.", detail: "Error: write failed"),
        ], "the orphans first, in the snapshot's order, then the files")
        XCTAssertEqual(log.entries, [
            "convert X.ARW",
            "write 1.5 1 A.dng",
            "write 1.5 1 B.dng", "read B.dng", "trash B.dng",
            "write 1.5 1 X.dng", "read X.dng", "trash X.dng",
        ], "no call names an orphan")
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.failed, 1)
    }

    func testARemoveRunReportsAnOrphanBackupAndCountsNothingForIt() {
        let summary = job().run(snapshot(dngs: [dng("A.dng", at: 1)], orphans: ["gone.dng_original"]),
                                factor: .noStretch, convert: false)
        XCTAssertEqual(summary.notes, [orphanNote("gone.dng_original", dng: "gone.dng")])
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(summary.converted, 0)
        XCTAssertEqual(summary.set, 0)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.failed, 0)
    }

    func testAFolderWithOnlyAnOrphanBackupStillReportsIt() {
        let summary = job().run(snapshot(dngs: [], orphans: ["gone.dng_original"]), factor: factor, convert: true)
        var expected = RunSummary()
        expected.notes = [orphanNote("gone.dng_original", dng: "gone.dng")]
        XCTAssertEqual(summary, expected)
        XCTAssertEqual(log.entries, [])
    }

    // The notes are added before the first file, so a cancel cannot lose them.
    func testACancelledRunStillReportsTheOrphanBackups() {
        let flag = CancelFlag()
        flag.cancel()
        let summary = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW"], orphans: ["gone.dng_original"]),
                                factor: factor, convert: true, cancel: flag)
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(summary.notes, [orphanNote("gone.dng_original", dng: "gone.dng")])
        XCTAssertEqual(log.entries, [])
    }

    func testAReadOnlyFolderKeepsItsOneNoteAndNamesNoOrphan() {
        let summary = job().run(
            snapshot(dngs: [dng("A.dng")], orphans: ["gone.dng_original"], writable: false),
            factor: factor, convert: true)
        XCTAssertEqual(summary.notes, [FileNote(name: "Shoot 1", kind: .folderReadOnly,
                                                message: "This folder is read-only. No file was changed.",
                                                detail: nil)])
        XCTAssertEqual(log.entries, [])
    }

    // MARK: A run from a folder

    // A window that kept an old snapshot made Remove report "skipped" while
    // the photos stayed stretched. `run(folder:)` reads the folder itself.
    func testARunFromAFolderReadsTheFolderAtCallTime() throws {
        let shoot = try makeTemporaryFolder()
        defer { removeTemporaryFolder(shoot) }
        func touch(_ name: String) throws { try Data("x".utf8).write(to: shoot.appendingPathComponent(name)) }

        try touch("A.dng")
        tag.rows = [TagRow(fileName: "A.dng", scale: .noStretch, originalRawFileName: nil)]
        let earlier = try FolderScanner(tag: tag, backups: backups).snapshot(of: shoot)
        XCTAssertEqual(earlier.dngs.map(\.name), ["A.dng"])
        XCTAssertEqual(earlier.dngs.map(\.scale), [.noStretch])
        XCTAssertEqual(earlier.pendingARWs, [])

        // After that scan: A.dng gets the factor, and two files arrive.
        try touch("B.dng")
        try touch("X.ARW")
        tag.rows = [
            TagRow(fileName: "A.dng", scale: Scale(horizontal: 1.5, vertical: 1), originalRawFileName: nil),
            TagRow(fileName: "B.dng", scale: .noStretch, originalRawFileName: nil),
        ]
        log.entries = []

        let summary = try job().run(folder: shoot, factor: factor, convert: true)

        XCTAssertEqual(log.entries, [
            "readFolder",
            "convert X.ARW",
            "write 1.5 1 B.dng", "read B.dng", "trash B.dng",
            "write 1.5 1 X.dng", "read X.dng", "trash X.dng",
        ], "A.dng is at the factor now: no call. B.dng and X.ARW came after the earlier scan.")
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.notes, [])
    }

    func testARunFromAFolderScansAgainOnEveryCall() throws {
        let shoot = try makeTemporaryFolder()
        defer { removeTemporaryFolder(shoot) }
        try Data("x".utf8).write(to: shoot.appendingPathComponent("A.dng"))
        tag.rows = [TagRow(fileName: "A.dng", scale: .noStretch, originalRawFileName: nil)]

        let applied = try job().run(folder: shoot, factor: factor, convert: true)
        XCTAssertEqual(applied.set, 1)

        // What a real scan reads after that run.
        tag.rows = [TagRow(fileName: "A.dng", scale: Scale(horizontal: 1.5, vertical: 1), originalRawFileName: nil)]
        log.entries = []
        let removed = try job().run(folder: shoot, factor: .noStretch, convert: false)

        XCTAssertEqual(log.entries, ["readFolder", "write 1 1 A.dng", "read A.dng", "trash A.dng"])
        XCTAssertEqual(removed.set, 1)
        XCTAssertEqual(removed.skipped, 0)
    }

    func testARunFromAFolderPassesCancelAndProgressOn() throws {
        let shoot = try makeTemporaryFolder()
        defer { removeTemporaryFolder(shoot) }
        for name in ["A.dng", "B.dng"] { try Data("x".utf8).write(to: shoot.appendingPathComponent(name)) }
        tag.rows = ["A.dng", "B.dng"].map { TagRow(fileName: $0, scale: .noStretch, originalRawFileName: nil) }
        let flag = CancelFlag()
        tag.onWrite = { flag.cancel() }
        var updates: [RunProgress] = []

        let summary = try job().run(folder: shoot, factor: factor, convert: true, cancel: flag) { updates.append($0) }

        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(updates, [RunProgress(completed: 1, total: 2, name: "A.dng")])
    }

    func testARunFromAFolderThrowsWhenTheScanFailsAndChangesNothing() throws {
        let shoot = try makeTemporaryFolder()
        defer { removeTemporaryFolder(shoot) }
        let missing = shoot.appendingPathComponent("No such folder")
        XCTAssertThrowsError(try job().run(folder: missing, factor: factor, convert: true))

        try Data("x".utf8).write(to: shoot.appendingPathComponent("A.dng"))
        tag.readFolderError = TagError.toolFailed("Error: exiftool did not start")
        XCTAssertThrowsError(try job().run(folder: shoot, factor: factor, convert: true)) {
            XCTAssertEqual($0 as? TagError, .toolFailed("Error: exiftool did not start"))
        }
        XCTAssertEqual(log.entries, ["readFolder"], "no write after a scan that failed")
    }
}
