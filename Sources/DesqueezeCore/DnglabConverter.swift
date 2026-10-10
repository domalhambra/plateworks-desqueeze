import Foundation

/// Converts with dnglab, then writes the tags that make the DNG render as
/// Adobe DNG Converter's does (design 13.2 to 13.4).
///
/// dnglab does not write `<base>.dng`. It writes a hidden **work file**
/// beside the ARW, `ConverterOutput.workURL`, and the DNG gets its name only
/// when it is complete and matched (design 13.3). First come the checks
/// that nothing has the name `<base>.dng`, and that no leftover of exiftool
/// from a tag step, `<base>.dng_exiftool_tmp`, is there. Then the steps.
/// Steps 1 and 5 are the same for Adobe DNG Converter, and `ConverterRules`
/// does them. Steps 2 to 4 are this converter's own:
///
/// 1. A work file that is there already is the leftover of a run that ended
///    hard, and so is `<work file>_exiftool_tmp`, which exiftool leaves when
///    it ends hard in step 3. `discardLeftover` takes them. When that fails,
///    no program starts. A folder or a link at either name is not taken,
///    and stops the conversion too.
/// 2. `dnglab convert --embed-raw false <in.ARW> <work file>`. Without the
///    flag dnglab puts the whole ARW inside the DNG.
/// 3. One exiftool call that writes every tag into the work file, with `-m`
///    and `-overwrite_original`. No backup is kept: the file is this run's
///    own, a moment old, and has no earlier state to keep.
/// 4. One exiftool call that reads every tag back. Numbers are compared as
///    numbers (`AdobeMatch.sameNumbers`), the file name as the text that
///    exiftool prints for it (`ExiftoolText.printed`).
/// 5. A rename of the work file to `<base>.dng` that fails when anything has
///    that name (`ExclusiveRename`).
///
/// The conversion passes only when dnglab returned 0, the work file has
/// bytes, the read-back equals what was written, and the rename passed.
/// When one of these fails after dnglab ran, the work file is this run's
/// partial output, by the rules of `ConverterRules`. `<base>.dng` is never
/// reported as partial: no converter writes to that name.
///
/// **When the rename finds the name taken,** another program made
/// `<base>.dng` while dnglab worked. That file is not touched. The error is
/// `ConvertError.failedForAll` with the sentence of the check before the
/// start, and the work file as the partial output.
///
/// **dnglab's exit code 6** says that its output exists, and that it did not
/// touch it. Step 1 removed the leftover, so the file came after that. It is
/// reported as a failure with no partial output. dnglab names the file by
/// its whole path, and the sentence gives its name only.
///
/// **The tags** are what `AdobeMatch` gives for the facts of the ARW, and
/// `IFD0:OriginalRawFileName`, which dnglab does not write with
/// `--embed-raw false` and which the pending rule needs (design 4.1). The
/// file name is written for every ARW. For an ARW with no full match, the
/// table tags are written as far as `AdobeMatch` gives them, and the result
/// carries the rule that failed.
///
/// Never pass `-f` to dnglab: it writes over an existing file.
public struct DnglabConverter: RawConverter {
    /// The tag that claims the ARW for this DNG. Text, not a number.
    static let originalRawFileName = "IFD0:OriginalRawFileName"
    /// dnglab's exit code for an output that exists. It does not touch it.
    static let outputExists: Int32 = 6

    private let executable: URL
    private let exiftool: URL
    private let runner: ProcessRunner
    private let rules: ConverterRules

    /// - Parameters:
    ///   - executable: dnglab.
    ///   - exiftool: writes the tags and reads them back.
    ///   - runner: starts dnglab and exiftool.
    ///   - discardLeftover: takes away what an earlier run left. It gets
    ///     only `ConverterOutput.workURL` of the ARW in work, and
    ///     `<work file>_exiftool_tmp`. The app gives
    ///     `BackupHandling.trashFile` of the job's backups, so the file goes
    ///     to the Trash. There is no default, so no caller reaches the Trash
    ///     by leaving it out.
    ///   - fileExists: whether anything has this name. It must not follow a
    ///     symbolic link. Tests inject it.
    ///   - fileSize: the size of a file in bytes, nil when it cannot be read.
    ///   - fileIsRegular: true only for a regular file. It must not follow
    ///     a symbolic link. Step 1 asks it about a leftover.
    ///   - rename: step 5. Tests inject it to drive each outcome.
    public init(
        executable: URL, exiftool: URL,
        runner: ProcessRunner = SystemProcessRunner(),
        discardLeftover: @escaping @Sendable (URL) throws -> Void,
        fileExists: @escaping @Sendable (String) -> Bool = { ConverterOutput.exists(atPath: $0) },
        fileSize: @escaping @Sendable (String) -> Int? = { ConverterOutput.size(atPath: $0) },
        fileIsRegular: @escaping @Sendable (String) -> Bool = { ConverterOutput.isRegularFile(atPath: $0) },
        rename: @escaping @Sendable (URL, URL) -> ExclusiveRename.Outcome = { ExclusiveRename.system.move($0, to: $1) }
    ) {
        self.executable = executable
        self.exiftool = exiftool
        self.runner = runner
        rules = ConverterRules(name: ConverterKind.dnglab.name, exists: fileExists, size: fileSize,
                               isRegularFile: fileIsRegular, discardLeftover: discardLeftover, rename: rename,
                               reason: { Self.reason(inStandardError: $0.stderr) },
                               exitCodesThatLeaveTheOutputAlone: [Self.outputExists])
    }

    /// Unlike Adobe's converter, dnglab's exit code is the truth: 7 for a
    /// file that it cannot read, with no DNG, and 6 for an output that
    /// exists, which it does not touch. After a non-zero exit, dnglab's own
    /// reason follows the exit code (`reason(inStandardError:)`).
    ///
    /// - Returns: the DNG at `<base>.dng`. No work file is left.
    public func convert(_ arw: URL, facts: ARWFacts) throws -> Conversion {
        let match = AdobeMatch.match(facts)
        let tags = match.tags + [AdobeMatch.Tag(name: Self.originalRawFileName, value: arw.lastPathComponent)]
        let dng = try rules.convert(
            arw,
            start: { work in try runner.run(executable, ["convert", "--embed-raw", "false", arw.path, work.path]) },
            match: { work in
                try write(tags, to: work)
                try check(tags, in: work)
            })
        return Conversion(dng: dng, unmatched: match.failed)
    }

    /// dnglab's own reason for a failure: the last line of its standard
    /// error that starts with `Error:`, without that prefix, and at most
    /// `reasonLimit` characters of it. Nil when there is no such line, or
    /// when nothing follows the prefix.
    ///
    /// dnglab 0.8.0 ends its output for a file that it cannot read with
    /// `Error: Unsupported file: Error: No decoder found, model '', make:
    /// '', mode: ''`. It writes terminal colour codes also into a pipe, so
    /// they are taken out first.
    static func reason(inStandardError text: String) -> String? {
        let prefix = "Error:"
        let line = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix(prefix) }
        guard let reason = line?.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces), !reason.isEmpty else {
            return nil
        }
        return String(reason.prefix(reasonLimit))
    }

    static let reasonLimit = 200

    /// Step 3. One call for every tag. The write passes when exiftool
    /// returned 0 and says that it updated the file.
    private func write(_ tags: [AdobeMatch.Tag], to dng: URL) throws {
        let result = try runner.run(
            exiftool, ["-m", "-overwrite_original"] + tags.map { "-\($0.name)=\($0.value)" } + [dng.path])
        guard result.exitCode == 0, result.stdout.contains("1 image files updated") else {
            throw TagError.toolFailed("The tags could not be written: \(ScaleTag.detail(result))")
        }
    }

    /// Step 4. One call reads every tag, as one tab-separated row in the
    /// order of `tags`. exiftool prints `-` for a tag that is not there.
    ///
    /// exiftool prints a control character as a period. The file name that
    /// was written is compared in that form: a name with a tab or a line end
    /// in it would otherwise never read back as equal, and its ARW would
    /// fail on every run.
    private func check(_ tags: [AdobeMatch.Tag], in dng: URL) throws {
        let result = try runner.run(exiftool, ["-m", "-n", "-T"] + tags.map { "-\($0.name)" } + [dng.path])
        let row = result.stdout.split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
        let cells = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard cells.count == tags.count else {
            throw TagError.toolFailed("The tags did not read back.")
        }
        for (tag, read) in zip(tags, cells) {
            // The file name, as exiftool prints it. The sentence has that
            // form too: a tab or a line end never goes into a note.
            let isText = tag.name == Self.originalRawFileName
            let wanted = isText ? ExiftoolText.printed(tag.value) : tag.value
            guard isText ? read == wanted : AdobeMatch.sameNumbers(wanted, read) else {
                throw TagError.toolFailed("The tag \(tag.name) did not read back as \(wanted).")
            }
        }
    }
}
