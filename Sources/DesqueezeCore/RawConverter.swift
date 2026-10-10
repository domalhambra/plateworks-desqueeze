import Foundation

public enum ConvertError: Error, Equatable {
    /// The conversion failed.
    ///
    /// - Parameters:
    ///   - partial: the `<base>.dng` that this conversion left behind, or
    ///     nil when it left none. It is never a DNG that was there before:
    ///     `AdobeConverter` proves that none was there when it starts. The
    ///     caller discards it (design, section 4.3).
    case failed(String, partial: URL? = nil)
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
    private let fileSize: @Sendable (String) -> Int?

    /// - Parameters:
    ///   - fileExists: whether a file is there. Tests inject it.
    ///   - fileSize: the size of a file in bytes, nil when it is not there.
    ///     Asked only for a DNG that `fileExists` has found.
    public init(
        executable: URL,
        runner: ProcessRunner = SystemProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        fileSize: @escaping @Sendable (String) -> Int? = {
            (try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? NSNumber)?.map(\.intValue)
        }
    ) {
        self.executable = executable
        self.runner = runner
        self.fileExists = fileExists
        self.fileSize = fileSize
    }

    public static func outputURL(for arw: URL) -> URL {
        arw.deletingPathExtension().appendingPathExtension("dng")
    }

    /// `-c` is lossless compression. `-d` is the output folder. The command
    /// line ignores the converter's window preferences.
    ///
    /// Only a pending ARW converts. When `<base>.dng` exists already, the real
    /// converter writes `<base>_1.dng`, so this method refuses to start it.
    /// That refusal reports no partial output: the DNG is not ours.
    ///
    /// A conversion that fails after the converter started (a non-zero exit,
    /// a signal, a runner error, or exit 0 with an empty DNG) and leaves a
    /// `<base>.dng` reports it as `ConvertError.failed`'s `partial`. A signal
    /// or runner error that leaves no file is thrown as it came.
    ///
    /// Never pass `-h`: it opens a window and the process never returns.
    public func convert(_ arw: URL) throws -> URL {
        let output = Self.outputURL(for: arw)
        // The scan sends only pending files. This guard holds the rule at the
        // last moment, for a DNG that appeared after the scan.
        guard !fileExists(output.path) else {
            throw ConvertError.failed("A DNG with this name exists already. Not converted.")
        }
        let result: ProcessResult
        do {
            result = try runner.run(executable, ["-c", "-d", arw.deletingLastPathComponent().path, arw.path])
        } catch {
            // The converter started and did not finish, for example when a
            // signal ended it. It may have begun the DNG.
            guard fileExists(output.path) else { throw error }
            throw ConvertError.failed(error.localizedDescription, partial: output)
        }
        // From here on, a `<base>.dng` is this run's: the guard above proved
        // that none was there before the converter started.
        guard result.exitCode == 0 else {
            throw ConvertError.failed("Adobe DNG Converter returned \(result.exitCode).",
                                      partial: fileExists(output.path) ? output : nil)
        }
        // The converter returns 0 for a file it cannot read, and makes no DNG.
        guard fileExists(output.path) else {
            throw ConvertError.failed("Adobe DNG Converter made no DNG. It may not support this file.")
        }
        // A DNG with no bytes is not a DNG.
        guard (fileSize(output.path) ?? 0) > 0 else {
            throw ConvertError.failed("Adobe DNG Converter made an empty DNG.", partial: output)
        }
        return output
    }
}
