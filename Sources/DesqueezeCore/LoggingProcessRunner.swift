import Foundation

/// Runs each program through another runner, and writes what happened to a
/// sink: the command line, the exit code, and the raw output. For `--verbose`.
///
/// ```
/// $ /opt/homebrew/bin/exiftool -m '-SubIFD:DefaultScale=1.5 1' '/Volumes/Card/Shoot 1/a.dng'
///   exit 0
///   stdout:     1 image files updated
/// ```
public struct LoggingProcessRunner: ProcessRunner {
    private let runner: ProcessRunner
    private let sink: @Sendable (String) -> Void

    /// - Parameters:
    ///   - runner: the runner that starts each program.
    ///   - sink: gets one line at a time, with no line end.
    public init(wrapping runner: ProcessRunner, sink: @escaping @Sendable (String) -> Void) {
        self.runner = runner
        self.sink = sink
    }

    public func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        // Before the program starts: a program that never returns is named.
        sink("$ " + ([executable.path] + arguments).map(Self.quoted).joined(separator: " "))
        let result: ProcessResult
        do {
            result = try runner.run(executable, arguments)
        } catch let ended as ProcessSignalError {
            sink("  ended by signal \(ended.signal)")
            for line in Self.lines(ended.stdout) { sink("  stdout: \(line)") }
            for line in Self.lines(ended.stderr) { sink("  stderr: \(line)") }
            throw ended
        } catch {
            sink("  did not start: \(error.localizedDescription)")
            throw error
        }
        sink("  exit \(result.exitCode)")
        for line in Self.lines(result.stdout) { sink("  stdout: \(line)") }
        for line in Self.lines(result.stderr) { sink("  stderr: \(line)") }
        return result
    }

    /// The lines of some output, with no empty line for its last line end.
    private static func lines(_ output: String) -> [Substring] {
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    /// One argument, written so that it reads as one: as it is when it holds
    /// only plain characters, and in single quotes when it holds a space or
    /// any other character. `/bin/sh` reads the result back as the argument.
    static func quoted(_ argument: String) -> String {
        let plain = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-"
        if !argument.isEmpty, argument.allSatisfy(plain.contains) { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
