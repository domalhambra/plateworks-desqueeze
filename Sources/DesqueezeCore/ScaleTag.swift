import Foundation

/// The two numbers of the `DefaultScale` tag: horizontal stretch, then
/// vertical stretch.
public struct Scale: Equatable, Sendable {
    public let horizontal: Double
    public let vertical: Double

    /// No stretch: 1 and 1. A DNG that a converter just made holds this.
    public static let noStretch = Scale(horizontal: 1, vertical: 1)

    public init(horizontal: Double, vertical: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// The tag value as text, the way exiftool prints it: `1.5 1`.
    ///
    /// Each number is the shortest text that reads back as the same number,
    /// with no `.0` on a whole number. Nothing is rounded: a value that this
    /// app did not write shows as it is. For each valid factor, this is
    /// `SqueezeFactor.tagValue`.
    public var text: String { "\(Self.text(horizontal)) \(Self.text(vertical))" }

    private static func text(_ number: Double) -> String {
        let text = "\(number)"
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

/// One row of the folder read: a DNG and its current tag.
public struct TagRow: Equatable, Sendable {
    public let fileName: String
    /// Nil when exiftool gave no value. The tag is absent, or the file is not
    /// a DNG that exiftool can read. The two cases look the same here.
    public let scale: Scale?
    public let originalRawFileName: String?

    /// Public, so a `ScaleTagging` outside this module can give rows: the
    /// fake of the window's tests does.
    public init(fileName: String, scale: Scale?, originalRawFileName: String?) {
        self.fileName = fileName
        self.scale = scale
        self.originalRawFileName = originalRawFileName
    }
}

/// A read or a write of a tag that failed, with the reason as text.
public enum TagError: Error, Equatable {
    case toolFailed(String)
}

/// Reads and writes the `DefaultScale` tag. `DesqueezeJob` depends on this
/// protocol, so its tests need no exiftool.
public protocol ScaleTagging: Sendable {
    func readFolder(_ folder: URL) throws -> [TagRow]
    func write(_ factor: SqueezeFactor, to file: URL) throws
    /// Nil when the file gives no value.
    func read(_ file: URL) throws -> Scale?
    /// The two tags of the check before an original moves to the Trash
    /// (design 14.2, line 5), from one read of one DNG. It changes no file.
    ///
    /// - Throws: when the read gave no row for the file. The error has the
    ///   tool's own words.
    func readOriginalCheck(_ dng: URL) throws -> OriginalCheckTags
}

/// The exiftool implementation.
///
/// The group `SubIFD` is named on every call, because that is the image
/// directory Camera Raw reads.
public struct ScaleTag: ScaleTagging {
    static let tagName = "-SubIFD:DefaultScale"

    private let exiftool: URL
    private let runner: ProcessRunner

    public init(exiftool: URL, runner: ProcessRunner = SystemProcessRunner()) {
        self.exiftool = exiftool
        self.runner = runner
    }

    /// One call for the whole folder. exiftool reads the top level only.
    public func readFolder(_ folder: URL) throws -> [TagRow] {
        let result = try runner.run(exiftool, [
            "-m", "-T", "-filename", Self.tagName, "-OriginalRawFileName", "-ext", "dng", folder.path,
        ])
        // exiftool exits 1 when any one file is unreadable, and the other rows
        // are still valid. Only a failure with no rows at all is a failed read.
        if result.stdout.isEmpty, result.exitCode != 0 {
            throw TagError.toolFailed(Self.detail(result))
        }
        return Self.parseRows(result.stdout)
    }

    /// Writes the tag. exiftool keeps the previous file as `<name>_original`.
    /// `-m` is needed: Adobe DNG Converter files carry a minor flaw in a Sony
    /// data block, and exiftool refuses to write without it.
    public func write(_ factor: SqueezeFactor, to file: URL) throws {
        let result = try runner.run(exiftool, ["-m", "\(Self.tagName)=\(factor.tagValue)", file.path])
        guard result.exitCode == 0, result.stdout.contains("1 image files updated") else {
            throw TagError.toolFailed(Self.detail(result))
        }
    }

    public func read(_ file: URL) throws -> Scale? {
        let result = try runner.run(exiftool, ["-s3", Self.tagName, file.path])
        return Self.parseScale(result.stdout)
    }

    /// The tags of `readOriginalCheck`, in the order of the columns that
    /// `parseOriginalCheck` reads.
    static let originalCheckTags = ["-IFD0:OriginalRawFileName", tagName]

    /// One call (design 14.2, line 5):
    ///
    /// ```
    /// exiftool -m -n -T -IFD0:OriginalRawFileName -SubIFD:DefaultScale <file.dng>
    /// ```
    ///
    /// exiftool prints one row for a file that it opened, also for a file
    /// that is no DNG: that row has `-` for each tag. For a file that is not
    /// there it prints no row, and this throws with its words.
    public func readOriginalCheck(_ dng: URL) throws -> OriginalCheckTags {
        let result = try runner.run(exiftool, ["-m", "-n", "-T"] + Self.originalCheckTags + [dng.path])
        guard let tags = Self.parseOriginalCheck(result.stdout) else {
            throw TagError.toolFailed(Self.detail(result))
        }
        return tags
    }

    /// Parses the one tab-separated row of `readOriginalCheck`: the name,
    /// then the scale. exiftool prints `-` for a tag that the file does not
    /// have. Nil when the first line is no such row.
    static func parseOriginalCheck(_ text: String) -> OriginalCheckTags? {
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
        let cells = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard cells.count == originalCheckTags.count else { return nil }
        return OriginalCheckTags(originalRawFileName: cells[0] == "-" ? nil : cells[0], scale: parseScale(cells[1]))
    }

    /// Parses `1.5 1`. Returns nil for `-`, an empty string, or anything else.
    static func parseScale(_ text: String) -> Scale? {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        // `Double` parses "inf" and "nan", and exiftool will write and print them.
        guard parts.count == 2, let horizontal = Double(parts[0]), let vertical = Double(parts[1]),
              horizontal.isFinite, vertical.isFinite else {
            return nil
        }
        return Scale(horizontal: horizontal, vertical: vertical)
    }

    /// Parses the tab-separated folder read. exiftool includes hidden files,
    /// so this drops each row whose name starts with a period.
    static func parseRows(_ text: String) -> [TagRow] {
        text.split(separator: "\n").compactMap { line in
            let cells = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cells.count == 3, !cells[0].hasPrefix(".") else { return nil }
            return TagRow(fileName: cells[0], scale: parseScale(cells[1]),
                          originalRawFileName: cells[2] == "-" ? nil : cells[2])
        }
    }

    /// One line that says why exiftool failed. The hidden-data warning is
    /// expected on every Adobe DNG Converter file and says nothing.
    static func detail(_ result: ProcessResult) -> String {
        let lines = (result.stderr + "\n" + result.stdout)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("Error copying hidden data") }
        let line = lines.first(where: { $0.hasPrefix("Error") })
            ?? lines.first(where: { $0.hasPrefix("Warning") })
            ?? lines.last
            ?? "exiftool returned \(result.exitCode)."
        // exiftool ends a message with " - <full path>". The window shows the
        // file name beside the message already.
        if let cut = line.range(of: " - /") { return String(line[..<cut.lowerBound]) }
        return line
    }
}
