import Foundation

public enum ConvertError: Error, Equatable {
    case failed(String)
}

/// Converts one raw file to a DNG beside it and returns the DNG.
///
/// Version 1 has one implementation. A dnglab implementation is the planned
/// replacement for a public release, because Adobe's converter cannot be
/// bundled (design, section 3).
public protocol RawConverter: Sendable {
    func convert(_ arw: URL) throws -> URL
}

public struct AdobeConverter: RawConverter {
    private let executable: URL
    private let runner: ProcessRunner
    private let fileExists: @Sendable (String) -> Bool

    public init(
        executable: URL,
        runner: ProcessRunner = SystemProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.executable = executable
        self.runner = runner
        self.fileExists = fileExists
    }

    public static func outputURL(for arw: URL) -> URL {
        arw.deletingPathExtension().appendingPathExtension("dng")
    }

    /// `-c` is lossless compression. `-d` is the output folder. The command
    /// line ignores the converter's window preferences.
    ///
    /// Only a pending ARW converts. When `<base>.dng` exists already, the real
    /// converter writes `<base>_1.dng`, so this method refuses to start it.
    ///
    /// Never pass `-h`: it opens a window and the process never returns.
    public func convert(_ arw: URL) throws -> URL {
        let output = Self.outputURL(for: arw)
        // The scan sends only pending files. This guard holds the rule at the
        // last moment, for a DNG that appeared after the scan.
        guard !fileExists(output.path) else {
            throw ConvertError.failed("A DNG with this name exists already. Not converted.")
        }
        let result = try runner.run(executable, ["-c", "-d", arw.deletingLastPathComponent().path, arw.path])
        guard result.exitCode == 0 else {
            throw ConvertError.failed("Adobe DNG Converter returned \(result.exitCode).")
        }
        // The converter returns 0 for a file it cannot read, and makes no DNG.
        guard fileExists(output.path) else {
            throw ConvertError.failed("Adobe DNG Converter made no DNG. It may not support this file.")
        }
        return output
    }
}
