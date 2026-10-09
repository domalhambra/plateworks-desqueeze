import Foundation

/// What a scan found, in the JSON shape of design 12.1.
///
/// The command line tool and the MCP server both print this type, so the two
/// print the same JSON. Every key is always there. A value that is not known
/// is `null`.
public struct ScanReport: Codable, Equatable, Sendable {
    public struct DNG: Codable, Equatable, Sendable {
        public let name: String
        /// The tag value as text, for example `1.5 1`. Nil when it is unknown.
        public let scale: String?
        public let originalRawFileName: String?
        public let hasBackup: Bool

        public init(name: String, scale: String?, originalRawFileName: String?, hasBackup: Bool) {
            self.name = name
            self.scale = scale
            self.originalRawFileName = originalRawFileName
            self.hasBackup = hasBackup
        }

        /// Writes `null` for a value that is not known. `encode` on an
        /// optional does that. The synthesized code leaves the key out.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(scale, forKey: .scale)
            try container.encode(originalRawFileName, forKey: .originalRawFileName)
            try container.encode(hasBackup, forKey: .hasBackup)
        }
    }

    public let folder: String
    public let writable: Bool
    public let exiftool: String
    /// Nil when Adobe DNG Converter is not installed.
    public let dngConverter: String?
    public let dngs: [DNG]
    public let pendingARWs: [String]
    public let orphanBackups: [String]

    public init(folder: String, writable: Bool, exiftool: String, dngConverter: String?, dngs: [DNG],
                pendingARWs: [String], orphanBackups: [String]) {
        self.folder = folder
        self.writable = writable
        self.exiftool = exiftool
        self.dngConverter = dngConverter
        self.dngs = dngs
        self.pendingARWs = pendingARWs
        self.orphanBackups = orphanBackups
    }

    public init(snapshot: FolderSnapshot, exiftool: URL, dngConverter: URL?) {
        self.init(
            folder: snapshot.folder.path,
            writable: snapshot.isWritable,
            exiftool: exiftool.path,
            dngConverter: dngConverter?.path,
            dngs: snapshot.dngs.map {
                DNG(name: $0.name, scale: $0.scale?.text, originalRawFileName: $0.originalRawFileName,
                    hasBackup: $0.hasBackup)
            },
            pendingARWs: snapshot.pendingARWs.map(\.lastPathComponent),
            orphanBackups: snapshot.orphanBackups.map(\.lastPathComponent))
    }

    /// True when the folder holds nothing to report.
    public var isEmpty: Bool { dngs.isEmpty && pendingARWs.isEmpty && orphanBackups.isEmpty }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(folder, forKey: .folder)
        try container.encode(writable, forKey: .writable)
        try container.encode(exiftool, forKey: .exiftool)
        try container.encode(dngConverter, forKey: .dngConverter)
        try container.encode(dngs, forKey: .dngs)
        try container.encode(pendingARWs, forKey: .pendingARWs)
        try container.encode(orphanBackups, forKey: .orphanBackups)
    }
}

/// The result of a run or of a dry run, in the JSON shape of design 12.1.
public struct RunReport: Codable, Equatable, Sendable {
    public let folder: String
    /// The factor as text, with no trailing zeros: `1.5`, `2`, `1`.
    public let factor: String
    public let dryRun: Bool
    public let converted: Int
    public let set: Int
    public let skipped: Int
    public let blocked: Int
    public let failed: Int
    public let stopped: Bool
    public let unconvertedARWs: Int
    public let notes: [FileNote]
    /// Only a dry run has steps. A real run has no `steps` key.
    public let steps: [RunPlan.Step]?

    init(folder: URL, factor: SqueezeFactor, summary: RunSummary, steps: [RunPlan.Step]?) {
        self.folder = folder.path
        self.factor = factor.label
        dryRun = steps != nil
        converted = summary.converted
        set = summary.set
        skipped = summary.skipped
        blocked = summary.blocked
        failed = summary.failed
        stopped = summary.cancelled
        unconvertedARWs = summary.unconvertedARWs
        notes = summary.notes
        self.steps = steps
    }

    /// The report of a real run.
    public init(folder: URL, factor: SqueezeFactor, summary: RunSummary) {
        self.init(folder: folder, factor: factor, summary: summary, steps: nil)
    }

    /// The report of a dry run: the counts a real run gives when every step
    /// passes, and the steps.
    public init(folder: URL, factor: SqueezeFactor, plan: RunPlan) {
        self.init(folder: folder, factor: factor, summary: plan.summary, steps: plan.steps)
    }

    public var countsLine: String {
        RunSummary.countsLine(converted: converted, set: set, skipped: skipped, blocked: blocked, failed: failed,
                              stopped: stopped)
    }
}

/// What a front end prints as JSON when it can give no report.
public struct ErrorReport: Codable, Equatable, Sendable {
    public let error: String
    public let detail: String?

    public init(error: String, detail: String?) {
        self.error = error
        self.detail = detail
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(error, forKey: .error)
        try container.encode(detail, forKey: .detail)
    }
}

public enum ReportJSON {
    /// The one way to turn a report into text, so every front end prints the
    /// same bytes for the same report: one JSON object, one key on each line,
    /// the keys in alphabetical order, each path as it is, and an empty list
    /// as `[]`. No line end follows the object.
    public static func text<Report: Encodable>(_ report: Report) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(report), as: UTF8.self)
        // Foundation prints an empty list over three lines. A line end is
        // never inside a JSON string, so this matches no text of a value.
        return text.replacingOccurrences(of: #"\[\n\s*\]"#, with: "[]", options: .regularExpression)
    }
}
