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
        // while this code waits on the other would block forever.
        let outData = DataBox()
        let errData = DataBox()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "org.plateworks.desqueeze.pipes", attributes: .concurrent)
        queue.async(group: group) { outData.value = out.fileHandleForReading.readDataToEndOfFile() }
        queue.async(group: group) { errData.value = err.fileHandleForReading.readDataToEndOfFile() }
        group.wait()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData.value, as: UTF8.self),
            stderr: String(decoding: errData.value, as: UTF8.self)
        )
    }
}

private final class DataBox: @unchecked Sendable {
    var value = Data()
}
