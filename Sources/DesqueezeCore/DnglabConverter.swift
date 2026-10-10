import Foundation

/// Converts with dnglab, then writes the tags that make the DNG render as
/// Adobe DNG Converter's does (design 13.2 to 13.4).
///
/// Three programs run for one ARW:
///
/// 1. `dnglab convert --embed-raw false <in.ARW> <out.dng>`. Without the
///    flag dnglab puts the whole ARW inside the DNG.
/// 2. One exiftool call that writes every tag, with `-m` and
///    `-overwrite_original`. No backup is kept: the DNG is this run's own, a
///    moment old, and has no earlier state to keep.
/// 3. One exiftool call that reads every tag back. Numbers are compared as
///    numbers (`AdobeMatch.sameNumbers`), the file name as text.
///
/// The conversion passes only when dnglab returned 0, the DNG has bytes, and
/// the read-back equals what was written. When any of these fails, the DNG
/// is this run's partial output, by the rules of `ConverterRules`.
///
/// **The tags** are what `AdobeMatch` gives for the facts of the ARW, and
/// `IFD0:OriginalRawFileName`, which dnglab does not write with
/// `--embed-raw false` and which the pending rule needs (design 4.1). The
/// file name is written for every ARW. For an ARW with no full match, the
/// table tags are written as far as `AdobeMatch` gives them, and the result
/// carries the rule that failed.
///
/// Never pass `-f` to dnglab: it writes over an existing file. The check
/// before the start is the rule.
public struct DnglabConverter: RawConverter {
    /// The tag that claims the ARW for this DNG. Text, not a number.
    static let originalRawFileName = "IFD0:OriginalRawFileName"

    private let executable: URL
    private let exiftool: URL
    private let runner: ProcessRunner
    private let rules: ConverterRules

    /// - Parameters:
    ///   - executable: dnglab.
    ///   - exiftool: writes the tags and reads them back.
    ///   - fileExists: whether anything has this name. It must not follow a
    ///     symbolic link. Tests inject it.
    ///   - fileSize: the size of a file in bytes, nil when it cannot be read.
    public init(
        executable: URL, exiftool: URL,
        runner: ProcessRunner = SystemProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = { ConverterOutput.exists(atPath: $0) },
        fileSize: @escaping @Sendable (String) -> Int? = { ConverterOutput.size(atPath: $0) }
    ) {
        self.executable = executable
        self.exiftool = exiftool
        self.runner = runner
        rules = ConverterRules(name: "dnglab", exists: fileExists, size: fileSize)
    }

    /// Unlike Adobe's converter, dnglab's exit code is the truth: 7 for a
    /// file that it cannot read, with no DNG, and 6 for an output that
    /// exists, which it does not touch. The rules are the same all the same.
    public func convert(_ arw: URL, facts: ARWFacts) throws -> Conversion {
        let match = AdobeMatch.match(facts)
        let tags = match.tags + [AdobeMatch.Tag(name: Self.originalRawFileName, value: arw.lastPathComponent)]
        let dng = try rules.convert(
            arw,
            start: { output in try runner.run(executable, ["convert", "--embed-raw", "false", arw.path, output.path]) },
            complete: { dng in
                try write(tags, to: dng)
                try check(tags, in: dng)
            })
        return Conversion(dng: dng, unmatched: match.failed)
    }

    /// One call for every tag. The write passes when exiftool returned 0 and
    /// says that it updated the file.
    private func write(_ tags: [AdobeMatch.Tag], to dng: URL) throws {
        let result = try runner.run(
            exiftool, ["-m", "-overwrite_original"] + tags.map { "-\($0.name)=\($0.value)" } + [dng.path])
        guard result.exitCode == 0, result.stdout.contains("1 image files updated") else {
            throw TagError.toolFailed("The tags could not be written: \(ScaleTag.detail(result))")
        }
    }

    /// One call reads every tag, as one tab-separated row in the order of
    /// `tags`. exiftool prints `-` for a tag that is not there.
    private func check(_ tags: [AdobeMatch.Tag], in dng: URL) throws {
        let result = try runner.run(exiftool, ["-m", "-n", "-T"] + tags.map { "-\($0.name)" } + [dng.path])
        let row = result.stdout.split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
        let cells = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard cells.count == tags.count else {
            throw TagError.toolFailed("The tags did not read back.")
        }
        for (tag, read) in zip(tags, cells) {
            let same = tag.name == Self.originalRawFileName
                ? read == tag.value
                : AdobeMatch.sameNumbers(tag.value, read)
            guard same else {
                throw TagError.toolFailed("The tag \(tag.name) did not read back as \(tag.value).")
            }
        }
    }
}
