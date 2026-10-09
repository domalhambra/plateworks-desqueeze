import Foundation

/// One run over a folder (design, section 4.3).
///
/// Order: scan the folder, convert every pending ARW, then tag every DNG, the
/// new ones last. One file at a time. Cancel is honored between files.
///
/// The notes of a run start with one note for each orphan backup in the
/// folder, so every front end reports them.
///
/// **The ARW files a run left.** `RunSummary.unconvertedARWs` is the number of
/// pending ARW files in the run's own scan, minus the ones this run converted.
/// So it counts every pending ARW when there is no converter or `convert` is
/// false, an ARW whose conversion failed (that one is in `failed` too), and
/// the ARW files that a stopped run did not reach. Remove is the exception:
/// it has no ARW work, so it reports 0. Remove is a run at no stretch with
/// `convert` false, as the design defines it.
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

    /// Scans `folder`, and returns what a run would do. Changes no file.
    ///
    /// The only tool call is the scan's one read of the folder.
    ///
    /// - Throws: only when the scan fails.
    public func plan(folder: URL, factor: SqueezeFactor, convert: Bool) throws -> RunPlan {
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        return plan(snapshot, factor: factor, convert: convert)
    }

    // MARK: What the run and the dry run share

    /// The summary before the first file: the ARW files to account for, and
    /// the notes about the folder itself.
    private func opening(_ snapshot: FolderSnapshot, factor: SqueezeFactor, convert: Bool) -> RunSummary {
        var summary = RunSummary()
        let isRemove = !convert && factor == .noStretch
        summary.unconvertedARWs = isRemove ? 0 : snapshot.pendingARWs.count
        guard snapshot.isWritable else {
            summary.notes = [.folderReadOnly(snapshot.folder)]
            return summary
        }
        // An orphan backup may be the only copy of a photo, and it is in no
        // count. The run does not touch it. The run names it first, before
        // any file, so a cancelled run names it too.
        summary.notes = snapshot.orphanBackups.map { .orphanBackup(named: $0.lastPathComponent) }
        return summary
    }

    /// The ARW files that go to the converter. Remove never converts. With
    /// no converter the ARW files wait.
    private func arwsToConvert(_ snapshot: FolderSnapshot, convert: Bool) -> [URL] {
        convert && converter != nil ? snapshot.pendingARWs : []
    }

    /// The DNG of a conversion. The converter writes no stretch, so the
    /// scale is known, and the job does not read the new file.
    private static func converted(_ arw: URL, to dng: URL) -> DNGFile {
        DNGFile(url: dng, scale: .noStretch, originalRawFileName: arw.lastPathComponent, hasBackup: false)
    }

    /// Asked at the moment of each file, not taken from the scan.
    private func decide(_ dng: DNGFile, _ factor: SqueezeFactor) -> (decision: TagDecision, hasBackup: Bool) {
        let hasBackup = backups.backupExists(for: dng.url)
        return (TagDecision.decide(scale: dng.scale, hasBackup: hasBackup, factor: factor), hasBackup)
    }

    // MARK: The dry run

    /// The plan itself, on a snapshot. Not public, for the reason at `run`.
    ///
    /// It walks the files in the order of `run`, and asks the same questions.
    /// It assumes that each conversion and each write passes.
    func plan(_ snapshot: FolderSnapshot, factor: SqueezeFactor, convert: Bool) -> RunPlan {
        var plan = RunPlan(steps: [], summary: opening(snapshot, factor: factor, convert: convert))
        guard snapshot.isWritable else { return plan }

        var dngs = snapshot.dngs
        for arw in arwsToConvert(snapshot, convert: convert) {
            plan.steps.append(RunPlan.Step(name: arw.lastPathComponent, action: .convert))
            plan.summary.converted += 1
            plan.summary.unconvertedARWs -= 1
            // The DNG is not there yet. The run will tag it, so the plan
            // must decide for it too.
            dngs.append(Self.converted(arw, to: AdobeConverter.outputURL(for: arw)))
        }
        for dng in dngs {
            let (decision, hasBackup) = decide(dng, factor)
            plan.steps.append(RunPlan.Step(name: dng.name, action: RunPlan.Action(decision)))
            plan.summary.count(decision, for: dng.name, hasBackup: hasBackup)
            if decision == .write { plan.summary.set += 1 }
        }
        return plan
    }

    // MARK: The run

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
        var summary = opening(snapshot, factor: factor, convert: convert)
        guard snapshot.isWritable else { return summary }

        let arws = arwsToConvert(snapshot, convert: convert)
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
                    summary.unconvertedARWs -= 1
                    dngs.append(Self.converted(arw, to: dng))
                } catch {
                    summary.failed += 1
                    // This ARW made no DNG, so its tag step will not happen.
                    total -= 1
                    summary.notes.append(.notConverted(arw.lastPathComponent, detail: Self.describe(error)))
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
        let (decision, hasBackup) = decide(dng, factor)
        summary.count(decision, for: dng.name, hasBackup: hasBackup)
        guard decision == .write else { return }

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
            summary.notes.append(.failed(dng.name, message: message, detail: detail))
            return
        }

        summary.set += 1
        do {
            try backups.trashBackup(for: dng.url)
        } catch {
            summary.notes.append(.backupKept(dng.name, detail: error.localizedDescription))
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
