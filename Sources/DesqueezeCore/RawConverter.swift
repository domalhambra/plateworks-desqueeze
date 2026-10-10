import Foundation

/// Why a conversion failed, and the file that it left behind.
public enum ConvertError: Error, Equatable {
    /// The conversion failed. The caller may give the ARW to the next
    /// converter.
    ///
    /// - Parameters:
    ///   - partial: the file that this conversion left behind, or nil when
    ///     it left none. The caller discards it (design 4.3 and 13.3). For
    ///     either converter it is the work file of the ARW
    ///     (`ConverterOutput.workURL`), and never `<base>.dng`: no converter
    ///     writes to that name. A converter reports it only when its program
    ///     ran (`ConverterRules`).
    case failed(String, partial: URL? = nil)
    /// The conversion failed for a reason that holds for every converter,
    /// so the caller does not give the ARW to the next one:
    ///
    /// - Something took the name `<base>.dng` while the converter worked.
    /// - A leftover file of exiftool, `<base>.dng_exiftool_tmp`, is beside
    ///   the ARW.
    /// - The Trash refused the leftover work file of an earlier run, or
    ///   exiftool's leftover beside it.
    /// - A folder or a link has the name of that work file or of that
    ///   leftover. The app does not remove it.
    /// - A name that the conversion needs would be longer than a file name
    ///   can be (design 13.9).
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
/// gets an ARW. Both follow `ConverterRules`: each writes the hidden work
/// file of the ARW, and the DNG gets its name only when it is complete.
public protocol RawConverter: Sendable {
    /// - Parameters:
    ///   - arw: the raw file. It is read, and never changed.
    ///   - facts: what the ARW says about itself, from the one read that
    ///     the run makes for all pending files. `ARWFacts.none` when nothing
    ///     is known. A converter reads no facts itself.
    /// - Throws: `ConvertError.failed` when the conversion failed, and
    ///   `ConvertError.failedForAll` when it failed for a reason that holds
    ///   for every converter, so the caller does not try the next one. The
    ///   runner's own error passes on as it came when the program could not
    ///   start, and when a signal ended it and it left no file.
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
    /// - Parameter exiftool: reads the facts of each ARW, and writes
    ///   dnglab's match.
    /// - Parameter dnglab: nil when dnglab is not installed.
    /// - Parameter adobe: Adobe DNG Converter, or nil when it is not
    ///   installed.
    /// - Parameter runner: starts every program.
    /// - Parameter backups: where each converter sends the work file that
    ///   an earlier run left, and exiftool's leftover beside it (design
    ///   13.3, step 1). Give the backups of the job, so every discarded file
    ///   goes to one place. There is no default, so no caller reaches the
    ///   Trash by leaving it out.
    /// - Parameter verbose: gets one line for each leftover that a converter
    ///   discarded in step 1, after `backups` took it:
    ///   `Removed a leftover work file: <name>`. Give it the sink of the
    ///   `LoggingProcessRunner`, so the line stands before the command of
    ///   the converter. The default says nothing.
    public init(exiftool: URL, dnglab: URL?, adobe: URL?, runner: ProcessRunner = SystemProcessRunner(),
                backups: BackupHandling, verbose: @escaping @Sendable (String) -> Void = { _ in }) {
        let discard: @Sendable (URL) throws -> Void = {
            try backups.trashFile($0)
            verbose(ConverterRules.removedLeftover(named: $0.lastPathComponent))
        }
        self.init(dnglab: dnglab.map {
                      DnglabConverter(executable: $0, exiftool: exiftool, runner: runner, discardLeftover: discard)
                  },
                  adobe: adobe.map { AdobeConverter(executable: $0, runner: runner, discardLeftover: discard) },
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

    /// The work file of a conversion of `arw` (design 13.3):
    /// `.<base>.desqueeze-work.dng`, in the folder of the ARW. The converter
    /// writes it, dnglab's match goes into it, and only then it gets the
    /// name `<base>.dng`. Both converters write it.
    ///
    /// This is the only place that makes the name. It starts with a period,
    /// so the scan, Finder and Lightroom do not see the file. It says that
    /// the file is this app's own: a work file that an earlier run left is
    /// discarded with no question.
    public static func workURL(for arw: URL) -> URL {
        let base = arw.deletingPathExtension().lastPathComponent
        return arw.deletingLastPathComponent().appendingPathComponent(".\(base).desqueeze-work.dng")
    }

    /// The most UTF-16 units that a file name can have on the volumes of a
    /// Mac (design 13.9). Measured 2026-10-10 on APFS, HFS+ and ExFAT: a
    /// name of 255 "あ", which is 765 bytes of UTF-8, is made, and a name of
    /// 256 is refused. So the limit is not in bytes.
    public static let longestFileName = 255

    /// The longest name that the app makes for `arw`: the temporary file
    /// that exiftool makes beside the work file while it writes dnglab's
    /// match, `.<base>.desqueeze-work.dng_exiftool_tmp`. It comes from the
    /// two functions that make those names, so it follows a change of
    /// either one.
    static func longestName(for arw: URL) -> String {
        exiftoolLeftoverURL(for: workURL(for: arw)).lastPathComponent
    }

    /// True when the longest name that the app makes for `arw` is longer
    /// than a file name can be (design 13.9). No converter starts for such
    /// an ARW (`ConverterRules`, rule 0), and the dry run plans no
    /// conversion for it. Both ask here, so the two cannot disagree.
    ///
    /// The name is counted in UTF-16 units of its decomposed form. HFS+
    /// stores an accented letter as its two parts, so "é" is two units
    /// there. The rule is one for both converters, also for Adobe DNG
    /// Converter, which starts no exiftool on the work file: a name must
    /// not convert with one converter and fail with the other.
    public static func nameIsTooLong(for arw: URL) -> Bool {
        longestName(for: arw).decomposedStringWithCanonicalMapping.utf16.count > longestFileName
    }

    /// What a note says after it names a file to delete, when that file is
    /// hidden: the work file is. The only place that makes the sentence.
    public static let hiddenFileHint = "It is a hidden file: in Finder, press Command-Shift-Period to see it."

    /// `hiddenFileHint` with a space before it when `name` starts with a
    /// period, and an empty string for any other name. A note puts it after
    /// the sentence that names the file.
    static func hint(forFileNamed name: String) -> String {
        name.hasPrefix(".") ? " " + hiddenFileHint : ""
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

    /// True only for a regular file. False for a folder, for a symbolic
    /// link, also one that points at a regular file, and when nothing has
    /// the name. `lstat` does not follow a link.
    public static func isRegularFile(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
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
/// and what it does to the file before the file gets its name: dnglab writes
/// its match, and Adobe DNG Converter does nothing.
///
/// **No program writes `<base>.dng`.** Each one writes the work file of the
/// ARW (`ConverterOutput.workURL`), and the work file gets the name
/// `<base>.dng` only when it is complete. So `<base>.dng` is never reported
/// as a partial output, and a DNG that this conversion did not make is never
/// touched.
///
/// 0. **A name that is too long** (design 13.9). The longest name that a
///    conversion needs is exiftool's temporary file beside the work file
///    (`ConverterOutput.longestName`). When it has more UTF-16 units than a
///    file name can have, no program is started and the disk is asked
///    nothing. A program would fail on that name with the system's words,
///    or with words about the photo. The failure holds for every converter,
///    and the sentence says what to do.
/// 1. **Before the start.** When anything has the name `<base>.dng`, the
///    program is not started. That refusal reports no partial output: the
///    thing at the name is not ours.
/// 2. **A leftover file of exiftool beside the DNG's name stops the ARW,
///    for every converter.** When `<base>.dng_exiftool_tmp` is there, no
///    program is started: exiftool refuses to write beside its own leftover,
///    so the tag step could never pass. The sentence names the file. The
///    file stays where it is: it is not this app's to remove, it is not
///    moved to the Trash, and it is not a partial output. Nothing else is
///    discarded either.
/// 3. **The two leftovers of this app are discarded** (design 13.3, step
///    1): the work file, and `<work file>_exiftool_tmp`, which exiftool
///    leaves when it ends hard in dnglab's match. A run that ended hard left
///    them, and their names say that they are this app's own.
///    `discardLeftover` takes each one that is there, the work file first.
///    When that fails, no program starts, the failure holds for every
///    converter, and the sentence names the file.
///
///    **Only a regular file is discarded.** A folder or a symbolic link at
///    either name, also a link that points at nothing, is no leftover of a
///    run. It stops the ARW in the same way, with the same sentence, and
///    nothing moves: both names are looked at before the first file is
///    taken.
/// 4. **A partial output is reported only when the program ran:** after a
///    signal ended it, after a non-zero exit, after exit 0 with an empty
///    file, after `match` failed, or after the rename failed. It is always
///    the work file, and only when the work file is there: a work file that
///    vanished is not reported, so no note names a file that is not there.
/// 5. **Any other error from the runner passes on as it came,** with no
///    partial: for example, the program could not start. The program never
///    ran, so a file at the name is not this conversion's.
/// 6. **An unknown size is not an empty file.** When the size cannot be read
///    after exit 0, the result is "made no DNG", with no partial.
/// 7. **An exit code that says "I did not touch the output" reports no
///    partial.** dnglab returns 6 for an output that exists already. The
///    file at the name is then not this conversion's.
/// 8. **The rename never replaces** (design 13.3, step 5, `ExclusiveRename`).
///    When it finds the name `<base>.dng` taken, another program made that
///    file while the converter worked. The file is not touched. The failure
///    holds for every converter, with the sentence of rule 1, and the work
///    file is the partial output.
struct ConverterRules: Sendable {
    /// What every converter says when something has the name `<base>.dng`:
    /// before the start, and at the rename of the work file.
    static let nameTaken = "A DNG with this name exists already. Not converted."

    /// What every converter says when a name that the conversion needs
    /// would be longer than a file name can be (rule 0). The only place
    /// that makes this sentence.
    static let nameTooLong = "The file name is too long. Shorten it, then run again."

    /// What a converter says about a file that an earlier run or an earlier
    /// exiftool left, and that the app does not remove. The only place that
    /// makes this sentence.
    static func leftover(named name: String) -> String {
        "A leftover file, \(name), is beside this photo.\(ConverterOutput.hint(forFileNamed: name)) "
            + "Delete it, then run again."
    }

    /// What `--verbose` says after step 1 discarded a leftover: the app
    /// removed a hidden file that the person never saw. The only place that
    /// makes this line.
    static func removedLeftover(named name: String) -> String {
        "Removed a leftover work file: \(name)"
    }

    /// The converter, as a sentence names it: `dnglab returned 7.`
    let name: String
    let exists: @Sendable (String) -> Bool
    let size: @Sendable (String) -> Int?
    /// True only for a regular file: not for a folder, and not for a link.
    let isRegularFile: @Sendable (String) -> Bool
    /// Rule 3. It gets only the two leftovers of the ARW in work:
    /// `ConverterOutput.workURL`, and `<work file>_exiftool_tmp`.
    let discardLeftover: @Sendable (URL) throws -> Void
    /// Rule 8.
    let rename: @Sendable (URL, URL) -> ExclusiveRename.Outcome
    /// The program's own reason for a non-zero exit, from what it printed.
    /// It follows the sentence with the exit code, on the same line. Nil
    /// when the program gave none: the sentence then stands alone.
    ///
    /// In what it gets, the path of the work file is its name already
    /// (`naming`): a sentence names a file beside the photo by its name.
    var reason: @Sendable (ProcessResult) -> String? = { _ in nil }
    /// The exit codes of rule 7.
    var exitCodesThatLeaveTheOutputAlone: Set<Int32> = []

    /// - Parameters:
    ///   - start: runs the program for this ARW. It gets the work file, and
    ///     the program must write there.
    ///   - match: what the converter does to the work file after its
    ///     program made one with bytes, and before the rename. When it
    ///     throws, the conversion failed, and the work file is the partial
    ///     output. The words are the error's own. A `ConvertError` passes on
    ///     as it came.
    /// - Returns: `<base>.dng`. No work file is left.
    func convert(
        _ arw: URL, start: (URL) throws -> ProcessResult, match: (URL) throws -> Void = { _ in }
    ) throws -> URL {
        let output = ConverterOutput.url(for: arw)
        let work = ConverterOutput.workURL(for: arw)
        // Rule 0, before any question to the disk: no file can have this
        // name, so no converter could write it.
        guard !ConverterOutput.nameIsTooLong(for: arw) else {
            throw ConvertError.failedForAll(Self.nameTooLong)
        }
        // The scan sends only pending files. This guard holds the rule at the
        // last moment, for a DNG that appeared after the scan.
        guard !exists(output.path) else {
            throw ConvertError.failed(Self.nameTaken)
        }
        // exiftool writes the DNG in the tag step. Its leftover there is
        // not this app's to remove.
        let tagLeftover = ConverterOutput.exiftoolLeftoverURL(for: output)
        guard !exists(tagLeftover.path) else {
            throw ConvertError.failedForAll(Self.leftover(named: tagLeftover.lastPathComponent))
        }
        try discardTheLeftovers(of: work)
        let result: ProcessResult
        do {
            result = try start(work)
        } catch let signal as ProcessSignalError {
            // The program ran, and a signal ended it. It may have begun its
            // file. With no file, the signal is thrown as it came.
            guard exists(work.path) else { throw signal }
            throw ConvertError.failed(signal.localizedDescription, partial: work)
        }
        // From here on, a file at the name of the work file is this
        // conversion's: the name is this app's own, and rule 3 left nothing
        // there before the program ran.
        guard result.exitCode == 0 else {
            var text = "\(name) returned \(result.exitCode)."
            // The reason is the program's, and the next sentence can be the
            // job's, about the partial DNG. A period keeps the two apart.
            if let reason = reason(Self.naming(work, in: result)) {
                text += " " + reason + (reason.hasSuffix(".") ? "" : ".")
            }
            let wrote = !exitCodesThatLeaveTheOutputAlone.contains(result.exitCode)
            throw ConvertError.failed(text, partial: wrote && exists(work.path) ? work : nil)
        }
        // Adobe's converter returns 0 for a file it cannot read, and makes no
        // DNG. A size that cannot be read says the same: no DNG is known.
        guard exists(work.path), let bytes = size(work.path) else {
            throw ConvertError.failed("\(name) made no DNG. It may not support this file.")
        }
        // A DNG with no bytes is not a DNG.
        guard bytes > 0 else {
            throw ConvertError.failed("\(name) made an empty DNG.", partial: work)
        }
        do {
            try match(work)
        } catch let error as ConvertError {
            throw error
        } catch {
            throw ConvertError.failed(DesqueezeJob.describe(error), partial: ifThere(work))
        }
        try move(work, to: output)
        return output
    }

    /// What a program printed, with the name of the work file where the
    /// program wrote its whole path. dnglab says `Already exists: <path>`
    /// for exit code 6. The change is made before `reason` cuts the words
    /// to their limit, so a long path is never left cut in the middle.
    static func naming(_ work: URL, in result: ProcessResult) -> ProcessResult {
        func named(_ text: String) -> String {
            text.replacingOccurrences(of: work.path, with: work.lastPathComponent)
        }
        return ProcessResult(exitCode: result.exitCode, stdout: named(result.stdout), stderr: named(result.stderr))
    }

    /// The work file as the partial output of a step that came after the
    /// program: nil when the file is gone. Another program, or the person,
    /// can take it away, and a rename then fails with "No such file".
    private func ifThere(_ work: URL) -> URL? {
        exists(work.path) ? work : nil
    }

    /// Rule 3. The names of the work file and of exiftool's leftover beside
    /// it say that they are this app's own, so each regular file that is
    /// there is discarded with no question. When one cannot be, or when a
    /// folder or a link has one of the names, the conversion fails for every
    /// converter, and the sentence names the thing to delete.
    private func discardTheLeftovers(of work: URL) throws {
        let leftovers = [work, ConverterOutput.exiftoolLeftoverURL(for: work)].filter { exists($0.path) }
        // Before the first file moves: a run leaves a regular file, and
        // nothing else. A folder can hold the person's files, and a link
        // is not this app's to judge.
        for leftover in leftovers where !isRegularFile(leftover.path) {
            throw ConvertError.failedForAll(Self.leftover(named: leftover.lastPathComponent))
        }
        for leftover in leftovers {
            do {
                try discardLeftover(leftover)
            } catch {
                throw ConvertError.failedForAll(Self.leftover(named: leftover.lastPathComponent))
            }
        }
    }

    /// Rule 8. The work file is complete, and gets its name.
    private func move(_ work: URL, to dng: URL) throws {
        switch rename(work, dng) {
        case .moved:
            return
        case .nameTaken:
            // Another program made `<base>.dng` while the converter worked.
            // Every converter would find the name taken, so no one tries.
            throw ConvertError.failedForAll(Self.nameTaken, partial: ifThere(work))
        case .failed(let code):
            throw ConvertError.failed(
                "The DNG could not get the name \(dng.lastPathComponent): \(ExclusiveRename.Outcome.words(for: code)).",
                partial: ifThere(work))
        }
    }
}

/// Converts with Adobe DNG Converter, the optional backup (design 13.3).
///
/// As dnglab's converter, it does not write `<base>.dng`. It gives Adobe DNG
/// Converter the name of the hidden work file (`ConverterOutput.workURL`),
/// and the DNG gets its name only when it is complete. The steps, after the
/// checks of `ConverterRules`:
///
/// 1. A work file that is there already is the leftover of a run that ended
///    hard, and so is `<work file>_exiftool_tmp`. `discardLeftover` takes
///    them. When that fails, the converter does not start. A folder or a
///    link at either name is not taken, and stops the conversion too.
/// 2. `"<Adobe DNG Converter>" -c -d <folder> -o <work file name> <in.ARW>`.
/// 3. A rename of the work file to `<base>.dng` that fails when anything has
///    that name (`ExclusiveRename`).
///
/// There is no match and no read-back: Adobe's DNG is the reference that
/// dnglab's match copies.
///
/// The conversion passes only when the exit code is 0, the work file has
/// bytes, and the rename passed. All three are needed: Adobe DNG Converter
/// returns 0 for a file that it cannot read, and makes no DNG. Ended by a
/// signal, it can leave a file of 0 bytes.
///
/// **Why step 1 comes first.** With the name of the work file taken, Adobe
/// DNG Converter 18.7 does not write over it: it writes a second file,
/// `.<base>.desqueeze-work_1.dng`, and returns 0 (tested 2026-10-09). Step 1
/// leaves the name free, so that file is never made.
///
/// Never pass `-h`: it opens a window and the process never returns.
public struct AdobeConverter: RawConverter {
    private let executable: URL
    private let runner: ProcessRunner
    private let rules: ConverterRules

    /// - Parameters:
    ///   - executable: Adobe DNG Converter, the program inside the app.
    ///   - runner: starts the converter.
    ///   - discardLeftover: takes away what an earlier run left. It gets
    ///     only `ConverterOutput.workURL` of the ARW in work, and
    ///     `<work file>_exiftool_tmp`. The app gives
    ///     `BackupHandling.trashFile` of the job's backups, so the file goes
    ///     to the Trash. There is no default, so no caller reaches the Trash
    ///     by leaving it out.
    ///   - fileExists: whether anything has this name. It must not follow a
    ///     symbolic link. Tests inject it.
    ///   - fileSize: the size of a file in bytes, nil when it cannot be read.
    ///     Asked only for a file that `fileExists` has found.
    ///   - fileIsRegular: true only for a regular file. It must not follow
    ///     a symbolic link. Step 1 asks it about a leftover.
    ///   - rename: step 3. Tests inject it to drive each outcome.
    public init(
        executable: URL,
        runner: ProcessRunner = SystemProcessRunner(),
        discardLeftover: @escaping @Sendable (URL) throws -> Void,
        fileExists: @escaping @Sendable (String) -> Bool = { ConverterOutput.exists(atPath: $0) },
        fileSize: @escaping @Sendable (String) -> Int? = { ConverterOutput.size(atPath: $0) },
        fileIsRegular: @escaping @Sendable (String) -> Bool = { ConverterOutput.isRegularFile(atPath: $0) },
        rename: @escaping @Sendable (URL, URL) -> ExclusiveRename.Outcome = { ExclusiveRename.system.move($0, to: $1) }
    ) {
        self.executable = executable
        self.runner = runner
        rules = ConverterRules(name: ConverterKind.adobe.name, exists: fileExists, size: fileSize,
                               isRegularFile: fileIsRegular, discardLeftover: discardLeftover, rename: rename)
    }

    /// `-c` is lossless compression. `-d` is the output folder, and `-o` the
    /// name of the output in it: the name only, never a path. The command
    /// line ignores the converter's window preferences.
    ///
    /// Only a pending ARW converts. The refusal for a name that is taken,
    /// and what a failed conversion reports as its partial output, are the
    /// rules of `ConverterRules`, which every converter follows.
    ///
    /// The facts are not used: Adobe's converter reads the ARW itself, and
    /// its DNG is the one that the match copies.
    ///
    /// - Returns: the DNG at `<base>.dng`. No work file is left.
    public func convert(_ arw: URL, facts: ARWFacts = .none) throws -> Conversion {
        let dng = try rules.convert(arw, start: { work in
            try runner.run(executable, ["-c", "-d", arw.deletingLastPathComponent().path,
                                        "-o", work.lastPathComponent, arw.path])
        })
        return Conversion(dng: dng, unmatched: nil)
    }
}
