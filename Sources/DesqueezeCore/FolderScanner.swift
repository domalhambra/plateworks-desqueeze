import Foundation

/// Everything the window and the job need to know about one folder.
public struct FolderSnapshot: Equatable, Sendable {
    public let folder: URL
    public var dngs: [DNGFile]
    /// The ARW files that no DNG claims. Only these may go to the converter.
    public var pendingARWs: [URL]
    public var isWritable: Bool

    public var photoCount: Int { dngs.count + pendingARWs.count }
    public var isEmpty: Bool { photoCount == 0 }

    public init(folder: URL, dngs: [DNGFile], pendingARWs: [URL], isWritable: Bool) {
        self.folder = folder
        self.dngs = dngs
        self.pendingARWs = pendingARWs
        self.isWritable = isWritable
    }
}

public struct FolderScanner: Sendable {
    private let tag: ScaleTagging
    private let backups: BackupHandling

    public init(tag: ScaleTagging, backups: BackupHandling = FileBackups()) {
        self.tag = tag
        self.backups = backups
    }

    public func snapshot(of folder: URL) throws -> FolderSnapshot {
        let contents = try FolderScan.contents(of: folder)
        var rows: [String: TagRow] = [:]
        if !contents.dngs.isEmpty {
            for row in try tag.readFolder(folder) { rows[row.fileName] = row }
        }
        let dngs = contents.dngs.map { url -> DNGFile in
            let row = rows[url.lastPathComponent]
            return DNGFile(
                url: url,
                horizontal: row?.horizontal ?? 1,
                vertical: row?.vertical ?? 1,
                originalRawFileName: row?.originalRawFileName,
                hasBackup: backups.backupExists(for: url)
            )
        }
        return FolderSnapshot(
            folder: folder,
            dngs: dngs,
            pendingARWs: FolderScan.pending(arws: contents.arws, dngs: dngs),
            isWritable: FileManager.default.isWritableFile(atPath: folder.path)
        )
    }
}
