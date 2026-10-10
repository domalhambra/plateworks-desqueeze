import Foundation

/// The three things a front end does with a folder: scan, run, and remove.
/// Each returns a report that is ready to print.
///
/// The command line tool and the MCP server both call these, so the two do
/// the same work and print the same JSON (design 12). Every rule is in
/// `FolderScanner` and `DesqueezeJob`. This type only joins them to the
/// report types.
public struct DesqueezeOperations: Sendable {
    public let exiftool: URL
    /// Nil when dnglab is not installed. Adobe DNG Converter then converts
    /// every ARW.
    public let dnglab: URL?
    /// Adobe DNG Converter, the optional backup. Nil when it is not
    /// installed. With neither converter the ARW files wait, and the DNG
    /// files still run.
    public let dngConverter: URL?
    private let tag: ScaleTagging
    private let converters: RawConverters
    private let backups: BackupHandling
    private let lock: FolderLock
    private let verbose: @Sendable (String) -> Void

    /// - Parameters:
    ///   - exiftool: reads and writes the tags.
    ///   - dnglab: there is no default, so no caller leaves dnglab out by
    ///     mistake and converts with Adobe alone.
    ///   - dngConverter: Adobe DNG Converter, or nil when it is not
    ///     installed.
    ///   - runner: starts exiftool and both converters. Wrap it in a
    ///     `LoggingProcessRunner` to see each command.
    ///   - backups: where a backup goes after a write that passed its check,
    ///     and where the partial output of a failed conversion and the
    ///     leftover work file of an earlier run go. There is no default, so
    ///     no caller reaches the Trash by leaving it out. The command line
    ///     tool and the MCP server name the Trash themselves, as the window
    ///     does for its own job.
    ///   - verbose: gets one line for each leftover work file that a
    ///     converter removed before it started: `Removed a leftover work
    ///     file: <name>`. It also gets one line, with the number of the
    ///     error, when the volume gave no lock for the folder (design
    ///     13.9). Give it the sink of the `LoggingProcessRunner`. The
    ///     default says nothing.
    public init(exiftool: URL, dnglab: URL?, dngConverter: URL?, runner: ProcessRunner = SystemProcessRunner(),
                backups: BackupHandling, verbose: @escaping @Sendable (String) -> Void = { _ in }) {
        self.init(exiftool: exiftool, dnglab: dnglab, dngConverter: dngConverter,
                  tag: ScaleTag(exiftool: exiftool, runner: runner),
                  converters: RawConverters(exiftool: exiftool, dnglab: dnglab, adobe: dngConverter, runner: runner,
                                            backups: backups, verbose: verbose),
                  backups: backups, verbose: verbose)
    }

    /// - Parameter lock: the lock of the job. The default is the system's,
    ///   and the public way in has no other: tests inject one to drive each
    ///   answer.
    init(exiftool: URL, dnglab: URL?, dngConverter: URL?, tag: ScaleTagging, converters: RawConverters,
         backups: BackupHandling, lock: FolderLock = .system,
         verbose: @escaping @Sendable (String) -> Void = { _ in }) {
        self.exiftool = exiftool
        self.dnglab = dnglab
        self.dngConverter = dngConverter
        self.tag = tag
        self.converters = converters
        self.backups = backups
        self.lock = lock
        self.verbose = verbose
    }

    /// True when one converter or the other is installed, so a pending ARW
    /// can convert. A front end gives this to the sentences of `FolderText`
    /// and `RunReport` that ask for `converterAvailable`.
    ///
    /// It is `RawConverters.canConvert` of the converters that the job runs:
    /// one source. `dnglab` and `dngConverter` are the paths for the report.
    public var canConvert: Bool { converters.canConvert }

    private var job: DesqueezeJob {
        DesqueezeJob(tag: tag, converters: converters, backups: backups, lock: lock, verbose: verbose)
    }

    /// What the folder holds now. Changes no file.
    ///
    /// - Throws: when the folder cannot be read.
    public func scan(_ folder: URL) throws -> ScanReport {
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        return ScanReport(snapshot: snapshot, exiftool: exiftool, dnglab: dnglab, dngConverter: dngConverter)
    }

    /// Design 4.3 at `factor`. With `dryRun`, the report of
    /// `DesqueezeJob.plan`, and no file changes.
    ///
    /// - Parameters:
    ///   - folder: the folder to scan and to run on. Its top level only.
    ///   - factor: the stretch to set.
    ///   - convert: false leaves the ARW files alone. The report still
    ///     counts them in `unconvertedARWs`, also at factor 1. Only `remove`
    ///     leaves that count out.
    ///   - trashOriginals: true moves each ARW that this run converted to
    ///     the Trash, when every line of design 14.2 holds for it. There is
    ///     no default, so every caller states it: the command line tool
    ///     gives its flag, and the MCP server always gives false.
    ///   - dryRun: true changes no file, and the report has the steps.
    ///   - cancel: stops the run after its current file, when it is set.
    ///   - progress: called after each step of a real run.
    /// - Throws: `FolderLock.Busy` when another run works in the folder,
    ///   and `FolderLock.Failed` when the lock call failed, for a real run
    ///   only: a dry run takes no lock (design 13.9). Any other error only
    ///   when the folder cannot be scanned. No file is changed then. A file
    ///   that fails is a note in the report.
    public func run(
        _ folder: URL,
        factor: SqueezeFactor,
        convert: Bool = true,
        trashOriginals: Bool,
        dryRun: Bool = false,
        cancel: CancelFlag = CancelFlag(),
        progress: (RunProgress) -> Void = { _ in }
    ) throws -> RunReport {
        try perform(folder, factor: factor, convert: convert, trashOriginals: trashOriginals, remove: false,
                    dryRun: dryRun, cancel: cancel, progress: progress)
    }

    /// Design 4.3 with factor 1 and no conversion. It reports no ARW files
    /// left: Remove has no ARW work. It never moves an original (design
    /// 14.2), so it takes no such request. It throws as `run` does.
    public func remove(
        _ folder: URL,
        dryRun: Bool = false,
        cancel: CancelFlag = CancelFlag(),
        progress: (RunProgress) -> Void = { _ in }
    ) throws -> RunReport {
        try perform(folder, factor: .noStretch, convert: false, trashOriginals: false, remove: true,
                    dryRun: dryRun, cancel: cancel, progress: progress)
    }

    private func perform(
        _ folder: URL, factor: SqueezeFactor, convert: Bool, trashOriginals: Bool, remove: Bool, dryRun: Bool,
        cancel: CancelFlag, progress: (RunProgress) -> Void
    ) throws -> RunReport {
        if dryRun {
            let plan = try job.plan(folder: folder, factor: factor, convert: convert,
                                    trashOriginals: trashOriginals, remove: remove)
            return RunReport(folder: folder, factor: factor, plan: plan)
        }
        let summary = try job.run(folder: folder, factor: factor, convert: convert, trashOriginals: trashOriginals,
                                  remove: remove, cancel: cancel, progress: progress)
        return RunReport(folder: folder, factor: factor, summary: summary)
    }
}
