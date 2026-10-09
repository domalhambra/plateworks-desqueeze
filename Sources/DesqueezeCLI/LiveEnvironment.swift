import DesqueezeCore
import Foundation

/// Sets a flag at Control-C, so a run stops after its current file.
///
/// exiftool and the converter do not get the Control-C: `Process` starts each
/// in a process group of its own, and the terminal signals only the group of
/// this tool. So the file in work completes, and the run then sees the flag.
/// A plain `kill` (SIGTERM) is taken the same way.
public final class InterruptWatcher: @unchecked Sendable {
    public let flag = CancelFlag()
    private var sources: [DispatchSourceSignal] = []

    /// - Parameter onFirst: called once, at the first signal.
    public init(onFirst: @escaping @Sendable () -> Void) {
        let flag = flag
        for number in [SIGINT, SIGTERM] {
            // The signal must not end the process. The source still sees it.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                if !flag.isCancelled { onFirst() }
                flag.cancel()
            }
            source.resume()
            sources.append(source)
        }
    }
}

extension ToolEnvironment {
    /// The environment of the real tool: the working folder, the two tools
    /// where `ToolLocator` finds them, the Trash, and the two standard
    /// streams.
    ///
    /// The converter is looked for in `/Applications` only. The window also
    /// asks Launch Services, which needs AppKit, and this tool is Foundation
    /// only.
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
            dngConverter: locator.dngConverter(),
            runner: SystemProcessRunner(),
            backups: backups,
            testBackupFolder: testFolder,
            interruptFlag: {
                // The watcher lives as long as the process: the run that asked
                // for it is the last thing the tool does.
                let watcher = InterruptWatcher { standardError("Stopping after the current file.") }
                return Unmanaged.passRetained(watcher).takeUnretainedValue().flag
            },
            standardOutput: { write($0, to: .standardOutput) },
            standardError: standardError)
    }

    private static func write(_ text: String, to handle: FileHandle) {
        // A closed pipe is not worth a crash.
        try? handle.write(contentsOf: Data((text + "\n").utf8))
    }
}

extension DesqueezeTool {
    /// The tool as `main.swift` starts it. Returns the exit code.
    public static func main() -> Int32 {
        do {
            let environment = try ToolEnvironment.live(processEnvironment: ProcessInfo.processInfo.environment)
            return run(Array(CommandLine.arguments.dropFirst()), in: environment)
        } catch let error as FileBackups.TestFolderError {
            let line = "desqueeze: \(FileBackups.testFolderVariable) is set, and its value is not a folder: "
                + "\"\(error.value)\". It is for tests only. Unset it, then run again.\n"
            try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
            return 1
        } catch {
            return 1
        }
    }
}
