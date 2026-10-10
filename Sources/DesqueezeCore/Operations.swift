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

    /// - Parameters:
    ///   - dnglab: there is no default, so no caller leaves dnglab out by
    ///     mistake and converts with Adobe alone.
    ///   - runner: starts exiftool and both converters. Wrap it in a
    ///     `LoggingProcessRunner` to see each command.
    ///   - backups: where a backup goes after a write that passed its check,
    ///     and where the partial output of a failed conversion and the
    ///     leftover work file of an earlier run go. There is no default, so
    ///     no caller reaches the Trash by leaving it out. The window and the
    ///     tool name the Trash themselves.
    ///   - verbose: gets one line for each leftover work file that a
    ///     converter removed before it started: `Removed a leftover work
    ///     file: <name>`. Give it the sink of the `LoggingProcessRunner`.
    ///     The default says nothing.
    public init(exiftool: URL, dnglab: URL?, dngConverter: URL?, runner: ProcessRunner = SystemProcessRunner(),
                backups: BackupHandling, verbose: @escaping @Sendable (String) -> Void = { _ in }) {
        self.init(exiftool: exiftool, dnglab: dnglab, dngConverter: dngConverter,
                  tag: ScaleTag(exiftool: exiftool, runner: runner),
                  converters: RawConverters(exiftool: exiftool, dnglab: dnglab, adobe: dngConverter, runner: runner,
                                            backups: backups, verbose: verbose),
                  backups: backups)
    }

    init(exiftool: URL, dnglab: URL?, dngConverter: URL?, tag: ScaleTagging, converters: RawConverters,
         backups: BackupHandling) {
        self.exiftool = exiftool
        self.dnglab = dnglab
        self.dngConverter = dngConverter
        self.tag = tag
        self.converters = converters
        self.backups = backups
    }

    /// True when one converter or the other is installed, so a pending ARW
    /// can convert. A front end gives this to the sentences of `FolderText`
    /// and `RunReport` that ask for `converterAvailable`.
    ///
    /// It is `RawConverters.canConvert` of the converters that the job runs:
    /// one source. `dnglab` and `dngConverter` are the paths for the report.
    public var canConvert: Bool { converters.canConvert }

    private var job: DesqueezeJob { DesqueezeJob(tag: tag, converters: converters, backups: backups) }

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
    /// - Parameter convert: false leaves the ARW files alone. The report
    ///   still counts them in `unconvertedARWs`, also at factor 1. Only
    ///   `remove` leaves that count out.
    /// - Throws: only when the folder cannot be scanned. No file is changed
    ///   then. A file that fails is a note in the report.
    public func run(
        _ folder: URL,
        factor: SqueezeFactor,
        convert: Bool = true,
        dryRun: Bool = false,
        cancel: CancelFlag = CancelFlag(),
        progress: (RunProgress) -> Void = { _ in }
    ) throws -> RunReport {
        try perform(folder, factor: factor, convert: convert, remove: false, dryRun: dryRun, cancel: cancel,
                    progress: progress)
    }

    /// Design 4.3 with factor 1 and no conversion. It reports no ARW files
    /// left: Remove has no ARW work.
    public func remove(
        _ folder: URL,
        dryRun: Bool = false,
        cancel: CancelFlag = CancelFlag(),
        progress: (RunProgress) -> Void = { _ in }
    ) throws -> RunReport {
        try perform(folder, factor: .noStretch, convert: false, remove: true, dryRun: dryRun, cancel: cancel,
                    progress: progress)
    }

    private func perform(
        _ folder: URL, factor: SqueezeFactor, convert: Bool, remove: Bool, dryRun: Bool, cancel: CancelFlag,
        progress: (RunProgress) -> Void
    ) throws -> RunReport {
        if dryRun {
            return RunReport(folder: folder, factor: factor,
                             plan: try job.plan(folder: folder, factor: factor, convert: convert, remove: remove))
        }
        let summary = try job.run(folder: folder, factor: factor, convert: convert, remove: remove, cancel: cancel,
                                  progress: progress)
        return RunReport(folder: folder, factor: factor, summary: summary)
    }
}
