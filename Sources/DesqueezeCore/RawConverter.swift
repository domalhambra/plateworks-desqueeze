import Foundation

public enum ConvertError: Error, Equatable {
    /// The conversion failed. The caller may give the ARW to the next
    /// converter.
    ///
    /// - Parameters:
    ///   - partial: the file that this conversion left behind, or nil when
    ///     it left none. The caller discards it (design 4.3 and 13.3).
    ///     For Adobe DNG Converter it is `<base>.dng`, and never a DNG that
    ///     was there before: a converter proves that nothing had the name
    ///     when it starts, and reports a partial only when its program ran
    ///     (`ConverterRules`). For dnglab it is the work file
    ///     (`ConverterOutput.workURL`), and never `<base>.dng`.
    case failed(String, partial: URL? = nil)
    /// The conversion failed for a reason that holds for every converter,
    /// so the caller does not give the ARW to the next one:
    ///
    /// - Something took the name `<base>.dng` while dnglab worked.
    /// - A leftover file of exiftool is beside the ARW.
    /// - The Trash refused the leftover work file of an earlier run.
    ///
    /// `partial` is as for `failed`.
    case failedForAll(String, partial: URL? = nil)

    /// The sentence, with either case.
    public var text: String {
        switch self {
        case .failed(let text, _), .failedForAll(let text, _): return text
        }
    }

    /// The file that the conversion left behind, with either case.
    public var partial: URL? {
        switch self {
        case .failed(_, let partial), .failedForAll(_, let partial): return partial
        }
    }
}

/// What a conversion made.
public struct Conversion: Equatable, Sendable {
    /// The DNG, beside the ARW.
    public let dng: URL
    /// The rule of design 13.4 that kept this DNG from a full match. Nil
    /// when the DNG renders as Adobe's does: it is Adobe's own, or dnglab's
    /// with every rule met. The caller makes the note from it.
    public let unmatched: AdobeMatch.Rule?

    public init(dng: URL, unmatched: AdobeMatch.Rule?) {
        self.dng = dng
        self.unmatched = unmatched
    }
}

/// Converts one raw file to a DNG beside it.
///
/// There are two implementations (design 13). `DnglabConverter` converts
/// first, and writes the tags that make its DNG render as Adobe's does.
/// `AdobeConverter` is the optional backup. `ConverterChoice` says which one
/// gets an ARW. Both follow `ConverterRules`.
public protocol RawConverter: Sendable {
    /// - Parameter facts: what the ARW says about itself, from the one read
    ///   that the run makes for all pending files. `ARWFacts.none` when
    ///   nothing is known. A converter reads no facts itself.
    /// - Throws: `ConvertError.failed` when the conversion failed, and the
    ///   runner's own error when the program never ran.
    func convert(_ arw: URL, facts: ARWFacts) throws -> Conversion
}

/// The converters that are installed, each optional, and the reader of the
/// facts that choose between them (design 13).
///
/// `DesqueezeJob` and `DesqueezeOperations` take this in place of one
/// converter. With neither converter the ARW files wait, and the DNG files
/// still run.
public struct RawConverters: Sendable {
    /// Nil when dnglab is not installed.
    public var dnglab: RawConverter?
    /// Nil when Adobe DNG Converter is not installed. It is the optional
    /// backup.
    public var adobe: RawConverter?
    /// Reads the facts of the pending ARW files. It is asked only when
    /// dnglab is there: with Adobe alone, no fact changes the choice. Nil
    /// gives every ARW no facts.
    public var facts: ARWFactsReading?

    public init(dnglab: RawConverter?, adobe: RawConverter?, facts: ARWFactsReading?) {
        self.dnglab = dnglab
        self.adobe = adobe
        self.facts = facts
    }

    /// The real converters, for the tools that are installed. One runner
    /// starts every program, so a `LoggingProcessRunner` shows them all.
    ///
    /// - Parameter backups: where dnglab's converter sends the work file
    ///   that an earlier run left (design 13.3, step 1). Give the backups
    ///   of the job, so every discarded file goes to one place. There is no
    ///   default, so no caller reaches the Trash by leaving it out.
    public init(exiftool: URL, dnglab: URL?, adobe: URL?, runner: ProcessRunner = SystemProcessRunner(),
                backups: BackupHandling) {
        self.init(dnglab: dnglab.map {
                      DnglabConverter(executable: $0, exiftool: exiftool, runner: runner,
                                      discardLeftover: { try backups.trashFile($0) })
                  },
                  adobe: adobe.map { AdobeConverter(executable: $0, runner: runner) },
                  facts: ARWFactsReader(exiftool: exiftool, runner: runner))
    }

    /// No converter is installed.
    public static let none = RawConverters(dnglab: nil, adobe: nil, facts: nil)

    /// True when one converter or the other is installed, so a pending ARW
    /// can convert.
    public var canConvert: Bool { dnglab != nil || adobe != nil }

    subscript(kind: ConverterKind) -> RawConverter? {
        switch kind {
        case .dnglab: return dnglab
        case .adobe: return adobe
        }
    }
}

/// The output of a conversion, `<base>.dng`, the names of the files that
/// can be beside it while a conversion works, and what a converter asks the
/// disk about them.
public enum ConverterOutput {
    /// The DNG that a conversion of `arw` makes: the same folder, the same
    /// base name.
    public static func url(for arw: URL) -> URL {
        arw.deletingPathExtension().appendingPathExtension("dng")
    }

    /// The work file of dnglab's conversion of `arw` (design 13.3):
    /// `.<base>.desqueeze-work.dng`, in the folder of the ARW. dnglab writes
    /// it, the match goes into it, and only then it gets the name
    /// `<base>.dng`.
    ///
    /// This is the only place that makes the name. It starts with a period,
    /// so the scan, Finder and Lightroom do not see the file. It says that
    /// the file is this app's own: a work file that an earlier run left is
    /// discarded with no question.
    public static func workURL(for arw: URL) -> URL {
        let base = arw.deletingPathExtension().lastPathComponent
        return arw.deletingLastPathComponent().appendingPathComponent(".\(base).desqueeze-work.dng")
    }

    /// The file that exiftool makes beside `file` while it writes it:
    /// `<name>_exiftool_tmp`. exiftool that ends hard leaves it there, and
    /// refuses every later write of `file`.
    public static func exiftoolLeftoverURL(for file: URL) -> URL {
        URL(fileURLWithPath: file.path + "_exiftool_tmp")
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

/// The rules of design 4.3, step 1, and 13.3, that hold for every converter.
/// They are here and nowhere else. A converter gives its name, its program,
/// and the file that its program writes: `<base>.dng` for Adobe DNG
/// Converter, the work file for dnglab.
///
/// 1. **Before the start.** When anything has the name `<base>.dng`, the
///    program is not started. That refusal reports no partial output: the
///    thing at the name is not ours.
/// 2. **A leftover file of exiftool stops the ARW, for every converter.**
///    When `<base>.dng_exiftool_tmp` or `<work file>_exiftool_tmp` is
///    there, no program is started: exiftool refuses to write beside its own
///    leftover, so the tag step, or dnglab's match, could never pass. The
///    sentence names the file. The file stays where it is: it is not moved
///    to the Trash, and it is not a partial output.
/// 3. **A partial output is reported only when the program ran:** after a
///    signal ended it, after a non-zero exit, after exit 0 with an empty
///    file, or after `complete` failed. It is the file that the program
///    writes. For Adobe DNG Converter, rule 1 proved that the name was free,
///    so a `<base>.dng` is then this run's. For dnglab it is the work file,
///    whose name is this app's own.
/// 4. **Any other error from the runner passes on as it came,** with no
///    partial: for example, the program could not start. The program never
///    ran, so a file at the name is not ours.
/// 5. **An unknown size is not an empty file.** When the size cannot be read
///    after exit 0, the result is "made no DNG", with no partial.
/// 6. **An exit code that says "I did not touch the output" reports no
///    partial.** dnglab returns 6 for an output that exists already. The
///    file at the name is then not this conversion's.
struct ConverterRules: Sendable {
    /// What every converter says when something has the name `<base>.dng`:
    /// before the start, and at the rename of dnglab's work file.
    static let nameTaken = "A DNG with this name exists already. Not converted."

    /// What a converter says about a file that an earlier run or an earlier
    /// exiftool left, and that the app does not remove. The only place that
    /// makes this sentence.
    static func leftover(named name: String) -> String {
        "A leftover file, \(name), is beside this photo. Delete it, then run again."
    }

    /// The converter, as a sentence names it: `dnglab returned 7.`
    let name: String
    let exists: @Sendable (String) -> Bool
    let size: @Sendable (String) -> Int?
    /// The program's own reason for a non-zero exit, from what it printed.
    /// It follows the sentence with the exit code, on the same line. Nil
    /// when the program gave none: the sentence then stands alone.
    var reason: @Sendable (ProcessResult) -> String? = { _ in nil }
    /// The exit codes of rule 6.
    var exitCodesThatLeaveTheOutputAlone: Set<Int32> = []

    /// - Parameters:
    ///   - product: the file that the program writes. Nil is `<base>.dng`.
    ///   - prepare: runs after rules 1 and 2 passed, and before the program
    ///     starts. What it throws passes on as it came.
    ///   - start: runs the program for this ARW. It gets `product`.
    ///   - complete: what the converter does to the product after its
    ///     program made one with bytes. When it throws, the conversion
    ///     failed, and the product is the partial output. The words are the
    ///     error's own. A `ConvertError` passes on as it came.
    /// - Returns: `<base>.dng`.
    func convert(
        _ arw: URL, writing product: URL? = nil, prepare: () throws -> Void = {},
        start: (URL) throws -> ProcessResult, complete: (URL) throws -> Void = { _ in }
    ) throws -> URL {
        let output = ConverterOutput.url(for: arw)
        let product = product ?? output
        // The scan sends only pending files. This guard holds the rule at the
        // last moment, for a DNG that appeared after the scan.
        guard !exists(output.path) else {
            throw ConvertError.failed(Self.nameTaken)
        }
        // exiftool writes the DNG in the tag step, and the work file in
        // dnglab's match. Both names are checked for every converter.
        for file in [output, ConverterOutput.workURL(for: arw)] {
            let leftover = ConverterOutput.exiftoolLeftoverURL(for: file)
            guard !exists(leftover.path) else {
                throw ConvertError.failedForAll(Self.leftover(named: leftover.lastPathComponent))
            }
        }
        try prepare()
        let result: ProcessResult
        do {
            result = try start(product)
        } catch let signal as ProcessSignalError {
            // The program ran, and a signal ended it. It may have begun its
            // file. With no file, the signal is thrown as it came.
            guard exists(product.path) else { throw signal }
            throw ConvertError.failed(signal.localizedDescription, partial: product)
        }
        // From here on, a file at the product's name is this run's: for
        // `<base>.dng`, the guard above proved that nothing had the name
        // before the program ran, and the work file has this app's own name.
        guard result.exitCode == 0 else {
            var text = "\(name) returned \(result.exitCode)."
            // The reason is the program's, and the next sentence can be the
            // job's, about the partial DNG. A period keeps the two apart.
            if let reason = reason(result) { text += " " + reason + (reason.hasSuffix(".") ? "" : ".") }
            let wrote = !exitCodesThatLeaveTheOutputAlone.contains(result.exitCode)
            throw ConvertError.failed(text, partial: wrote && exists(product.path) ? product : nil)
        }
        // Adobe's converter returns 0 for a file it cannot read, and makes no
        // DNG. A size that cannot be read says the same: no DNG is known.
        guard exists(product.path), let bytes = size(product.path) else {
            throw ConvertError.failed("\(name) made no DNG. It may not support this file.")
        }
        // A DNG with no bytes is not a DNG.
        guard bytes > 0 else {
            throw ConvertError.failed("\(name) made an empty DNG.", partial: product)
        }
        do {
            try complete(product)
        } catch let error as ConvertError {
            throw error
        } catch {
            throw ConvertError.failed(DesqueezeJob.describe(error), partial: product)
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
        rules = ConverterRules(name: ConverterKind.adobe.name, exists: fileExists, size: fileSize)
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
    ///
    /// The facts are not used: Adobe's converter reads the ARW itself, and
    /// its DNG is the one that the match copies.
    public func convert(_ arw: URL, facts: ARWFacts = .none) throws -> Conversion {
        let dng = try rules.convert(arw, start: { _ in
            try runner.run(executable, ["-c", "-d", arw.deletingLastPathComponent().path, arw.path])
        })
        return Conversion(dng: dng, unmatched: nil)
    }
}
