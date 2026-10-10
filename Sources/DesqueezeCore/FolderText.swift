import Foundation

/// The words and the counts that a front end shows about a folder (design,
/// sections 5 and 7).
///
/// Each one is a pure function of a `FolderSnapshot` and of whether a
/// converter is there: dnglab, or Adobe DNG Converter, or both
/// (`RawConverters.canConvert`), or of which of the two is there. The window
/// and the command line tool only show them, so the two cannot say different
/// things about one folder. The sentence
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

    /// The one line of advice about the converters, for a folder with a
    /// pending ARW (design 13.5). Nil when both converters are installed,
    /// and when no ARW is pending: the advice is about the files that wait.
    ///
    /// | Installed | The line |
    /// |---|---|
    /// | dnglab and Adobe | none |
    /// | dnglab only | Adobe is not installed, and is an optional backup. |
    /// | Adobe only | dnglab is faster, with its install command. |
    /// | Neither | The install command of dnglab. |
    ///
    /// With one converter the line is a quiet one: every ARW still converts.
    /// With neither, `FolderSnapshot.countsLine` says that the ARW files
    /// cannot be converted, and this line says what to do.
    public static func converterAdvice(pendingARWs: Int, dnglabInstalled: Bool, adobeInstalled: Bool) -> String? {
        guard pendingARWs > 0 else { return nil }
        switch (dnglabInstalled, adobeInstalled) {
        case (true, true):
            return nil
        case (true, false):
            // The words of design 13.5. The name is said once.
            return "\(ConverterKind.adobe.name) is not installed. "
                + "It is an optional backup for photos that \(ConverterKind.dnglab.name) cannot match."
        case (false, true):
            return "dnglab is faster and opens no window. Install it with: \(ToolLocator.dnglabInstallCommand)"
        case (false, false):
            return ToolLocator.dnglabInstallLine
        }
    }

    /// The sentence about the ARW files that wait, with neither converter:
    /// `12 ARW cannot be converted: no converter is installed`. The counts
    /// line and the scan text of the tool both say it.
    public static func arwsCannotConvert(count: Int) -> String {
        "\(count) ARW cannot be converted: no converter is installed"
    }

    /// The label of the run button for `count` photos: `Desqueeze N photos`,
    /// `Desqueeze 1 photo`, or `Desqueeze` when there is nothing to run. The
    /// window gives it `FolderSnapshot.runCount`.
    public static func runLabel(count: Int) -> String {
        switch count {
        case ...0: return "Desqueeze"
        case 1: return "Desqueeze 1 photo"
        default: return "Desqueeze \(count) photos"
        }
    }

    /// The label of the run button when the run also moves the originals
    /// (design 14.4): `Desqueeze 14 photos, move 12 originals to the Trash`.
    /// With no original to move, it is `runLabel(count:)`.
    ///
    /// - Parameters:
    ///   - count: the photos that the run works on.
    ///   - originalsToTrash: the pending ARW files that can convert, when
    ///     the box of the window is on. 0 when it is off.
    public static func runLabel(count: Int, originalsToTrash: Int) -> String {
        guard originalsToTrash > 0 else { return runLabel(count: count) }
        let originals = originalsToTrash == 1 ? "1 original" : "\(originalsToTrash) originals"
        return "\(runLabel(count: count)), move \(originals) to the Trash"
    }

    /// The label of the checkbox of the window (design 14.4). The only
    /// place that makes it.
    public static let trashOriginalsLabel = "Move the original ARW files to the Trash"

    /// The line under the checkbox while it is on (design 14.4): what the
    /// run will do with the originals.
    ///
    /// - Parameter count: the pending ARW files that can convert.
    public static func trashOriginalsLine(count: Int) -> String {
        count == 1
            ? "1 original ARW file goes to the Trash after its DNG file passes the check."
            : "\(count) original ARW files go to the Trash after their DNG files pass the check."
    }

    /// The messages about a folder: the read-only sentence, then one line
    /// for each orphan backup, with the name to rename it to.
    ///
    /// - Parameters:
    ///   - isWritable: false adds the read-only sentence.
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
    ///   is installed. False says why the ARW files wait: `12 ARW cannot be
    ///   converted: no converter is installed`. `converterAdvice` then gives
    ///   the install command.
    public func countsLine(converterAvailable: Bool) -> String {
        if isEmpty { return FolderText.noPhotos }
        var parts = ["\(dngs.count) DNG"]
        if !pendingARWs.isEmpty {
            parts.append(converterAvailable
                ? "\(pendingARWs.count) ARW to convert"
                : FolderText.arwsCannotConvert(count: pendingARWs.count))
        }
        return parts.joined(separator: " · ")
    }

    /// `FolderText.converterAdvice` for the pending ARW files of this folder.
    public func converterAdvice(dnglabInstalled: Bool, adobeInstalled: Bool) -> String? {
        FolderText.converterAdvice(pendingARWs: pendingARWs.count, dnglabInstalled: dnglabInstalled,
                                   adobeInstalled: adobeInstalled)
    }

    /// The photos a run works on: the DNG files, plus the pending ARW files
    /// that can convert. With neither converter the ARW files are not in it.
    public func runCount(converterAvailable: Bool) -> Int {
        dngs.count + convertibleARWs(converterAvailable: converterAvailable)
    }

    /// The pending ARW files that a run can convert, and so the originals
    /// that a run can move to the Trash (design 14.4): every pending ARW
    /// when one converter or the other is installed, and 0 with neither.
    public func convertibleARWs(converterAvailable: Bool) -> Int {
        converterAvailable ? pendingARWs.count : 0
    }

    /// The messages about this folder, as the window shows them: at most
    /// `FolderText.namedOrphanLimit` orphan backups by name.
    public var messages: [String] {
        FolderText.messages(isWritable: isWritable, orphanBackups: orphanBackups.map(\.lastPathComponent),
                            namedOrphanLimit: FolderText.namedOrphanLimit)
    }
}
