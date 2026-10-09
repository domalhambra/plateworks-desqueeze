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

    override func tearDown() { removeTemporaryFolder(folder) }

    func touch(_ name: String) throws {
        try Data("x".utf8).write(to: folder.appendingPathComponent(name))
    }

    func testSnapshotJoinsContentsTagsAndBackups() throws {
        for name in ["a.dng", "renamed 0001.dng", "DSC1.ARW", "DSC2.ARW"] { try touch(name) }
        tag.rows = [
            TagRow(fileName: "a.dng", horizontal: 1.5, vertical: 1, originalRawFileName: nil),
            TagRow(fileName: "renamed 0001.dng", horizontal: 1, vertical: 1, originalRawFileName: "DSC1.ARW"),
        ]
        backups.existing = ["a.dng"]

        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)

        XCTAssertEqual(snapshot.dngs.map(\.name), ["a.dng", "renamed 0001.dng"])
        XCTAssertEqual(snapshot.dngs.map(\.horizontal), [1.5, 1])
        XCTAssertEqual(snapshot.dngs.map(\.hasBackup), [true, false])
        XCTAssertEqual(snapshot.pendingARWs.map(\.lastPathComponent), ["DSC2.ARW"])
        XCTAssertTrue(snapshot.isWritable)
        XCTAssertEqual(snapshot.photoCount, 3)
    }

    func testADNGWithNoRowReadsAsNoStretch() throws {
        try touch("a.dng")
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertEqual(snapshot.dngs.map(\.horizontal), [1])
        XCTAssertEqual(snapshot.dngs.map(\.vertical), [1])
    }

    func testAFolderWithNoDNGCallsExiftoolZeroTimes() throws {
        try touch("DSC1.ARW")
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(snapshot.pendingARWs.count, 1)
        XCTAssertFalse(snapshot.isEmpty)
    }
}
