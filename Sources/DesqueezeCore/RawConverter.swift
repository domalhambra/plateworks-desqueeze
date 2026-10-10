import Foundation

public enum ConvertError: Error, Equatable {
    /// The conversion failed.
    ///
    /// - Parameters:
    ///   - partial: the `<base>.dng` that this conversion left behind, or
    ///     nil when it left none. It is never a DNG that was there before:
    ///     a converter proves that nothing had the name when it starts, and
    ///     reports a partial only when its program ran (`ConverterRules`).
    ///     The caller discards it (design, section 4.3).
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

/// The output of a conversion, `<base>.dng`, and what a converter asks the
/// disk about it.
public enum ConverterOutput {
    /// The DNG that a conversion of `arw` makes: the same folder, the same
    /// base name.
    public static func url(for arw: URL) -> URL {
        arw.deletingPathExtension().appendingPathExtension("dng")
    }

    /// True when anything has this name: a file, a folder, or a symbolic
    /// link, also a link that points at nothing.
    ///
    /// `lstat` does not follow a link. `FileManager.fileExists` does, so it
    /// says that a dangling link is not there, and a converter would then
    /// write through the link or beside it.
    public static func exists(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// The size of the file in bytes. Nil when it cannot be read: nothing is
    /// there, or the disk gave an error. Nil is not 0.
    public static func size(atPath path: String) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attributes[.size] as? NSNumber)?.intValue
    }
}

/// The rules of design 4.3, step 1, that hold for every converter. They are
/// here and nowhere else. A converter gives its name and its program.
///
/// 1. **Before the start.** When anything has the name `<base>.dng`, the
///    program is not started. That refusal reports no partial output: the
///    thing at the name is not ours.
/// 2. **A partial output is reported only when the program ran:** after a
///    signal ended it, after a non-zero exit, after exit 0 with an empty
///    file, or after `complete` failed. Rule 1 proved that the name was free,
///    so a `<base>.dng` is then this run's.
/// 3. **Any other error from the runner passes on as it came,** with no
///    partial: for example, the program could not start. The program never
///    ran, so a file at the name is not ours.
/// 4. **An unknown size is not an empty file.** When the size cannot be read
///    after exit 0, the result is "made no DNG", with no partial.
struct ConverterRules: Sendable {
    /// The converter, as a sentence names it: `dnglab returned 7.`
    let name: String
    let exists: @Sendable (String) -> Bool
    let size: @Sendable (String) -> Int?

    /// - Parameters:
    ///   - start: runs the program for this ARW. It gets the output URL.
    ///   - complete: what the converter does to the DNG after its program
    ///     made one with bytes. When it throws, the conversion failed, and
    ///     the DNG is the partial output. The words are the error's own.
    /// - Returns: the DNG.
    func convert(
        _ arw: URL, start: (URL) throws -> ProcessResult, complete: (URL) throws -> Void = { _ in }
    ) throws -> URL {
        let output = ConverterOutput.url(for: arw)
        // The scan sends only pending files. This guard holds the rule at the
        // last moment, for a DNG that appeared after the scan.
        guard !exists(output.path) else {
            throw ConvertError.failed("A DNG with this name exists already. Not converted.")
        }
        let result: ProcessResult
        do {
            result = try start(output)
        } catch let signal as ProcessSignalError {
            // The program ran, and a signal ended it. It may have begun the
            // DNG. With no file, the signal is thrown as it came.
            guard exists(output.path) else { throw signal }
            throw ConvertError.failed(signal.localizedDescription, partial: output)
        }
        // From here on, a `<base>.dng` is this run's: the guard above proved
        // that nothing had the name before the program ran.
        guard result.exitCode == 0 else {
            throw ConvertError.failed("\(name) returned \(result.exitCode).",
                                      partial: exists(output.path) ? output : nil)
        }
        // Adobe's converter returns 0 for a file it cannot read, and makes no
        // DNG. A size that cannot be read says the same: no DNG is known.
        guard exists(output.path), let bytes = size(output.path) else {
            throw ConvertError.failed("\(name) made no DNG. It may not support this file.")
        }
        // A DNG with no bytes is not a DNG.
        guard bytes > 0 else {
            throw ConvertError.failed("\(name) made an empty DNG.", partial: output)
        }
        do {
            try complete(output)
        } catch {
            throw ConvertError.failed(DesqueezeJob.describe(error), partial: output)
        }
        return output
    }
}

public struct AdobeConverter: RawConverter {
    private let executable: URL
    private let runner: ProcessRunner
    private let rules: ConverterRules

    /// - Parameters:
    ///   - fileExists: whether anything has this name. It must not follow a
    ///     symbolic link. Tests inject it.
    ///   - fileSize: the size of a file in bytes, nil when it cannot be read.
    ///     Asked only for a DNG that `fileExists` has found.
    public init(
        executable: URL,
        runner: ProcessRunner = SystemProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = { ConverterOutput.exists(atPath: $0) },
        fileSize: @escaping @Sendable (String) -> Int? = { ConverterOutput.size(atPath: $0) }
    ) {
        self.executable = executable
        self.runner = runner
        rules = ConverterRules(name: "Adobe DNG Converter", exists: fileExists, size: fileSize)
    }

    /// `ConverterOutput.url(for:)`, under its first name.
    public static func outputURL(for arw: URL) -> URL {
        ConverterOutput.url(for: arw)
    }

    /// `-c` is lossless compression. `-d` is the output folder. The command
    /// line ignores the converter's window preferences.
    ///
    /// Only a pending ARW converts. When `<base>.dng` exists already, the real
    /// converter writes `<base>_1.dng`, so this method refuses to start it.
    ///
    /// The refusal, and what a failed conversion reports as its partial DNG,
    /// are the rules of `ConverterRules`, which every converter follows.
    ///
    /// Never pass `-h`: it opens a window and the process never returns.
    public func convert(_ arw: URL) throws -> URL {
        try rules.convert(arw, start: { _ in
            try runner.run(executable, ["-c", "-d", arw.deletingLastPathComponent().path, arw.path])
        })
    }
}
