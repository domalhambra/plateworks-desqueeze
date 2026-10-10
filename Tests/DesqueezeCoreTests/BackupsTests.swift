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

    /// Backups that fail the test if anything tries to discard a file. No
    /// test here may reach the real Trash.
    var backups: FileBackups {
        FileBackups(trash: { _ in XCTFail("this test must not discard a backup") })
    }

    // The Trash has a name, and no initializer falls back to it. Evaluating
    // the constant moves nothing. The initializer has no default, so a call
    // with no argument does not compile.
    func testTheRealTrashIsANamedConstant() {
        let systemTrash: BackupHandling = FileBackups.systemTrash
        XCTAssertNotNil(systemTrash as? FileBackups)
    }

    func testBackupURLAppendsOriginalToTheFullName() {
        XCTAssertEqual(FileBackups.backupURL(for: dng).lastPathComponent, "one.dng_original")
        XCTAssertEqual(FileBackups.backupURL(for: dng).deletingLastPathComponent().path, folder.path)
    }

    func testBackupExistsOnlyWhenTheFileIsThere() throws {
        XCTAssertFalse(backups.backupExists(for: dng))
        try Data("old".utf8).write(to: backup)
        XCTAssertTrue(backups.backupExists(for: dng))
    }

    func testRestorePutsTheOldBytesBackAndConsumesTheBackup() throws {
        try Data("new".utf8).write(to: dng)
        try Data("old".utf8).write(to: backup)
        try backups.restoreBackup(for: dng)
        XCTAssertEqual(try Data(contentsOf: dng), Data("old".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testTrashSendsTheBackupToTheInjectedFunction() throws {
        let seen = URLBox()
        let backups = FileBackups(trash: { seen.url = $0 })
        try backups.trashBackup(for: dng)
        XCTAssertEqual(seen.url?.path, folder.path + "/one.dng_original")
    }

    // The partial DNG of a failed conversion goes where a backup goes, as it is.
    func testTrashFileSendsTheFileItselfToTheInjectedFunction() throws {
        let seen = URLBox()
        let backups = FileBackups(trash: { seen.url = $0 })
        try backups.trashFile(dng)
        XCTAssertEqual(seen.url?.path, folder.path + "/one.dng")
    }

    func testBackupURLKeepsTheNameAsItIs() {
        let odd = folder.appendingPathComponent("A #1 50%?.DNG")
        XCTAssertEqual(FileBackups.backupURL(for: odd).path, folder.path + "/A #1 50%?.DNG_original")
    }

    func testRestoreWorksWhenTheDNGIsMissing() throws {
        try Data("old".utf8).write(to: backup)
        try backups.restoreBackup(for: dng)
        XCTAssertEqual(try Data(contentsOf: dng), Data("old".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    // In a folder with no ARW files the DNG is the only copy of the photo.
    func testRestoreThrowsAndKeepsTheDNGWhenThereIsNoBackup() throws {
        try Data("new".utf8).write(to: dng)
        XCTAssertThrowsError(try backups.restoreBackup(for: dng))
        XCTAssertEqual(try Data(contentsOf: dng), Data("new".utf8))
    }

    func testRestoreBringsBackTheOriginalCreationDate() throws {
        try Data("new".utf8).write(to: dng)
        try Data("old".utf8).write(to: backup)
        let shotOn = Date(timeIntervalSince1970: 1_577_880_000)
        try FileManager.default.setAttributes([.creationDate: shotOn], ofItemAtPath: backup.path)
        try backups.restoreBackup(for: dng)
        let restored = try FileManager.default.attributesOfItem(atPath: dng.path)[.creationDate] as? Date
        XCTAssertEqual(restored, shotOn)
    }
}

private final class URLBox: @unchecked Sendable {
    var url: URL?
}
