import Foundation

/// What a program that ran and exited gave: its exit code and its output.
public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// A program that a signal ended, for example `kill` or a crash.
///
/// Such a program has no exit code. `Process` reports the signal number in its
/// place, so a runner that returned it as an exit code would make "ended by
/// signal 15" read as "returned 15", and a caller that accepts a partial
/// output would take half a result as a whole one. So the runner throws this,
/// and each caller turns it into the note for its file with the words of
/// `errorDescription`.
public struct ProcessSignalError: Error, LocalizedError, Equatable, Sendable {
    public let signal: Int32
    /// What the program wrote before it ended.
    public let stdout: String
    public let stderr: String

    public init(signal: Int32, stdout: String, stderr: String) {
        self.signal = signal
        self.stdout = stdout
        self.stderr = stderr
    }

    public var errorDescription: String? { "The program was ended by signal \(signal)." }
}

/// Starts a program with arguments and waits for it. No shell is involved, so
/// a path with spaces is one argument.
///
/// - Throws: when the program cannot start, and `ProcessSignalError` when a
///   signal ended it. A program that ran and exited gives a `ProcessResult`,
///   whatever its exit code.
public protocol ProcessRunner: Sendable {
    func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult
}

/// The real runner. It starts each program with `Process`.
public struct SystemProcessRunner: ProcessRunner {
    public init() {}

    public func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        // Foundation autoreleases the pipe handles. Without this pool, a caller
        // that loops holds two descriptors for each call until its own pool drains.
        try autoreleasepool {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            try process.run()

            // Read both pipes at the same time. A program that fills one pipe
            // while this code waits on the other would block forever. A serial
            // queue always gets a thread of its own, also when every thread of
            // the Swift concurrency pool is blocked in this method.
            let errData = DataBox()
            let group = DispatchGroup()
            DispatchQueue(label: "org.plateworks.desqueeze.stderr").async(group: group) {
                errData.value = err.fileHandleForReading.readDataToEndOfFile()
            }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            group.wait()
            process.waitUntilExit()

            let stdout = String(decoding: outData, as: UTF8.self)
            let stderr = String(decoding: errData.value, as: UTF8.self)
            // For a program that a signal ended, `terminationStatus` is the
            // signal number, not an exit code.
            if process.terminationReason == .uncaughtSignal {
                throw ProcessSignalError(signal: process.terminationStatus, stdout: stdout, stderr: stderr)
            }
            return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
        }
    }
}

private final class DataBox: @unchecked Sendable {
    var value = Data()
}
