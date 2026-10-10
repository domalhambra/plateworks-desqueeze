import Foundation

/// Everything a front end and the job need to know about one folder.
public struct FolderSnapshot: Equatable, Sendable {
    public let folder: URL
    public var dngs: [DNGFile]
    /// The ARW files that no DNG claims. Only these may go to a converter:
    /// dnglab, or Adobe DNG Converter.
    public var pendingARWs: [URL]
    /// Each `<name>.dng_original` whose DNG is not beside it. exiftool leaves
    /// one when it stops between its two renames. It may be the only copy of
    /// a photo. It is in no count. A run does not touch it, and names it in
    /// a note.
    public var orphanBackups: [URL]
    public var isWritable: Bool

    /// The photos a run can work on. An orphan backup is not one of them.
    public var photoCount: Int { dngs.count + pendingARWs.count }
    /// True when the folder holds nothing to report: no DNG, no pending ARW,
    /// and no orphan backup. A folder that holds only an orphan backup is not
    /// empty, so no front end can drop the backup with an "empty folder" line.
    public var isEmpty: Bool { photoCount == 0 && orphanBackups.isEmpty }

    public init(folder: URL, dngs: [DNGFile], pendingARWs: [URL], orphanBackups: [URL], isWritable: Bool) {
        self.folder = folder
        self.dngs = dngs
        self.pendingARWs = pendingARWs
        self.orphanBackups = orphanBackups
        self.isWritable = isWritable
    }
}

/// Makes the `FolderSnapshot` of a folder: the lists of `FolderScan`, the tag
/// of each DNG, and the backup state. It changes no file.
public struct FolderScanner: Sendable {
    private let tag: ScaleTagging
    private let backups: BackupHandling

    public init(tag: ScaleTagging, backups: BackupHandling) {
        self.tag = tag
        self.backups = backups
    }

    public func snapshot(of folder: URL) throws -> FolderSnapshot {
        let contents = try FolderScan.contents(of: folder)
        // exiftool prints a control character of a file name as a period,
        // so a row is found by the printed name (`ExiftoolText.pair`). A file
        // with no row has an unknown scale, and a run tries to write it.
        var rows: [String: [TagRow]] = [:]
        if !contents.dngs.isEmpty {
            for row in try tag.readFolder(folder) { rows[row.fileName, default: []].append(row) }
        }
        let paired = ExiftoolText.pair(files: contents.dngs.map(\.lastPathComponent), rows: rows)
        let dngs = contents.dngs.map { url -> DNGFile in
            let row = paired[url.lastPathComponent]
            return DNGFile(
                url: url,
                scale: row?.scale,
                originalRawFileName: row?.originalRawFileName,
                hasBackup: backups.backupExists(for: url)
            )
        }
        return FolderSnapshot(
            folder: folder,
            dngs: dngs,
            pendingARWs: FolderScan.pending(arws: contents.arws, dngs: dngs, orphanBackups: contents.orphanBackups),
            orphanBackups: contents.orphanBackups,
            isWritable: FileManager.default.isWritableFile(atPath: folder.path)
        )
    }
}
