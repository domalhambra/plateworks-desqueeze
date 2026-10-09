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
        XCTAssertEqual(seen.url?.path, folder.path + "/one.dng_original")
    }

    func testBackupURLKeepsTheNameAsItIs() {
        let odd = folder.appendingPathComponent("A #1 50%?.DNG")
        XCTAssertEqual(FileBackups.backupURL(for: odd).path, folder.path + "/A #1 50%?.DNG_original")
    }

    func testRestoreWorksWhenTheDNGIsMissing() throws {
        try Data("old".utf8).write(to: backup)
        try FileBackups().restoreBackup(for: dng)
        XCTAssertEqual(try Data(contentsOf: dng), Data("old".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    // In a folder with no ARW files the DNG is the only copy of the photo.
    func testRestoreThrowsAndKeepsTheDNGWhenThereIsNoBackup() throws {
        try Data("new".utf8).write(to: dng)
        XCTAssertThrowsError(try FileBackups().restoreBackup(for: dng))
        XCTAssertEqual(try Data(contentsOf: dng), Data("new".utf8))
    }

    func testRestoreBringsBackTheOriginalCreationDate() throws {
        try Data("new".utf8).write(to: dng)
        try Data("old".utf8).write(to: backup)
        let shotOn = Date(timeIntervalSince1970: 1_577_880_000)
        try FileManager.default.setAttributes([.creationDate: shotOn], ofItemAtPath: backup.path)
        try FileBackups().restoreBackup(for: dng)
        let restored = try FileManager.default.attributesOfItem(atPath: dng.path)[.creationDate] as? Date
        XCTAssertEqual(restored, shotOn)
    }
}

private final class URLBox: @unchecked Sendable {
    var url: URL?
}
