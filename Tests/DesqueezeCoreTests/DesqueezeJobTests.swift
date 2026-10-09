import XCTest
@testable import DesqueezeCore

final class DesqueezeJobTests: XCTestCase {
    let folder = URL(fileURLWithPath: "/tmp/Shoot 1")
    let factor = SqueezeFactor(1.5)!
    var log: CallLog!
    var backups: FakeBackups!
    var tag: FakeTag!
    var converter: FakeConverter!

    override func setUp() {
        log = CallLog()
        backups = FakeBackups(log: log)
        tag = FakeTag(log: log, backups: backups)
        converter = FakeConverter(log: log)
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

    func job(withConverter: Bool = true) -> DesqueezeJob {
        DesqueezeJob(tag: tag, converter: withConverter ? converter : nil, backups: backups)
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
        let summary = job().run(snapshot(dngs: files, pending: ["X.ARW"]), factor: .noStretch, convert: false)
        XCTAssertEqual(log.entries, ["write 1 1 A.dng", "read A.dng", "trash A.dng"])
        XCTAssertEqual(summary.converted, 0)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.skipped, 1)
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
        XCTAssertFalse(log.entries.contains("write 1.5 1 X.dng"))
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(summary.notes, [FileNote(name: "X.ARW", kind: .notConverted, message: "Not converted.", detail: "made no DNG")])
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
