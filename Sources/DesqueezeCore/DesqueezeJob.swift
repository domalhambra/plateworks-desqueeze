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

/// One run over a folder (design, section 4.3).
///
/// Order: scan the folder, convert every pending ARW, then tag every DNG, the
/// new ones last. One file at a time. Cancel is honored between files.
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

    /// Scans `folder`, then runs on what that scan found.
    ///
    /// This is the only public way to run. Each skip is decided on what the
    /// folder holds at the call, never on what a front end read earlier.
    ///
    /// - Parameter convert: false for Remove, which never converts.
    /// - Throws: only when the scan fails. No file is changed then. A file
    ///   that fails during the run is a note in the summary, not an error.
    public func run(
        folder: URL,
        factor: SqueezeFactor,
        convert: Bool,
        cancel: CancelFlag = CancelFlag(),
        progress: (RunProgress) -> Void = { _ in }
    ) throws -> RunSummary {
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        return run(snapshot, factor: factor, convert: convert, cancel: cancel, progress: progress)
    }

    /// The run itself, on a snapshot.
    ///
    /// Not public, on purpose. A snapshot is true only at the moment of its
    /// scan. A window that kept one across a run made Remove report "skipped"
    /// for files that the run had just stretched. Tests reach this method
    /// with `@testable`, to give the job a folder state without a folder.
    func run(
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

        // Remove never converts. With no converter the ARW files wait.
        let converter = convert ? self.converter : nil
        let arws = converter == nil ? [] : snapshot.pendingARWs
        var dngs = snapshot.dngs
        var total = arws.count * 2 + dngs.count
        var completed = 0

        if let converter {
            for arw in arws {
                if cancel.isCancelled {
                    summary.cancelled = true
                    return summary
                }
                do {
                    let dng = try converter.convert(arw)
                    summary.converted += 1
                    // The converter writes no stretch, so the scale is known.
                    dngs.append(DNGFile(url: dng, scale: .noStretch,
                                        originalRawFileName: arw.lastPathComponent, hasBackup: false))
                } catch {
                    summary.failed += 1
                    // This ARW made no DNG, so its tag step will not happen.
                    total -= 1
                    summary.notes.append(FileNote(name: arw.lastPathComponent, message: "Not converted.",
                                                  detail: Self.describe(error)))
                }
                completed += 1
                progress(RunProgress(completed: completed, total: total, name: arw.lastPathComponent))
            }
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
        let hasBackup = backups.backupExists(for: dng.url)
        if factor.matches(dng.scale) {
            summary.skipped += 1
            // A run that died after its write leaves this. The backup is the
            // file as it was before, so the user must know that it is there.
            if hasBackup {
                summary.notes.append(FileNote(
                    name: dng.name,
                    message: "Already set. A backup, \(dng.name)_original, is beside this file.",
                    detail: nil))
            }
            return
        }
        // exiftool never replaces an existing `_original`. A write over one
        // would leave a backup of the wrong state, and this app must not
        // discard a backup that it did not make.
        if hasBackup {
            summary.skipped += 1
            summary.notes.append(FileNote(
                name: dng.name,
                message: "Skipped. An older backup, \(dng.name)_original, is beside this file. Move it away, then run again.",
                detail: nil))
            return
        }

        do {
            try tag.write(factor, to: dng.url)
            guard factor.matches(try tag.read(dng.url)) else {
                throw TagError.toolFailed("The tag did not read back as \(factor.tagValue).")
            }
        } catch {
            // A failed write makes no backup and leaves the file unchanged.
            // Restore only when a backup exists.
            var message = "Not changed."
            var detail = Self.describe(error)
            if backups.backupExists(for: dng.url) {
                do {
                    try backups.restoreBackup(for: dng.url)
                    message = "Not changed. The backup was restored."
                } catch let restoreError {
                    // The write may have passed and the check failed, so the
                    // file may be changed. "The write failed" would be wrong.
                    message = "The change failed, and the backup could not be restored. The backup is \(dng.name)_original."
                    detail += "\nRestore: " + Self.describe(restoreError)
                }
            }
            summary.failed += 1
            summary.notes.append(FileNote(name: dng.name, message: message, detail: detail))
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
