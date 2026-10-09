import Foundation

/// The backup that exiftool leaves beside a file it wrote: `<name>_original`.
public protocol BackupHandling: Sendable {
    func backupExists(for dng: URL) -> Bool
    /// Moves the backup to the Trash.
    func trashBackup(for dng: URL) throws
    /// Replaces the DNG with its backup. The backup file is consumed.
    func restoreBackup(for dng: URL) throws
}

public struct FileBackups: BackupHandling {
    private let trash: @Sendable (URL) throws -> Void

    /// - Parameter trash: how to discard a backup. The default moves it to the
    ///   Trash. Tests inject a function, so they never fill the real Trash.
    public init(trash: @escaping @Sendable (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }) {
        self.trash = trash
    }

    public static func backupURL(for dng: URL) -> URL {
        URL(fileURLWithPath: dng.path + "_original")
    }

    public func backupExists(for dng: URL) -> Bool {
        FileManager.default.fileExists(atPath: Self.backupURL(for: dng).path)
    }

    public func trashBackup(for dng: URL) throws {
        try trash(Self.backupURL(for: dng))
    }

    /// One atomic `rename`. The restored file is the backup itself, with its
    /// own creation date and permissions. `FileManager.replaceItemAt` keeps the
    /// replaced file's creation date, which is the time of the failed write.
    /// With no backup this throws and leaves the DNG as it is.
    public func restoreBackup(for dng: URL) throws {
        guard rename(Self.backupURL(for: dng).path, dng.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

/// A place for discarded backups that is not the Trash. For tests only.
///
/// The end-to-end tests start the built command line tools as child
/// processes, so they cannot inject a function as the unit tests do. They set
/// one environment variable instead. The rules that keep a person from
/// starting this by accident:
///
/// - It is an environment variable with a long name, not a flag. No help text
///   names it, and no shell sets it.
/// - Its value must be an absolute path to a folder that exists. Any other
///   value is an error, and the tool stops before it reads a photo folder.
///   So `=1`, or an empty value, starts nothing.
/// - A backup is moved to that folder. Nothing is ever removed, and no file
///   there is replaced. The worst case is a backup in a folder that the
///   person named, in place of the Trash.
/// - A front end that takes the folder must say so on standard error.
/// - Only `fromEnvironment` reads the variable. The window never calls it.
extension FileBackups {
    /// The environment variable that names the folder.
    public static let testFolderVariable = "DESQUEEZE_TEST_BACKUP_FOLDER"

    /// The variable is set, and its value is not an absolute path to a folder.
    public struct TestFolderError: Error, Equatable {
        public let value: String

        public init(value: String) {
            self.value = value
        }
    }

    /// The backups for a command line tool.
    ///
    /// - Parameter environment: the environment of the process.
    /// - Returns: with no variable, backups that go to the Trash, and a nil
    ///   folder. With the variable, backups that move to that folder.
    /// - Throws: `TestFolderError` when the variable is set to anything but
    ///   an absolute path to a folder that exists.
    public static func fromEnvironment(
        _ environment: [String: String]
    ) throws -> (backups: FileBackups, testFolder: URL?) {
        guard let value = environment[testFolderVariable] else { return (FileBackups(), nil) }
        var isFolder: ObjCBool = false
        guard value.hasPrefix("/"), FileManager.default.fileExists(atPath: value, isDirectory: &isFolder),
              isFolder.boolValue else {
            throw TestFolderError(value: value)
        }
        let folder = URL(fileURLWithPath: value, isDirectory: true)
        return (FileBackups(trash: { try move($0, into: folder) }), folder)
    }

    /// Moves `backup` into `folder` under its own name. When that name is
    /// taken, a number follows it, as the Trash adds a time. Never replaces.
    private static func move(_ backup: URL, into folder: URL) throws {
        let name = backup.lastPathComponent
        var destination = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(name) \(number)")
            number += 1
        }
        try FileManager.default.moveItem(at: backup, to: destination)
    }
}
