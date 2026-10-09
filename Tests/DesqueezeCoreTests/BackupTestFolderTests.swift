import XCTest
@testable import DesqueezeCore

/// The one way a command line tool can be told to keep away from the Trash.
/// The end-to-end tests of the tools use it. See `FileBackups.fromEnvironment`.
final class BackupTestFolderTests: XCTestCase {
    var folder: URL!
    var discard: URL!
    var dng: URL!
    var backup: URL!

    override func setUpWithError() throws {
        folder = try makeTemporaryFolder()
        discard = folder.deletingLastPathComponent().appendingPathComponent("Discarded backups")
        try FileManager.default.createDirectory(at: discard, withIntermediateDirectories: true)
        dng = folder.appendingPathComponent("one.dng")
        backup = folder.appendingPathComponent("one.dng_original")
    }

    override func tearDown() { removeTemporaryFolder(folder) }

    func environment(_ value: String) -> [String: String] {
        ["PATH": "/usr/bin", FileBackups.testFolderVariable: value]
    }

    /// The backups for the test folder. Throws when the code under test did
    /// not take the folder, so no test here can reach the real Trash.
    func testBackups() throws -> FileBackups {
        let result = try FileBackups.fromEnvironment(environment(discard.path))
        XCTAssertEqual(try XCTUnwrap(result.testFolder).path, discard.path)
        return result.backups
    }

    func discarded() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: discard.path).sorted()
    }

    func testTheVariableHasOneExactName() {
        XCTAssertEqual(FileBackups.testFolderVariable, "DESQUEEZE_TEST_BACKUP_FOLDER")
    }

    func testWithNoVariableTheBackupsGoToTheTrash() throws {
        let result = try FileBackups.fromEnvironment(["PATH": "/usr/bin", "DESQUEEZE_TEST": "1"])
        XCTAssertNil(result.testFolder)
    }

    func testWithTheVariableADiscardedBackupIsMovedToThatFolderAndNotRemoved() throws {
        try Data("the file as it was".utf8).write(to: backup)
        try testBackups().trashBackup(for: dng)

        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try discarded(), ["one.dng_original"])
        XCTAssertEqual(try Data(contentsOf: discard.appendingPathComponent("one.dng_original")),
                       Data("the file as it was".utf8))
    }

    // The Trash keeps both files of one name. So does this folder.
    func testASecondBackupOfTheSameNameIsKeptBesideTheFirst() throws {
        let backups = try testBackups()
        for text in ["first", "second", "third"] {
            try Data(text.utf8).write(to: backup)
            try backups.trashBackup(for: dng)
        }
        XCTAssertEqual(try discarded(), ["one.dng_original", "one.dng_original 2", "one.dng_original 3"])
        XCTAssertEqual(try Data(contentsOf: discard.appendingPathComponent("one.dng_original")), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: discard.appendingPathComponent("one.dng_original 3")), Data("third".utf8))
    }

    func testAMoveThatFailsThrowsAndKeepsTheBackup() throws {
        try Data("old".utf8).write(to: backup)
        let backups = try testBackups()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: discard.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: discard.path) }

        XCTAssertThrowsError(try backups.trashBackup(for: dng))
        XCTAssertEqual(try Data(contentsOf: backup), Data("old".utf8))
    }

    // A value that is wrong must stop the tool. To go on would be to use the
    // real Trash in a test, or a folder that nobody chose.
    func testAValueThatIsNotAnAbsolutePathToAFolderIsRefused() throws {
        let file = folder.appendingPathComponent("a file")
        try Data("x".utf8).write(to: file)
        for value in ["", "1", "relative/folder", file.path, discard.path + "/no such folder"] {
            XCTAssertThrowsError(try FileBackups.fromEnvironment(environment(value)), value) {
                XCTAssertEqual($0 as? FileBackups.TestFolderError, FileBackups.TestFolderError(value: value))
            }
        }
    }
}

final class VersionTests: XCTestCase {
    // The app's version is in project.yml. The tools' version is in the core.
    func testTheToolsAndTheAppHaveTheSameVersion() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("MARKETING_VERSION: \"\(DesqueezeVersion.current)\""),
                      "project.yml and DesqueezeVersion.current must hold the same number")
        XCTAssertEqual(DesqueezeVersion.current, "0.1.0")
    }
}
