import XCTest
@testable import DesqueezeCore

final class FolderScannerTests: XCTestCase {
    var folder: URL!
    var log: CallLog!
    var backups: FakeBackups!
    var tag: FakeTag!

    override func setUpWithError() throws {
        folder = try makeTemporaryFolder()
        log = CallLog()
        backups = FakeBackups(log: log)
        tag = FakeTag(log: log, backups: backups)
    }

    override func tearDown() {
        // A test may have locked the folder. Unlock it, or it cannot be removed.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        removeTemporaryFolder(folder)
    }

    func touch(_ name: String) throws {
        try Data("x".utf8).write(to: folder.appendingPathComponent(name))
    }

    func testSnapshotJoinsContentsTagsAndBackups() throws {
        for name in ["a.dng", "renamed 0001.dng", "DSC1.ARW", "DSC2.ARW"] { try touch(name) }
        tag.rows = [
            TagRow(fileName: "a.dng", scale: Scale(horizontal: 1.5, vertical: 1), originalRawFileName: nil),
            TagRow(fileName: "renamed 0001.dng", scale: .noStretch, originalRawFileName: "DSC1.ARW"),
        ]
        backups.existing = ["a.dng"]

        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)

        XCTAssertEqual(snapshot.dngs.map(\.name), ["a.dng", "renamed 0001.dng"])
        XCTAssertEqual(snapshot.dngs.map(\.scale?.horizontal), [1.5, 1])
        XCTAssertEqual(snapshot.dngs.map(\.hasBackup), [true, false])
        XCTAssertEqual(snapshot.pendingARWs.map(\.lastPathComponent), ["DSC2.ARW"])
        XCTAssertTrue(snapshot.isWritable)
        XCTAssertEqual(snapshot.photoCount, 3)
    }

    // exiftool gave no row, or a row with no value. Neither is "no stretch".
    func testADNGWithNoRowOrNoValueHasAnUnknownScale() throws {
        for name in ["no row.dng", "no value.dng", "read.dng"] { try touch(name) }
        tag.rows = [
            TagRow(fileName: "no value.dng", scale: nil, originalRawFileName: nil),
            TagRow(fileName: "read.dng", scale: .noStretch, originalRawFileName: nil),
        ]
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertEqual(snapshot.dngs.map(\.name), ["no row.dng", "no value.dng", "read.dng"])
        XCTAssertEqual(snapshot.dngs.map(\.scale), [nil, nil, .noStretch])
    }

    // exiftool prints a control character of a file name as a period
    // (`ExiftoolText.printed`), so the row of `tab<TAB>here.dng` is named
    // `tab.here.dng`. The file takes the row that has its printed name.
    func testADNGWithAControlCharacterInItsNameTakesTheRowOfItsPrintedName() throws {
        for name in ["tab\there.dng", "line\nend.dng", "plain.dng"] { try touch(name) }
        tag.rows = [
            TagRow(fileName: "tab.here.dng", scale: Scale(horizontal: 1.5, vertical: 1), originalRawFileName: "a.ARW"),
            TagRow(fileName: "line.end.dng", scale: .noStretch, originalRawFileName: nil),
            TagRow(fileName: "plain.dng", scale: Scale(horizontal: 2, vertical: 1), originalRawFileName: nil),
        ]
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        let byName = Dictionary(uniqueKeysWithValues: snapshot.dngs.map { ($0.name, $0) })
        XCTAssertEqual(byName["tab\there.dng"]?.scale, Scale(horizontal: 1.5, vertical: 1))
        XCTAssertEqual(byName["tab\there.dng"]?.originalRawFileName, "a.ARW")
        XCTAssertEqual(byName["line\nend.dng"]?.scale, .noStretch)
        XCTAssertEqual(byName["plain.dng"]?.scale, Scale(horizontal: 2, vertical: 1))
    }

    // Two files print as one name, so no one can say which row is whose. Both
    // stay unknown: the safe direction, since a write is tried for an
    // unknown scale. That holds with two rows, and with one.
    func testTwoDNGFilesThatPrintAsOneNameBothStayUnknown() throws {
        for name in ["a\tb.dng", "a.b.dng", "other.dng"] { try touch(name) }
        tag.rows = [
            TagRow(fileName: "a.b.dng", scale: .noStretch, originalRawFileName: nil),
            TagRow(fileName: "a.b.dng", scale: Scale(horizontal: 2, vertical: 1), originalRawFileName: nil),
            TagRow(fileName: "other.dng", scale: .noStretch, originalRawFileName: nil),
        ]
        var snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertEqual(snapshot.dngs.map { $0.name + ($0.scale == nil ? " unknown" : " known") }.sorted(),
                       ["a\tb.dng unknown", "a.b.dng unknown", "other.dng known"])

        tag.rows = [TagRow(fileName: "a.b.dng", scale: .noStretch, originalRawFileName: nil)]
        snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertEqual(snapshot.dngs.map(\.scale), [nil, nil, nil], "one row for two files is no row for either")
    }

    // Two rows for one file are not one row either.
    func testTwoRowsForOneDNGLeaveItUnknown() throws {
        try touch("one.dng")
        tag.rows = [
            TagRow(fileName: "one.dng", scale: .noStretch, originalRawFileName: nil),
            TagRow(fileName: "one.dng", scale: .noStretch, originalRawFileName: nil),
        ]
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertEqual(snapshot.dngs.map(\.scale), [nil])
    }

    func testAFolderWithNoDNGCallsExiftoolZeroTimes() throws {
        try touch("DSC1.ARW")
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(snapshot.pendingARWs.count, 1)
        XCTAssertFalse(snapshot.isEmpty)
    }

    func testAFolderThatCannotBeWrittenIsNotWritable() throws {
        try touch("a.dng")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        // The premise: a new file is refused. Without it the test proves nothing.
        XCTAssertThrowsError(try touch("b.dng"))

        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)

        XCTAssertFalse(snapshot.isWritable)
        XCTAssertEqual(snapshot.dngs.map(\.name), ["a.dng"], "a read-only folder still scans")
    }

    func testSnapshotCarriesOrphanBackupsAndCountsNoPhotoForThem() throws {
        for name in ["kept.dng", "kept.dng_original", "gone.dng_original"] { try touch(name) }
        tag.rows = [TagRow(fileName: "kept.dng", scale: .noStretch, originalRawFileName: nil)]

        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)

        XCTAssertEqual(snapshot.orphanBackups.map(\.lastPathComponent), ["gone.dng_original"])
        XCTAssertEqual(snapshot.dngs.map(\.name), ["kept.dng"])
        XCTAssertEqual(snapshot.photoCount, 1)
    }

    // The only thing in the folder is a backup: no photo to run, and still
    // something the user must see. So the folder is not "empty".
    func testAFolderWithOnlyAnOrphanBackupIsNotEmptyAndReportsIt() throws {
        try touch("gone.dng_original")
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertEqual(snapshot.photoCount, 0)
        XCTAssertEqual(snapshot.orphanBackups.map(\.lastPathComponent), ["gone.dng_original"])
        XCTAssertEqual(log.entries, [], "no DNG, so no exiftool call")
    }

    func testAFolderWithNothingToReportIsEmpty() throws {
        try touch("notes.txt")
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertTrue(snapshot.isEmpty)
    }

    // exiftool stopped between its two renames. The photo's DNG is waiting as
    // frame.dng_original, so frame.ARW must not go to the converter.
    func testAnOrphanBackupKeepsItsARWOutOfThePendingList() throws {
        for name in ["frame.dng_original", "frame.ARW", "other.ARW"] { try touch(name) }
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertEqual(snapshot.orphanBackups.map(\.lastPathComponent), ["frame.dng_original"])
        XCTAssertEqual(snapshot.pendingARWs.map(\.lastPathComponent), ["other.ARW"])
    }

    // One photo, one note. The run converts nothing and counts no ARW as left:
    // the ARW is claimed, so it is not pending.
    func testARunOnAnOrphanBackupAndItsARWConvertsNothingAndGivesOneNote() throws {
        for name in ["frame.dng_original", "frame.ARW"] { try touch(name) }
        let job = DesqueezeJob(tag: tag, converters: RawConverters(dnglab: nil, adobe: FakeConverter(log: log),
                                                                   facts: nil), backups: backups)

        let summary = try job.run(folder: folder, factor: SqueezeFactor(1.5)!, convert: true, trashOriginals: false)

        XCTAssertEqual(log.entries, [], "no conversion, and no exiftool call")
        var expected = RunSummary()
        expected.notes = [FileNote(
            name: "frame.dng_original", kind: .orphanBackup,
            message: "A backup with no DNG beside it. Rename it to frame.dng to get the photo back.", detail: nil)]
        XCTAssertEqual(summary, expected)
    }
}
