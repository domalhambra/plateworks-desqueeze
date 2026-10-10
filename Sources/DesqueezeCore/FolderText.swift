import Foundation

/// The words and the counts that a front end shows about a folder (design,
/// sections 5 and 7).
///
/// Each one is a pure function of a `FolderSnapshot` and of whether a
/// converter is there: dnglab, or Adobe DNG Converter, or both
/// (`RawConverters.canConvert`). The window and the command line tool only show them,
/// so the two cannot say different things about one folder. The sentence
/// about an orphan backup is made at `FileNote.orphanBackup`, and nowhere
/// else: a front end and a run both show that note's `line`.
public enum FolderText {
    public static let noPhotos = "No DNG or ARW files in this folder."
    public static let readOnly = "This folder is read-only. Desqueeze cannot change its files."
    /// For a folder whose scan failed, and for a path that names no folder
    /// (design, section 8).
    public static let unreadable = "This folder could not be read."
    /// The window names this many orphan backups. The others are a count.
    public static let namedOrphanLimit = 5

    /// `unreadable` with the path after it, as the command line tool prints
    /// it: `This folder could not be read: /Volumes/Card/Shoot 1`.
    public static func unreadable(path: String) -> String {
        "\(unreadable.dropLast()): \(path)"
    }

    /// The label of the run button for `count` photos.
    public static func runLabel(count: Int) -> String {
        switch count {
        case ...0: return "Desqueeze"
        case 1: return "Desqueeze 1 photo"
        default: return "Desqueeze \(count) photos"
        }
    }

    /// The messages about a folder: the read-only sentence, then one line
    /// for each orphan backup, with the name to rename it to.
    ///
    /// - Parameters:
    ///   - orphanBackups: the file names, each `<name>.dng_original`.
    ///   - namedOrphanLimit: how many orphan backups to name. `and N more`
    ///     follows when there are more. Nil names every one.
    public static func messages(isWritable: Bool, orphanBackups: [String], namedOrphanLimit: Int?) -> [String] {
        var messages: [String] = []
        if !isWritable { messages.append(readOnly) }
        let named = orphanBackups.prefix(namedOrphanLimit ?? orphanBackups.count)
        messages += named.map { FileNote.orphanBackup(named: $0).line }
        if named.count < orphanBackups.count {
            messages.append("and \(orphanBackups.count - named.count) more")
        }
        return messages
    }
}

extension FolderSnapshot {
    /// For example `216 DNG · 12 ARW to convert`.
    ///
    /// A folder that holds only an orphan backup is not empty: its counts
    /// show, and `messages` names the backup.
    ///
    /// - Parameter converterAvailable: true when one converter or the other
    ///   is installed. False says why the ARW files wait.
    public func countsLine(converterAvailable: Bool) -> String {
        if isEmpty { return FolderText.noPhotos }
        var parts = ["\(dngs.count) DNG"]
        if !pendingARWs.isEmpty {
            parts.append(converterAvailable
                ? "\(pendingARWs.count) ARW to convert"
                : "\(pendingARWs.count) ARW cannot be converted: Adobe DNG Converter is not installed")
        }
        return parts.joined(separator: " · ")
    }

    /// The photos a run works on: the DNG files, plus the pending ARW files
    /// that can convert. With neither converter the ARW files are not in it.
    public func runCount(converterAvailable: Bool) -> Int {
        dngs.count + (converterAvailable ? pendingARWs.count : 0)
    }

    /// `Desqueeze N photos`, `Desqueeze 1 photo`, or `Desqueeze` when there
    /// is nothing to run.
    public func runLabel(converterAvailable: Bool) -> String {
        FolderText.runLabel(count: runCount(converterAvailable: converterAvailable))
    }

    /// The messages about this folder, as the window shows them: at most
    /// `FolderText.namedOrphanLimit` orphan backups by name.
    public var messages: [String] {
        FolderText.messages(isWritable: isWritable, orphanBackups: orphanBackups.map(\.lastPathComponent),
                            namedOrphanLimit: FolderText.namedOrphanLimit)
    }
}
