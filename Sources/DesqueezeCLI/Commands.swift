import DesqueezeCore
import Foundation

/// Everything the tool takes from the outside. A test gives its own.
public struct ToolEnvironment: Sendable {
    /// A relative folder on the command line is resolved against this.
    public var workingFolder: URL
    /// Nil when exiftool is not installed. No command can run then.
    public var exiftool: URL?
    /// Nil when dnglab is not installed. Adobe DNG Converter then converts.
    public var dnglab: URL?
    /// Nil when Adobe DNG Converter is not installed. It is the optional
    /// backup. With neither converter the DNG files still run.
    public var dngConverter: URL?
    public var runner: ProcessRunner
    public var backups: BackupHandling
    /// Set when `backups` does not use the Trash. The tool then says so.
    public var testBackupFolder: URL?
    /// Called once, at the start of a run that changes files. Returns the
    /// flag that Control-C sets. Other commands keep the system's Control-C.
    public var interruptFlag: @Sendable () -> CancelFlag
    /// Each call is one line, or one JSON object. The line end is added.
    public var standardOutput: @Sendable (String) -> Void
    public var standardError: @Sendable (String) -> Void

    public init(
        workingFolder: URL, exiftool: URL?, dnglab: URL?, dngConverter: URL?, runner: ProcessRunner,
        backups: BackupHandling,
        testBackupFolder: URL?, interruptFlag: @escaping @Sendable () -> CancelFlag,
        standardOutput: @escaping @Sendable (String) -> Void, standardError: @escaping @Sendable (String) -> Void
    ) {
        self.workingFolder = workingFolder
        self.exiftool = exiftool
        self.dnglab = dnglab
        self.dngConverter = dngConverter
        self.runner = runner
        self.backups = backups
        self.testBackupFolder = testBackupFolder
        self.interruptFlag = interruptFlag
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// The `desqueeze` command line tool (design 12.1): parse, do, print.
///
/// Standard output holds the result only: text for a person, or with `--json`
/// exactly one JSON object. Progress, `--verbose` and every message go to
/// standard error. All file work is in `DesqueezeOperations`.
public enum DesqueezeTool {
    /// - Parameter arguments: the command line with no program name.
    /// - Returns: the exit code. 0, 1 or 2, as the design defines them.
    public static func run(_ arguments: [String], in environment: ToolEnvironment) -> Int32 {
        let invocation: Invocation
        do {
            invocation = try Arguments.parse(arguments)
        } catch let error as UsageError {
            Usage.error(error).forEach(environment.standardError)
            return 2
        } catch {
            return 2
        }

        switch invocation.command {
        case .help:
            environment.standardOutput(Usage.help)
            return 0
        case .version:
            environment.standardOutput(Usage.version)
            return 0
        case .scan(let folder):
            return perform(invocation, folder, in: environment) { operations, url in
                let report = try operations.scan(url)
                // The scan completed, so it gives 0, also for a read-only
                // folder: the report says `"writable": false`.
                return (try output(report, TextOutput.scan(report), invocation), 0)
            }
        case .run(let folder, let factor, let convert, let trashOriginals, let dryRun):
            return perform(invocation, folder, in: environment) { operations, url in
                // The flag of the command line, and nothing else, says
                // whether the originals move (design 14.5).
                let report = try operations.run(
                    url, factor: factor, convert: convert, trashOriginals: trashOriginals, dryRun: dryRun,
                    cancel: dryRun ? CancelFlag() : environment.interruptFlag(), progress: progress(to: environment))
                return (try output(report, runText(report, operations), invocation), exitCode(report))
            }
        case .remove(let folder, let dryRun):
            return perform(invocation, folder, in: environment) { operations, url in
                let report = try operations.remove(
                    url, dryRun: dryRun, cancel: dryRun ? CancelFlag() : environment.interruptFlag(),
                    progress: progress(to: environment))
                return (try output(report, runText(report, operations), invocation), exitCode(report))
            }
        }
    }

    // MARK: Exit codes

    /// The code of a run or a remove: 1 when a file failed or was blocked,
    /// the run was stopped, or the folder is read-only. A dry run gives the
    /// code of the run it plans. A scan has no such code: when it completed,
    /// it gives 0. A DNG with no full match (`convertedUnmatched`) is
    /// converted: it does not make the code 1 (design 13.4). An original
    /// that stays (`originalKept`) does not make it 1 either (design 14.3),
    /// and no more does a run on a volume that gives no folder lock
    /// (`noFolderLock`, design 13.9).
    static func exitCode(_ report: RunReport) -> Int32 {
        let readOnly = report.notes.contains { $0.kind == .folderReadOnly }
        return report.failed > 0 || report.blocked > 0 || report.stopped || readOnly ? 1 : 0
    }

    // MARK: The parts of a command

    /// The frame around every command that reads a folder: the exiftool
    /// check, the folder path, `--verbose`, the output, and a scan that fails.
    private static func perform(
        _ invocation: Invocation, _ folder: String, in environment: ToolEnvironment,
        _ work: (DesqueezeOperations, URL) throws -> (output: String, exitCode: Int32)
    ) -> Int32 {
        if let testFolder = environment.testBackupFolder {
            environment.standardError(FileBackups.testModeNotice(folder: testFolder))
        }
        guard let exiftool = environment.exiftool else {
            // The line is the core's, so the MCP server says the same.
            return fail(ToolLocator.exiftoolMissingLine, detail: nil, invocation, environment)
        }
        let named = resolve(folder, against: environment.workingFolder)
        // The window's rule for what a folder is. A link to a folder is that
        // folder, and the report names the folder, as the window does. A
        // file, and a package such as an app or a photo library, are not
        // folders.
        guard let url = FolderChoice.folder(at: named) else {
            return fail(FolderText.unreadable(path: named.path), detail: FolderChoice.whyNotAFolder(named), invocation,
                        environment)
        }
        var runner = environment.runner
        var verbose: @Sendable (String) -> Void = { _ in }
        if invocation.verbose {
            runner = LoggingProcessRunner(wrapping: runner, sink: environment.standardError)
            verbose = environment.standardError
        }
        // One runner starts exiftool, dnglab and Adobe DNG Converter, so
        // `--verbose` shows each command of all three. The same sink gets
        // the line about a leftover work file that a converter removed, and
        // the line with the error number of a volume that gave no folder
        // lock (design 13.9).
        let operations = DesqueezeOperations(exiftool: exiftool, dnglab: environment.dnglab,
                                             dngConverter: environment.dngConverter, runner: runner,
                                             backups: environment.backups, verbose: verbose)
        do {
            let result = try work(operations, url)
            environment.standardOutput(result.output)
            return result.exitCode
        } catch is FolderLock.Busy {
            // Another run works in the folder (design 13.9). This one did
            // not start. The sentence is the core's, so the window and the
            // MCP server say the same.
            return fail(FolderLock.busyMessage, detail: nil, invocation, environment)
        } catch {
            // Every other error is a scan that failed, or a lock call that
            // failed (`FolderLock.Failed`, design 13.9). No file was tried.
            return fail(FolderText.unreadable(path: url.path), detail: describe(error), invocation, environment)
        }
    }

    /// An absolute path as it is, and a relative path against the working
    /// folder. `.` and `..` are taken out, and nothing else changes: no link
    /// is resolved. `FolderChoice` decides next what the path names.
    static func resolve(_ folder: String, against workingFolder: URL) -> URL {
        let path = folder.hasPrefix("/") ? folder : workingFolder.path + "/" + folder
        var parts: [Substring] = []
        for part in path.split(separator: "/") where part != "." {
            if part == ".." {
                _ = parts.popLast()
            } else {
                parts.append(part)
            }
        }
        return URL(fileURLWithPath: "/" + parts.joined(separator: "/"), isDirectory: true)
    }

    /// The text of a result: one JSON object, or the lines for a person.
    private static func output<Report: Encodable>(_ report: Report, _ text: @autoclosure () -> [String],
                                                  _ invocation: Invocation) throws -> String {
        invocation.json ? try ReportJSON.text(report) : text().joined(separator: "\n")
    }

    /// The reason "No converter is installed" follows the line about the
    /// ARW files that the run left only when neither converter is there.
    private static func runText(_ report: RunReport, _ operations: DesqueezeOperations) -> [String] {
        TextOutput.run(report, converterInstalled: operations.canConvert)
    }

    private static func progress(to environment: ToolEnvironment) -> (RunProgress) -> Void {
        { environment.standardError("\($0.completed)/\($0.total) \($0.name)") }
    }

    /// A command that could give no report. The message goes to standard
    /// error. With `--json`, standard output still gets its one object.
    private static func fail(_ message: String, detail: String?, _ invocation: Invocation,
                             _ environment: ToolEnvironment) -> Int32 {
        environment.standardError("desqueeze: \(message)")
        if let detail { environment.standardError("    \(detail)") }
        if invocation.json, let json = try? ReportJSON.text(ErrorReport(error: message, detail: detail)) {
            environment.standardOutput(json)
        }
        return 1
    }

    private static func describe(_ error: Error) -> String {
        if case TagError.toolFailed(let text) = error { return text }
        return error.localizedDescription
    }
}
