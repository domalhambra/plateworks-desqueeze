import Foundation

/// What a scan found, in the JSON shape of design 12.1, with the `dnglab`
/// key of design 13.6.
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
    /// Where dnglab is. Nil when it is not installed (design 13.6).
    public let dnglab: String?
    /// Where Adobe DNG Converter is. Nil when it is not installed.
    public let dngConverter: String?
    public let dngs: [DNG]
    public let pendingARWs: [String]
    public let orphanBackups: [String]

    public init(folder: String, writable: Bool, exiftool: String, dnglab: String?, dngConverter: String?,
                dngs: [DNG], pendingARWs: [String], orphanBackups: [String]) {
        self.folder = folder
        self.writable = writable
        self.exiftool = exiftool
        self.dnglab = dnglab
        self.dngConverter = dngConverter
        self.dngs = dngs
        self.pendingARWs = pendingARWs
        self.orphanBackups = orphanBackups
    }

    public init(snapshot: FolderSnapshot, exiftool: URL, dnglab: URL?, dngConverter: URL?) {
        self.init(
            folder: snapshot.folder.path,
            writable: snapshot.isWritable,
            exiftool: exiftool.path,
            dnglab: dnglab?.path,
            dngConverter: dngConverter?.path,
            dngs: snapshot.dngs.map {
                DNG(name: $0.name, scale: $0.scale?.text, originalRawFileName: $0.originalRawFileName,
                    hasBackup: $0.hasBackup)
            },
            pendingARWs: snapshot.pendingARWs.map(\.lastPathComponent),
            orphanBackups: snapshot.orphanBackups.map(\.lastPathComponent))
    }

    /// `FolderText.converterAdvice` for this scan: the one line about the
    /// converters, or nil.
    public var converterAdvice: String? {
        FolderText.converterAdvice(pendingARWs: pendingARWs.count, dnglabInstalled: dnglab != nil,
                                   adobeInstalled: dngConverter != nil)
    }

    /// With neither converter and an ARW that waits: the sentence that the
    /// ARW files cannot be converted (`FolderText.arwsCannotConvert`). The
    /// scan text shows it before the install line. Nil in every other state.
    public var arwsCannotConvertLine: String? {
        guard dnglab == nil, dngConverter == nil, !pendingARWs.isEmpty else { return nil }
        return FolderText.arwsCannotConvert(count: pendingARWs.count)
    }

    /// True when the folder holds nothing to report.
    public var isEmpty: Bool { dngs.isEmpty && pendingARWs.isEmpty && orphanBackups.isEmpty }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(folder, forKey: .folder)
        try container.encode(writable, forKey: .writable)
        try container.encode(exiftool, forKey: .exiftool)
        try container.encode(dnglab, forKey: .dnglab)
        try container.encode(dngConverter, forKey: .dngConverter)
        try container.encode(dngs, forKey: .dngs)
        try container.encode(pendingARWs, forKey: .pendingARWs)
        try container.encode(orphanBackups, forKey: .orphanBackups)
    }
}

/// The result of a run or of a dry run, in the JSON shape of design 12.1,
/// with the two counts of design 13.6 and the two keys of design 14.3.
public struct RunReport: Codable, Equatable, Sendable {
    public let folder: String
    /// The factor as text, with no trailing zeros: `1.5`, `2`, `1`.
    public let factor: String
    public let dryRun: Bool
    /// `convertedByDnglab` plus `convertedByAdobe`.
    public let converted: Int
    public let convertedByDnglab: Int
    public let convertedByAdobe: Int
    public let set: Int
    public let skipped: Int
    public let blocked: Int
    public let failed: Int
    public let stopped: Bool
    public let unconvertedARWs: Int
    /// True when the run was asked to move the originals to the Trash
    /// (design 14.3). The key is always there.
    public let trashOriginals: Bool
    /// The ARW files that the run moved to the Trash. In a dry run: the
    /// count that a run gives when every step passes. The key is always
    /// there, and it is 0 when `trashOriginals` is false.
    public let originalsInTrash: Int
    public let notes: [FileNote]
    /// Only a dry run has steps. A real run has no `steps` key.
    public let steps: [RunPlan.Step]?
    /// True when the folder held no DNG, no ARW and no orphan backup. It is
    /// for the text of a front end, and it is not in the JSON, which stays
    /// the object of design 12.1.
    ///
    /// It is part of `==` and not part of the JSON, so it does not read back:
    /// a report decoded from JSON always has `false`, and it is not equal to
    /// the report that was encoded when that one held `true`. Use the flag
    /// on a report from `DesqueezeOperations`, never on a decoded one.
    public private(set) var folderIsEmpty = false

    private enum CodingKeys: String, CodingKey {
        case folder, factor, dryRun, converted, convertedByDnglab, convertedByAdobe, set, skipped, blocked, failed,
             stopped, unconvertedARWs, trashOriginals, originalsInTrash, notes, steps
    }

    init(folder: URL, factor: SqueezeFactor, summary: RunSummary, steps: [RunPlan.Step]?) {
        self.folder = folder.path
        self.factor = factor.label
        dryRun = steps != nil
        converted = summary.converted
        convertedByDnglab = summary.convertedByDnglab
        convertedByAdobe = summary.convertedByAdobe
        set = summary.set
        skipped = summary.skipped
        blocked = summary.blocked
        failed = summary.failed
        stopped = summary.cancelled
        unconvertedARWs = summary.unconvertedARWs
        trashOriginals = summary.trashOriginals
        originalsInTrash = summary.originalsInTrash
        notes = summary.notes
        self.steps = steps
        folderIsEmpty = summary.folderIsEmpty
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

    /// The sentence of `RunSummary.convertersLine`: how many ARW files each
    /// converter converted, when both did work. Nil when only one
    /// converted, or none, and for a dry run: its steps name the converter
    /// of each ARW.
    public var convertersLine: String? {
        RunSummary.convertersLine(dnglab: convertedByDnglab, adobe: convertedByAdobe, dryRun: dryRun)
    }

    /// The sentence of `RunSummary.originalsLine`: how many originals the
    /// run moved to the Trash, of the ARW files that it converted. Nil when
    /// the run was not asked to move them, and for a dry run: it moved
    /// nothing, and its steps name each ARW that a run would move.
    public var originalsLine: String? {
        RunSummary.originalsLine(asked: trashOriginals, moved: originalsInTrash, converted: converted,
                                 dryRun: dryRun)
    }

    /// The line of `RunSummary.lightroomLine`: shown when the run set at
    /// least one photo, and never for a dry run (design 4.4).
    public var lightroomLine: String? {
        RunSummary.lightroomLine(set: set, dryRun: dryRun)
    }

    /// The sentence of `RunSummary.unconvertedARWsLine`. A dry run says
    /// "would not be".
    ///
    /// - Parameter converterAvailable: true when one converter or the other
    ///   is installed.
    public func unconvertedARWsLine(converterAvailable: Bool) -> String? {
        RunSummary.unconvertedARWsLine(count: unconvertedARWs, dryRun: dryRun, converterAvailable: converterAvailable)
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

/// Turns a report into JSON text.
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
