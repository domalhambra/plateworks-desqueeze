import XCTest
@testable import DesqueezeCore

final class BackupsTests: XCTestCase {
    var folder: URL!
    var dng: URL!
    var backup: URL!

    override func setUpWithError() throws {
        folder = try makeTemporaryFolder()
        dng = folder.appendingPathComponent("one.dng")
        backup = folder.appendingPathComponent("one.dng_original")
    }

    override func tearDown() { removeTemporaryFolder(folder) }

    func testBackupURLAppendsOriginalToTheFullName() {
        XCTAssertEqual(FileBackups.backupURL(for: dng).lastPathComponent, "one.dng_original")
        XCTAssertEqual(FileBackups.backupURL(for: dng).deletingLastPathComponent().path, folder.path)
    }

    func testBackupExistsOnlyWhenTheFileIsThere() throws {
        let backups = FileBackups()
        XCTAssertFalse(backups.backupExists(for: dng))
        try Data("old".utf8).write(to: backup)
        XCTAssertTrue(backups.backupExists(for: dng))
    }

    func testRestorePutsTheOldBytesBackAndConsumesTheBackup() throws {
        try Data("new".utf8).write(to: dng)
        try Data("old".utf8).write(to: backup)
        try FileBackups().restoreBackup(for: dng)
        XCTAssertEqual(try Data(contentsOf: dng), Data("old".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testTrashSendsTheBackupToTheInjectedFunction() throws {
        let seen = URLBox()
        let backups = FileBackups(trash: { seen.url = $0 })
        try backups.trashBackup(for: dng)
        XCTAssertEqual(seen.url?.lastPathComponent, "one.dng_original")
    }
}

private final class URLBox: @unchecked Sendable {
    var url: URL?
}
