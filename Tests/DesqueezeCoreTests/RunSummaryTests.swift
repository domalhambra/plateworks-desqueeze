import XCTest
@testable import DesqueezeCore

/// What a run reports: the kind of each note, the blocked count, the ARW
/// files it left, and the one line of counts.
final class RunSummaryTests: XCTestCase {
    let factor = SqueezeFactor(1.5)!
    var h: JobHarness!

    override func setUp() { h = JobHarness() }

    // MARK: The kind of each note

    // The raw values are the JSON values. A front end reads them.
    func testTheKindsAreTheSevenNamesOfTheDesign() {
        XCTAssertEqual(FileNote.Kind.allCases.map(\.rawValue), [
            "orphanBackup", "notConverted", "failed", "blockedByBackup", "leftoverBackup", "backupKept",
            "folderReadOnly",
        ])
    }

    func testAnOrphanBackupNoteHasItsKind() {
        let summary = h.job().run(h.snapshot(orphans: ["gone.dng_original"]), factor: factor, convert: true)
        XCTAssertEqual(summary.notes.map(\.kind), [.orphanBackup])
    }

    func testAFailedConversionNoteHasItsKind() {
        h.converter.fail = ["X.ARW"]
        let summary = h.job().run(h.snapshot(pending: ["X.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(summary.notes.map(\.kind), [.notConverted])
    }

    func testEachWayAWriteFailsGivesTheKindFailed() {
        h.tag.failWrites = ["write.dng"]
        h.tag.wrongReadBack = ["check.dng"]
        let summary = h.job().run(h.snapshot(dngs: [h.dng("write.dng"), h.dng("check.dng")]),
                                  factor: factor, convert: true)
        XCTAssertEqual(summary.notes.map(\.message), ["Not changed.", "Not changed. The backup was restored."])
        XCTAssertEqual(summary.notes.map(\.kind), [.failed, .failed])
    }

    func testAFailedRestoreGivesTheKindFailed() {
        h.tag.wrongReadBack = ["A.dng"]
        h.backups.restoreError = NamedError(text: "The volume refused the rename.")
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(summary.notes.map(\.kind), [.failed])
        XCTAssertEqual(summary.failed, 1)
    }

    func testABlockedFileNoteHasItsKindAndSaysBlocked() {
        h.backups.existing = ["A.dng"]
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "A.dng", kind: .blockedByBackup,
            message: "Blocked. An older backup, A.dng_original, is beside this file. Move it away, then run again.",
            detail: nil)])
    }

    func testALeftoverBackupNoteHasItsKindAndTheExactSentence() {
        h.backups.existing = ["A.dng"]
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng", at: 1.5)]), factor: factor, convert: true)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "A.dng", kind: .leftoverBackup,
            message: "Already at this value. A backup, A.dng_original, is beside this file.", detail: nil)])
    }

    func testARefusedTrashNoteHasItsKind() {
        h.backups.trashError = NamedError(text: "The Trash is not here.")
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "A.dng", kind: .backupKept,
            message: "Done. The backup stayed beside the file, because the Trash refused it.",
            detail: "The Trash is not here.")])
    }

    func testAReadOnlyFolderNoteHasItsKind() {
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng")], writable: false), factor: factor, convert: true)
        XCTAssertEqual(summary.notes.map(\.kind), [.folderReadOnly])
    }

    // MARK: Blocked is not skipped

    func testABlockedFileIsNotInTheSkippedCount() {
        h.backups.existing = ["old backup.dng"]
        let files = [h.dng("old backup.dng"), h.dng("at value.dng", at: 1.5), h.dng("new.dng")]
        let summary = h.job().run(h.snapshot(dngs: files), factor: factor, convert: true)
        XCTAssertEqual(summary.blocked, 1)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(h.log.entries, ["write 1.5 1 new.dng", "read new.dng", "trash new.dng"])
    }

    // A file at the value with a leftover backup is skipped: it is at the value.
    func testALeftoverBackupFileIsSkippedNotBlocked() {
        h.backups.existing = ["A.dng"]
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng", at: 1.5)]), factor: factor, convert: true)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.blocked, 0)
    }

    // MARK: The ARW files a run left

    func testARunThatConvertsEveryPendingARWLeavesNone() {
        let summary = h.job().run(h.snapshot(pending: ["X.ARW", "Y.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(summary.converted, 2)
        XCTAssertEqual(summary.unconvertedARWs, 0)
    }

    func testWithNoConverterARunLeavesEveryPendingARW() {
        let summary = h.job(withConverter: false).run(
            h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(summary.unconvertedARWs, 2)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.failed, 0, "a missing converter is not a failed file")
        XCTAssertEqual(summary.notes, [])
    }

    func testARunToldNotToConvertLeavesEveryPendingARW() {
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"]),
                                  factor: factor, convert: false)
        XCTAssertEqual(summary.unconvertedARWs, 2)
        XCTAssertEqual(summary.converted, 0)
        XCTAssertEqual(h.log.entries, ["write 1.5 1 A.dng", "read A.dng", "trash A.dng"])
    }

    func testRemoveNeverConvertsAndReportsNoARW() {
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng", at: 1.5)], pending: ["X.ARW", "Y.ARW"]),
                                  factor: .noStretch, convert: false)
        XCTAssertEqual(summary.unconvertedARWs, 0)
        XCTAssertEqual(summary.set, 1)
    }

    // The ARW is in `failed`, with a note. It also has no DNG, so it is left.
    func testAFailedConversionIsAlsoAnARWTheRunLeft() {
        h.converter.fail = ["X.ARW"]
        let summary = h.job().run(h.snapshot(pending: ["X.ARW", "Y.ARW"]), factor: factor, convert: true)
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.unconvertedARWs, 1)
    }

    func testAStoppedRunLeavesTheARWFilesItDidNotReach() {
        let flag = CancelFlag()
        h.converter.onConvert = { flag.cancel() }
        let summary = h.job().run(h.snapshot(pending: ["X.ARW", "Y.ARW", "Z.ARW"]), factor: factor,
                                  convert: true, cancel: flag)
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.unconvertedARWs, 2)
    }

    func testAReadOnlyFolderLeavesEveryPendingARWAndRemoveStillReportsNone() {
        let state = h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW"], writable: false)
        XCTAssertEqual(h.job().run(state, factor: factor, convert: true).unconvertedARWs, 1)
        XCTAssertEqual(h.job().run(state, factor: .noStretch, convert: false).unconvertedARWs, 0)
        XCTAssertEqual(h.log.entries, [])
    }

    // MARK: The one line of counts

    func line(_ change: (inout RunSummary) -> Void) -> String {
        var summary = RunSummary()
        change(&summary)
        return summary.countsLine
    }

    func testTheCountsLineOfTheDesign() {
        XCTAssertEqual(line { $0.converted = 1; $0.set = 3 }, "1 converted · 3 set · 0 skipped · 0 failed")
    }

    func testTheCountsLineLeavesOutConvertedAndBlockedAtZero() {
        XCTAssertEqual(line { $0.set = 2; $0.skipped = 4; $0.failed = 1 }, "2 set · 4 skipped · 1 failed")
    }

    func testTheCountsLineShowsBlockedBetweenSkippedAndFailedWhenItIsNotZero() {
        XCTAssertEqual(line { $0.set = 2; $0.blocked = 3 }, "2 set · 0 skipped · 3 blocked · 0 failed")
    }

    func testTheCountsLineEndsWithStoppedAfterACancel() {
        XCTAssertEqual(line { $0.set = 1; $0.blocked = 1; $0.cancelled = true },
                       "1 set · 0 skipped · 1 blocked · 0 failed · stopped")
    }
}
