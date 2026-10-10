import DesqueezeCore
import Foundation
import Logging
import MCP

/// The `desqueeze-mcp` program (design 12.2): an MCP server over standard
/// input and standard output, with three tools.
///
/// Standard output is the protocol. Only the library's transport writes to
/// it, one JSON-RPC message on each line. Every other word of the program
/// goes to standard error. The two flags are the exception: they print and
/// start no server.
enum Program {
    static let name = "desqueeze-mcp"
    /// `desqueeze-mcp 0.1.0`. The number is `DesqueezeVersion.current`.
    static let version = "\(name) \(DesqueezeVersion.current)"

    static let usage = """
        Usage:
          desqueeze-mcp             Starts the server. A client starts it this way.
          desqueeze-mcp --version
          desqueeze-mcp --help
        """

    static let help = """
        The MCP server of Plateworks Desqueeze. It sets the stretch of anamorphic
        DNG photos, so Lightroom shows them at the correct shape.

        \(usage)

        The server speaks MCP on standard input and standard output. A person
        does not type to it. An MCP client starts it, for example Claude Code:
          claude mcp add desqueeze -- /absolute/path/to/desqueeze-mcp

        Tools:
          desqueeze_scan     Reports what one folder holds. Changes no file.
          desqueeze_run      Converts each ARW that has no DNG, then sets the
                             stretch on every DNG.
          desqueeze_remove   Sets every DNG back to no stretch.

        The server runs one tool call at a time. Its messages for a person go
        to standard error. For the same work in a terminal: desqueeze --help.
        """

    /// What the program does with its command line and its environment.
    enum Startup {
        /// Prints `text` on standard output and ends with 0.
        case print(String)
        /// Prints `lines` on standard error and ends with `exitCode`.
        case stop(lines: [String], exitCode: Int32)
        /// Starts the server. `notice` goes to standard error first.
        case serve(backups: FileBackups, notice: String?)
    }

    /// Reads the command line and the environment. Starts nothing.
    ///
    /// - Parameter arguments: the command line with no program name.
    static func startup(arguments: [String], environment: [String: String]) -> Startup {
        switch arguments {
        case []:
            break
        case ["--version"]:
            return .print(version)
        case ["--help"], ["-h"]:
            return .print(help)
        default:
            let line = "\(name): The server takes no argument but --version and --help. "
                + "It got: \(arguments.joined(separator: " "))"
            return .stop(lines: [line, usage], exitCode: 2)
        }
        do {
            // The Trash in normal use. The test folder when the test
            // variable names one.
            let (backups, testFolder) = try FileBackups.fromEnvironment(environment)
            return .serve(backups: backups, notice: testFolder.map(FileBackups.testModeNotice(folder:)))
        } catch let error as FileBackups.TestFolderError {
            // The server stops before it reads a message. The words are the
            // core's, so the command line tool says the same.
            return .stop(lines: ["\(name): \(error.message) \(FileBackups.TestFolderError.detail)"], exitCode: 1)
        } catch {
            return .stop(lines: ["\(name): \(error.localizedDescription)"], exitCode: 1)
        }
    }

    /// The program as `main.swift` starts it. Returns the exit code.
    static func main() async -> Int32 {
        // A client that closes its end of a pipe must not end the server in
        // the middle of a file. With the default action, the next write to
        // the closed pipe raises SIGPIPE and the process dies. Ignored, the
        // write fails with an error, and the run completes.
        signal(SIGPIPE, SIG_IGN)

        let environment = ProcessInfo.processInfo.environment
        switch startup(arguments: Array(CommandLine.arguments.dropFirst()), environment: environment) {
        case .print(let text):
            write(text, to: .standardOutput)
            return 0
        case .stop(let lines, let exitCode):
            lines.forEach { write($0, to: .standardError) }
            return exitCode
        case .serve(let backups, let notice):
            if let notice { write(notice, to: .standardError) }
            return await serve(
                ToolEnvironment(locator: ToolLocator(pathVariable: environment["PATH"]),
                                runner: SystemProcessRunner(), backups: backups))
        }
    }

    /// The signals with which a client stops the server. An MCP client
    /// sends `SIGTERM` when it shuts a server down.
    static let stopSignals = [SIGTERM, SIGINT, SIGHUP]

    /// Runs the server until standard input closes or a signal comes, and
    /// every answer that will come is written.
    private static func serve(_ environment: ToolEnvironment) async -> Int32 {
        // swift-log prints on standard output until it is told otherwise.
        LoggingSystem.bootstrap { StreamLogHandler.standardError(label: $0) }
        var logger = Logger(label: name)
        logger.logLevel = .warning

        let queue = CallQueue()
        let server = Server(
            name: name, version: DesqueezeVersion.current, title: "Plateworks Desqueeze",
            instructions: ToolCatalog.instructions, capabilities: .init(tools: .init(listChanged: false)))
        await ToolHandlers(environment: environment, queue: queue).register(on: server)
        let transport = AnsweringTransport(logger: logger, queue: queue)

        // A server that ended at once would leave a backup beside the file
        // that exiftool was writing (design 12.2). At a signal, no call that
        // waits starts, the call in work stops after its current file, its
        // report is written, and the program ends with 0. With no call in
        // work, it ends at once.
        let watcher = InterruptWatcher(signals: stopSignals) {
            queue.stop()
            Task { await transport.stopReading() }
        }
        defer { withExtendedLifetime(watcher) {} }

        do {
            try await server.start(transport: transport)
        } catch {
            write("\(name): The server could not start: \(error.localizedDescription)", to: .standardError)
            return 1
        }
        await server.waitUntilCompleted()
        // The transport has closed the queue and waited for the call in
        // work. This is the last check that no file is in work when the
        // program ends.
        queue.close()
        await queue.waitForCallInWork()
        return 0
    }

    private static func write(_ text: String, to handle: FileHandle) {
        // A closed pipe is not worth a crash.
        try? handle.write(contentsOf: Data((text + "\n").utf8))
    }
}
