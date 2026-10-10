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
        /// A DNG that dnglab made with no full match, because Adobe DNG
        /// Converter is not installed (design 13.4). The file counts as
        /// converted. It is not failed and not blocked.
        case convertedUnmatched
        /// An ARW that this run converted, and that stays in the folder
        /// though the run was asked to move the originals to the Trash
        /// (design 14.3). The name is the ARW's. It is information: the file
        /// is not failed and not blocked.
        case originalKept
        /// The run worked without the lock that keeps a second run out of
        /// the folder, because the volume gives none (design 13.9). The
        /// name is the folder's. It is information: no file is failed or
        /// blocked by it.
        case noFolderLock
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

    /// The note of a run on a volume that gives no lock for a folder
    /// (design 13.9). The run went on, and nothing kept a second run out.
    /// The only place that makes this sentence.
    static func noFolderLock(_ folder: URL) -> FileNote {
        FileNote(name: folder.lastPathComponent, kind: .noFolderLock,
                 message: "This volume gives no folder lock. Do not start a second run in this folder while "
                     + "this run works.",
                 detail: nil)
    }

    /// - Parameter detail: each converter's own words, one line for each
    ///   converter that was tried, in the order of the tries.
    static func notConverted(_ arw: String, detail: String) -> FileNote {
        FileNote(name: arw, kind: .notConverted, message: "Not converted.", detail: detail)
    }

    /// How each note about a DNG with no full match ends (design 13.4).
    static let installAdobeForTheSameFile = "Install Adobe DNG Converter for the same file that Lightroom makes."

    /// The note for a DNG that dnglab made with no full match (design 13.4).
    /// The only place that makes these sentences.
    ///
    /// When only rule 4 failed, every tag of the match is in the DNG, and it
    /// has no lens correction. The detail line says that the ARW holds
    /// lens-correction data only when the ARW says so. When the ARW has no
    /// word about it, the line says that. When rule 1, 2, 3 or 5 failed, no tag of the
    /// match is in it.
    ///
    /// - Parameters:
    ///   - rule: the first rule that failed, from `AdobeMatch`.
    ///   - facts: the facts of the ARW. The detail line names the one that
    ///     has no row in the table.
    static func convertedUnmatched(_ dng: String, rule: AdobeMatch.Rule, facts: ARWFacts) -> FileNote {
        let what: String
        let why: String
        switch rule {
        case .model:
            what = "The levels are dnglab's own."
            why = facts.model.map { "The table of Adobe's values has no camera \($0)." }
                ?? "The camera model could not be read from the ARW."
        case .iso:
            what = "The levels are dnglab's own."
            why = facts.iso.map { "The table of Adobe's values has no row for ISO \($0)." }
                ?? "The ISO could not be read from the ARW."
        case .daylightLevels:
            what = "The levels are dnglab's own."
            why = "The ARW has no daylight levels that the table of Adobe's values can use."
        case .compressedRaw:
            what = "The levels are dnglab's own."
            why = facts.rawFileType == nil
                ? "The kind of raw data could not be read from the ARW."
                : "The table of Adobe's values has compressed raw only, and this ARW is another kind."
        case .noLensCorrection:
            what = "The DNG has no built-in lens correction."
            // No value is not "the ARW holds data": the tag can be absent.
            why = facts.distortionCorrection == nil
                ? "The ARW does not say whether it has lens-correction data, and dnglab writes none into the DNG."
                : "The ARW holds lens-correction data, and dnglab does not write it into the DNG."
        }
        return FileNote(name: dng, kind: .convertedUnmatched,
                        message: "Converted. \(what) \(installAdobeForTheSameFile)", detail: why)
    }

    /// The note for an original that stays (design 14.3). The sentences are
    /// made at `OriginalDecision.KeepReason.sentence`, and nowhere else.
    ///
    /// - Parameter arw: the file name of the ARW.
    static func originalKept(_ arw: String, because reason: OriginalDecision.KeepReason) -> FileNote {
        FileNote(name: arw, kind: .originalKept, message: reason.sentence, detail: reason.detail)
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

/// The counts and the notes of one run.
public struct RunSummary: Equatable, Sendable {
    /// ARW files that dnglab converted. A DNG with no full match is in it
    /// too, and has a `convertedUnmatched` note.
    public var convertedByDnglab = 0
    /// ARW files that Adobe DNG Converter converted.
    public var convertedByAdobe = 0
    /// Every ARW that the run converted: the sum of the two counts above.
    public var converted: Int { convertedByDnglab + convertedByAdobe }
    public var set = 0
    /// DNG files already at the value. Nothing else counts here.
    public var skipped = 0
    /// DNG files held back by an older backup.
    public var blocked = 0
    public var failed = 0
    /// The pending ARW files of the run's own scan that have no DNG when the
    /// run returns. Remove reports 0. The rule is at `DesqueezeJob`.
    public var unconvertedARWs = 0
    /// True when the run was asked to move the originals to the Trash
    /// (design 14). Remove is never asked.
    public var trashOriginals = false
    /// The ARW files that the run moved to the Trash. It is 0 when
    /// `trashOriginals` is false. In the summary of a `RunPlan`: the count
    /// that a run gives when every step passes.
    public var originalsInTrash = 0
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

    /// The words of the line under the counts (design 4.4). Lightroom reads
    /// the tag at import, and keeps what it read. Whether a front end shows
    /// the line is `lightroomLine`.
    public static let lightroomHint = "Photos already in Lightroom: Metadata › Read Metadata from File."

    /// `lightroomHint` when this run set the tag on at least one photo, and
    /// nil when it set none (design 4.4). The window shows it under the
    /// counts.
    ///
    /// This is for the summary of a real run. The summary inside a `RunPlan`
    /// counts what a run would set, and a dry run never shows the line: ask
    /// `RunReport.lightroomLine` for a dry run.
    public var lightroomLine: String? { Self.lightroomLine(set: set, dryRun: false) }

    /// The one rule for the Lightroom line (design 4.4): shown when the run
    /// set at least one photo, and never for a dry run. Every front end
    /// follows it, through `RunSummary.lightroomLine` or
    /// `RunReport.lightroomLine`.
    static func lightroomLine(set: Int, dryRun: Bool) -> String? {
        !dryRun && set > 0 ? lightroomHint : nil
    }

    /// How many ARW files each converter converted, when both did work
    /// (design 4.4): `Converted with dnglab: 11. With Adobe DNG Converter:
    /// 1.` Nil when only one converted, or none. The window shows it under
    /// the counts.
    ///
    /// This is for the summary of a real run, as `lightroomLine` is.
    public var convertersLine: String? {
        Self.convertersLine(dnglab: convertedByDnglab, adobe: convertedByAdobe, dryRun: false)
    }

    /// The one rule for the line about the two converters. A dry run has
    /// none: its steps name the converter of each ARW.
    static func convertersLine(dnglab: Int, adobe: Int, dryRun: Bool) -> String? {
        guard !dryRun, dnglab > 0, adobe > 0 else { return nil }
        return "Converted with \(ConverterKind.dnglab.name): \(dnglab). With \(ConverterKind.adobe.name): \(adobe)."
    }

    /// How many originals the run moved to the Trash, of the ARW files that
    /// it converted (design 14.3): `Originals moved to the Trash: 11 of 12.`
    /// Nil when the run was not asked to move them. The window shows it
    /// under the counts, and VoiceOver hears it.
    ///
    /// This is for the summary of a real run, as `lightroomLine` is.
    public var originalsLine: String? {
        Self.originalsLine(asked: trashOriginals, moved: originalsInTrash, converted: converted, dryRun: false)
    }

    /// The one rule for the line about the originals. It exists only when
    /// the option was on. A dry run has none: it moved nothing, and its
    /// steps name each ARW that a run would move.
    static func originalsLine(asked: Bool, moved: Int, converted: Int, dryRun: Bool) -> String? {
        guard asked, !dryRun else { return nil }
        return "Originals moved to the Trash: \(moved) of \(converted)."
    }

    /// True when a file failed or was blocked. A front end then marks the
    /// result as one to look at. A stopped run with no such file is not one,
    /// a DNG with no full match (`convertedUnmatched`) is not one, an
    /// original that stays (`originalKept`) is not one, and a run on a
    /// volume that gives no folder lock (`noFolderLock`) is not one.
    public var needsAttention: Bool { failed > 0 || blocked > 0 }

    /// The sentence about the ARW files the run left, with the count. Nil
    /// when it left none.
    ///
    /// - Parameter converterAvailable: true when one converter or the other
    ///   is installed (`RawConverters.canConvert`). False adds the reason,
    ///   "No converter is installed."
    public func unconvertedARWsLine(converterAvailable: Bool) -> String? {
        Self.unconvertedARWsLine(count: unconvertedARWs, dryRun: false, converterAvailable: converterAvailable)
    }

    static func unconvertedARWsLine(count: Int, dryRun: Bool, converterAvailable: Bool) -> String? {
        guard count > 0 else { return nil }
        let files = count == 1 ? "1 ARW file" : "\(count) ARW files"
        let verb = dryRun ? "would not be" : (count == 1 ? "was not" : "were not")
        return "\(files) \(verb) converted." + (converterAvailable ? "" : " No converter is installed.")
    }
}

/// One completed step of a run: how many steps are complete, how many the
/// run has, and the file of this step. A conversion is one step, the tag of
/// a DNG is one, and so is each ARW that the run handles when it moves the
/// originals (design 14.3).
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
