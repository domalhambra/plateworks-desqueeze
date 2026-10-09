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
        DNGFile(url: folder.appendingPathComponent(name), horizontal: horizontal, vertical: 1,
                originalRawFileName: nil, hasBackup: false)
    }

    func snapshot(dngs: [DNGFile], pending: [String] = [], writable: Bool = true) -> FolderSnapshot {
        FolderSnapshot(folder: folder, dngs: dngs,
                       pendingARWs: pending.map { folder.appendingPathComponent($0) }, isWritable: writable)
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

    func testAFileAlreadyAtTheFactorGetsNoCall() {
        let summary = job().run(snapshot(dngs: [dng("A.dng", at: 1.5)]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.notes, [])
    }

    func testAFileWithAnExistingBackupIsSkippedWithANote() {
        backups.existing = ["A.dng"]
        let summary = job().run(snapshot(dngs: [dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.notes.map(\.name), ["A.dng"])
        XCTAssertTrue(summary.notes[0].message.hasPrefix("Skipped."))
        XCTAssertTrue(backups.existing.contains("A.dng"), "the old backup must stay")
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
        XCTAssertEqual(summary.notes, [FileNote(name: "A.dng", message: "Not changed.", detail: "Error: write failed")])
    }

    func testAFailedCheckRestoresTheBackup() {
        tag.wrongReadBack = ["A.dng"]
        let summary = job().run(snapshot(dngs: [dng("A.dng")]), factor: factor, convert: true)
        XCTAssertEqual(log.entries, ["write 1.5 1 A.dng", "read A.dng", "restore A.dng"])
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.set, 0)
        XCTAssertEqual(summary.notes.map(\.message), ["Not changed. The backup was restored."])
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

    func testAFailedConversionIsReportedAndTheRunContinues() {
        converter.fail = ["X.ARW"]
        let summary = job().run(snapshot(dngs: [dng("A.dng")], pending: ["X.ARW", "Y.ARW"]),
                                factor: factor, convert: true)
        XCTAssertEqual(log.entries.filter { $0.hasPrefix("convert") }, ["convert X.ARW", "convert Y.ARW"])
        XCTAssertFalse(log.entries.contains("write 1.5 1 X.dng"))
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(summary.notes, [FileNote(name: "X.ARW", message: "Not converted.", detail: "made no DNG")])
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
}
