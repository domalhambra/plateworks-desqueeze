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
    // something the user must see.
    func testAFolderWithOnlyAnOrphanBackupIsEmptyAndStillReportsIt() throws {
        try touch("gone.dng_original")
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertEqual(snapshot.orphanBackups.map(\.lastPathComponent), ["gone.dng_original"])
        XCTAssertEqual(log.entries, [], "no DNG, so no exiftool call")
    }
}
