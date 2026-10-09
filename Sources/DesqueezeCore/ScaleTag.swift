import Foundation

/// The two numbers of the `DefaultScale` tag: horizontal stretch, then
/// vertical stretch.
public struct Scale: Equatable, Sendable {
    public let horizontal: Double
    public let vertical: Double

    /// No stretch: 1 and 1. A DNG that the converter just made holds this.
    public static let noStretch = Scale(horizontal: 1, vertical: 1)

    public init(horizontal: Double, vertical: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

/// One row of the folder read: a DNG and its current tag.
public struct TagRow: Equatable, Sendable {
    public let fileName: String
    /// Nil when exiftool gave no value. The tag is absent, or the file is not
    /// a DNG that exiftool can read. The two cases look the same here.
    public let scale: Scale?
    public let originalRawFileName: String?
}

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
