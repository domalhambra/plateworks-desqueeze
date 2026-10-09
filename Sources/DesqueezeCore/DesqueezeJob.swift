import Foundation

/// One line for the result list: a file and what happened to it.
public struct FileNote: Equatable, Sendable, Identifiable {
    public let name: String
    public let message: String
    /// The tool's own words, shown below the plain sentence.
    public let detail: String?

    public var id: String { name + "\n" + message }

    public init(name: String, message: String, detail: String?) {
        self.name = name
        self.message = message
        self.detail = detail
    }
}

public struct RunSummary: Equatable, Sendable {
    public var converted = 0
    public var set = 0
    public var skipped = 0
    public var failed = 0
    public var notes: [FileNote] = []
    public var cancelled = false

    public init() {}
}

public struct RunProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let name: String
}

/// Set from the main thread, read from the job's thread.
public final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    public init() {}

    public func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// One run over a folder snapshot (design, section 4.3).
///
/// Order: convert every pending ARW, then tag every DNG, the new ones last.
/// One file at a time. Cancel is honored between files.
public struct DesqueezeJob: Sendable {
    private let tag: ScaleTagging
    private let converter: RawConverter?
    private let backups: BackupHandling

    /// - Parameter converter: nil when Adobe DNG Converter is not installed.
    ///   The DNG files still run.
    public init(tag: ScaleTagging, converter: RawConverter?, backups: BackupHandling = FileBackups()) {
        self.tag = tag
        self.converter = converter
        self.backups = backups
    }

    /// - Parameter convert: false for Remove, which never converts.
    public func run(
        _ snapshot: FolderSnapshot,
        factor: SqueezeFactor,
        convert: Bool,
        cancel: CancelFlag = CancelFlag(),
        progress: (RunProgress) -> Void = { _ in }
    ) -> RunSummary {
        var summary = RunSummary()
        guard snapshot.isWritable else {
            summary.notes.append(FileNote(name: snapshot.folder.lastPathComponent,
                                          message: "This folder is read-only. No file was changed.", detail: nil))
            return summary
        }

        let arws = (convert && converter != nil) ? snapshot.pendingARWs : []
        var dngs = snapshot.dngs
        var total = arws.count * 2 + dngs.count
        var completed = 0

        for arw in arws {
            if cancel.isCancelled {
                summary.cancelled = true
                return summary
            }
            do {
                let dng = try converter!.convert(arw)
                summary.converted += 1
                dngs.append(DNGFile(url: dng, horizontal: 1, vertical: 1,
                                    originalRawFileName: arw.lastPathComponent, hasBackup: false))
            } catch {
                summary.failed += 1
                total -= 1
                summary.notes.append(FileNote(name: arw.lastPathComponent, message: "Not converted.",
                                              detail: Self.describe(error)))
            }
            completed += 1
            progress(RunProgress(completed: completed, total: total, name: arw.lastPathComponent))
        }

        for dng in dngs {
            if cancel.isCancelled {
                summary.cancelled = true
                return summary
            }
            tagOne(dng, factor, &summary)
            completed += 1
            progress(RunProgress(completed: completed, total: total, name: dng.name))
        }
        return summary
    }

    private func tagOne(_ dng: DNGFile, _ factor: SqueezeFactor, _ summary: inout RunSummary) {
        if factor.matches(horizontal: dng.horizontal, vertical: dng.vertical) {
            summary.skipped += 1
            return
        }
        // exiftool never replaces an existing `_original`. A write over one
        // would leave a backup of the wrong state, and this app must not
        // discard a backup that it did not make.
        if backups.backupExists(for: dng.url) {
            summary.skipped += 1
            summary.notes.append(FileNote(
                name: dng.name,
                message: "Skipped. An older backup, \(dng.name)_original, is beside this file. Move it away, then run again.",
                detail: nil))
            return
        }

        do {
            try tag.write(factor, to: dng.url)
            guard let now = try tag.read(dng.url),
                  factor.matches(horizontal: now.horizontal, vertical: now.vertical) else {
                throw TagError.toolFailed("The tag did not read back as \(factor.tagValue).")
            }
        } catch {
            // A failed write makes no backup and leaves the file unchanged.
            // Restore only when a backup exists.
            var message = "Not changed."
            if backups.backupExists(for: dng.url) {
                do {
                    try backups.restoreBackup(for: dng.url)
                    message = "Not changed. The backup was restored."
                } catch {
                    message = "The write failed, and the backup could not be restored. The backup is \(dng.name)_original."
                }
            }
            summary.failed += 1
            summary.notes.append(FileNote(name: dng.name, message: message, detail: Self.describe(error)))
            return
        }

        summary.set += 1
        do {
            try backups.trashBackup(for: dng.url)
        } catch {
            summary.notes.append(FileNote(
                name: dng.name,
                message: "Done. The backup stayed beside the file, because the Trash refused it.",
                detail: error.localizedDescription))
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case TagError.toolFailed(let text): return text
        case ConvertError.failed(let text): return text
        default: return error.localizedDescription
        }
    }
}
