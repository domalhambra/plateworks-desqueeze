import Foundation

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

/// Starts a program with arguments and waits for it. No shell is involved, so
/// a path with spaces is one argument.
public protocol ProcessRunner: Sendable {
    func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult
}

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

            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(decoding: outData, as: UTF8.self),
                stderr: String(decoding: errData.value, as: UTF8.self)
            )
        }
    }
}

private final class DataBox: @unchecked Sendable {
    var value = Data()
}
