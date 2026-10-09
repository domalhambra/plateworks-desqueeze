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
