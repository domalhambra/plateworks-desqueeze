import Foundation

/// One line for the result list: a file and what happened to it.
///
/// A front end reads `kind`, never the English sentence. `message` and
/// `detail` are for a person.
public struct FileNote: Equatable, Sendable, Identifiable, Codable {
    /// Why the note exists. The raw values are the JSON values (design 12.1).
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A `<name>.dng_original` with no DNG beside it.
        case orphanBackup
        /// An ARW whose conversion failed.
        case notConverted
        /// A DNG whose write or check failed.
        case failed
        /// A DNG held back, because an older backup is beside it.
        case blockedByBackup
        /// A DNG already at the value, with a backup beside it.
        case leftoverBackup
        /// A DNG that was set, and whose backup the Trash refused.
        case backupKept
        /// The folder is read-only. No file was tried.
        case folderReadOnly
    }

    public let name: String
    public let kind: Kind
    public let message: String
    /// The tool's own words, shown below the plain sentence.
    public let detail: String?

    public var id: String { name + "\n" + message }
    /// The note as one line of text: the name, then the sentence.
    public var line: String { "\(name): \(message)" }

    public init(name: String, kind: Kind, message: String, detail: String?) {
        self.name = name
        self.kind = kind
        self.message = message
        self.detail = detail
    }

    /// Writes `detail` as `null` when there is none, so the key is always there.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(message, forKey: .message)
        try container.encode(detail, forKey: .detail)
    }
}

/// Each sentence a run can say about a file, with its kind. They are made
/// here and nowhere else, so the run and the dry run say the same words.
extension FileNote {
    /// The only place that makes this sentence. A front end that names an
    /// orphan backup shows the `line` of this note (`FolderText.messages`).
    ///
    /// - Parameter backup: the file name, `<name>.dng_original`.
    public static func orphanBackup(named backup: String) -> FileNote {
        FileNote(name: backup, kind: .orphanBackup,
                 message: "A backup with no DNG beside it. Rename it to \(backup.dropLast("_original".count)) to get the photo back.",
                 detail: nil)
    }

    public static func folderReadOnly(_ folder: URL) -> FileNote {
        FileNote(name: folder.lastPathComponent, kind: .folderReadOnly,
                 message: "This folder is read-only. No file was changed.", detail: nil)
    }

    static func notConverted(_ arw: String, detail: String) -> FileNote {
        FileNote(name: arw, kind: .notConverted, message: "Not converted.", detail: detail)
    }

    static func failed(_ dng: String, message: String, detail: String) -> FileNote {
        FileNote(name: dng, kind: .failed, message: message, detail: detail)
    }

    static func blockedByBackup(_ dng: String) -> FileNote {
        FileNote(name: dng, kind: .blockedByBackup,
                 message: "Blocked. An older backup, \(dng)_original, is beside this file. Move it away, then run again.",
                 detail: nil)
    }

    static func leftoverBackup(_ dng: String) -> FileNote {
        FileNote(name: dng, kind: .leftoverBackup,
                 message: "Already at this value. A backup, \(dng)_original, is beside this file.", detail: nil)
    }

    static func backupKept(_ dng: String, detail: String) -> FileNote {
        FileNote(name: dng, kind: .backupKept,
                 message: "Done. The backup stayed beside the file, because the Trash refused it.", detail: detail)
    }
}

public struct RunSummary: Equatable, Sendable {
    public var converted = 0
    public var set = 0
    /// DNG files already at the value. Nothing else counts here.
    public var skipped = 0
    /// DNG files held back by an older backup.
    public var blocked = 0
    public var failed = 0
    /// The pending ARW files of the run's own scan that have no DNG when the
    /// run returns. Remove reports 0. The rule is at `DesqueezeJob`.
    public var unconvertedARWs = 0
    public var notes: [FileNote] = []
    public var cancelled = false
    /// True when the folder held no DNG, no ARW and no orphan backup, as
    /// `FolderSnapshot.isEmpty` says. A front end then shows
    /// `FolderText.noPhotos`. A folder with an orphan backup is not empty.
    public var folderIsEmpty = false

    public init() {}
}

extension RunSummary {
    /// The one line of counts (design 4.4). The window and the command line
    /// tool both show this text.
    public var countsLine: String {
        Self.countsLine(converted: converted, set: set, skipped: skipped, blocked: blocked, failed: failed,
                        stopped: cancelled)
    }

    /// Converted and blocked show only when they are not zero.
    static func countsLine(converted: Int, set: Int, skipped: Int, blocked: Int, failed: Int,
                           stopped: Bool) -> String {
        var parts: [String] = []
        if converted > 0 { parts.append("\(converted) converted") }
        parts.append("\(set) set")
        parts.append("\(skipped) skipped")
        if blocked > 0 { parts.append("\(blocked) blocked") }
        parts.append("\(failed) failed")
        if stopped { parts.append("stopped") }
        return parts.joined(separator: " · ")
    }

    /// The fixed line under the counts (design 4.4). Lightroom reads the tag
    /// at import, and keeps what it read.
    public static let lightroomHint = "Photos already in Lightroom: Metadata › Read Metadata from File."

    /// True when a file failed or was blocked. A front end then marks the
    /// result as one to look at. A stopped run with no such file is not one.
    public var needsAttention: Bool { failed > 0 || blocked > 0 }

    /// The sentence about the ARW files the run left, with the count. Nil
    /// when it left none.
    ///
    /// - Parameter converterAvailable: false adds the reason.
    public func unconvertedARWsLine(converterAvailable: Bool) -> String? {
        Self.unconvertedARWsLine(count: unconvertedARWs, dryRun: false, converterAvailable: converterAvailable)
    }

    static func unconvertedARWsLine(count: Int, dryRun: Bool, converterAvailable: Bool) -> String? {
        guard count > 0 else { return nil }
        let files = count == 1 ? "1 ARW file" : "\(count) ARW files"
        let verb = dryRun ? "would not be" : (count == 1 ? "was not" : "were not")
        return "\(files) \(verb) converted." + (converterAvailable ? "" : " Adobe DNG Converter is not installed.")
    }
}

public struct RunProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let name: String
}

/// Set from the main thread, read from the job's thread.
public final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    public init() {}

    public func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
