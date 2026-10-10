import DesqueezeCore
import Foundation

extension ToolEnvironment {
    /// The environment of the real tool: the working folder, the three tools
    /// where `ToolLocator` finds them, the Trash, and the two standard
    /// streams.
    ///
    /// Adobe DNG Converter is looked for in `/Applications` only. The window
    /// also asks Launch Services, which needs AppKit, and this tool is
    /// Foundation only.
    ///
    /// - Throws: `FileBackups.TestFolderError` when the test variable is set
    ///   to something that is not a folder.
    public static func live(processEnvironment: [String: String]) throws -> ToolEnvironment {
        let (backups, testFolder) = try FileBackups.fromEnvironment(processEnvironment)
        let locator = ToolLocator(pathVariable: processEnvironment["PATH"])
        let standardError: @Sendable (String) -> Void = { write($0, to: .standardError) }
        return ToolEnvironment(
            workingFolder: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            exiftool: locator.exiftool(),
            dnglab: locator.dnglab(),
            dngConverter: locator.dngConverter(),
            runner: SystemProcessRunner(),
            backups: backups,
            testBackupFolder: testFolder,
            interruptFlag: {
                // The watcher lives as long as the process: the run that asked
                // for it is the last thing the tool does.
                let watcher = InterruptWatcher(signals: stopSignals) {
                    standardError("Stopping after the current file.")
                }
                return Unmanaged.passRetained(watcher).takeUnretainedValue().flag
            },
            standardOutput: { write($0, to: .standardOutput) },
            standardError: standardError)
    }

    /// The signals that stop a run after its current file: Control-C, a
    /// plain `kill`, and the `SIGHUP` of a Terminal window that closes. With
    /// the system's action for `SIGHUP`, the tool would end in the middle of
    /// a file.
    static let stopSignals = [SIGINT, SIGTERM, SIGHUP]

    fileprivate static func write(_ text: String, to handle: FileHandle) {
        // A closed pipe is not worth a crash.
        try? handle.write(contentsOf: Data((text + "\n").utf8))
    }
}

extension DesqueezeTool {
    /// The tool as `main.swift` starts it. Returns the exit code.
    public static func main() -> Int32 {
        // A pipe that closes early (`desqueeze run … | head`) must not end the
        // run. With the default action, the next write to the closed pipe
        // raises SIGPIPE and the process dies in the middle of a file. Ignored,
        // the write fails with an error, which `write` discards: the run
        // completes and loses only its output (design 12.1).
        signal(SIGPIPE, SIG_IGN)
        return main(
            arguments: Array(CommandLine.arguments.dropFirst()), processEnvironment: ProcessInfo.processInfo.environment,
            standardOutput: { ToolEnvironment.write($0, to: .standardOutput) },
            standardError: { ToolEnvironment.write($0, to: .standardError) })
    }

    /// - Parameters:
    ///   - arguments: the command line with no program name.
    ///   - standardOutput: gets the JSON error object, when the test variable
    ///     is wrong and the command line asks for `--json`.
    static func main(
        arguments: [String], processEnvironment: [String: String],
        standardOutput: @Sendable (String) -> Void, standardError: @Sendable (String) -> Void
    ) -> Int32 {
        do {
            let environment = try ToolEnvironment.live(processEnvironment: processEnvironment)
            return run(arguments, in: environment)
        } catch let error as FileBackups.TestFolderError {
            // The tool stops before it reads a photo folder. A usage error
            // still wins: the command line is read first, so a wrong line
            // gives 2 and nothing on standard output.
            let invocation: Invocation
            do {
                invocation = try Arguments.parse(arguments)
            } catch let usage as UsageError {
                Usage.error(usage).forEach(standardError)
                return 2
            } catch {
                return 2
            }
            // The words are the core's, so the MCP server says the same.
            let detail = FileBackups.TestFolderError.detail
            standardError("desqueeze: \(error.message) \(detail)")
            if invocation.json, let json = try? ReportJSON.text(ErrorReport(error: error.message, detail: detail)) {
                standardOutput(json)
            }
            return 1
        } catch {
            return 1
        }
    }
}
