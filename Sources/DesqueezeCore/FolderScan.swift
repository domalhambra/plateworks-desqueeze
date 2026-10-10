import Foundation

/// One DNG in the folder, with what the scan learned about it.
public struct DNGFile: Equatable, Sendable {
    public let url: URL
    /// The current `DefaultScale`. Nil when it is not known: exiftool gave no
    /// value, or no row, for this file. Unknown is not "no stretch".
    public var scale: Scale?
    /// The source file name that the DNG records in `OriginalRawFileName`,
    /// when it has one. Adobe DNG Converter writes it, and the app writes it
    /// into each DNG that dnglab makes.
    public var originalRawFileName: String?
    /// True when `<name>_original` was beside the file at scan time.
    public var hasBackup: Bool

    public var name: String { url.lastPathComponent }

    public init(url: URL, scale: Scale?, originalRawFileName: String?, hasBackup: Bool) {
        self.url = url
        self.scale = scale
        self.originalRawFileName = originalRawFileName
        self.hasBackup = hasBackup
    }
}

/// The files at the top level of one folder that a scan looks at.
public struct FolderContents: Equatable, Sendable {
    public var dngs: [URL]
    public var arws: [URL]
    /// Each `<name>.dng_original` whose DNG is not beside it.
    public var orphanBackups: [URL]
}

/// Lists the top level of a folder, and decides which ARW files are pending.
/// It reads no tag.
public enum FolderScan {
    /// The DNG and ARW files at the top level of `folder`, and each DNG
    /// backup that has lost its DNG, sorted by name. Subfolders, hidden
    /// files, and other file types are not returned.
    public static func contents(of folder: URL) throws -> FolderContents {
        let items = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [])
        var contents = FolderContents(dngs: [], arws: [], orphanBackups: [])
        for item in items {
            guard !item.lastPathComponent.hasPrefix("."), isRegularFile(item) else { continue }
            switch item.pathExtension.lowercased() {
            case "dng": contents.dngs.append(item)
            case "arw": contents.arws.append(item)
            case "dng_original":
                // The DNG is looked up on the disk, not in the list above, so
                // the volume decides letter case here as it does for
                // `FileBackups`. A folder or a link named like the DNG is not
                // a DNG to this scan, so it does not count.
                let name = item.lastPathComponent.dropLast("_original".count)
                let dng = item.deletingLastPathComponent().appendingPathComponent(String(name))
                if !isRegularFile(dng) { contents.orphanBackups.append(item) }
            default: break
            }
        }
        let byName: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        contents.dngs.sort(by: byName)
        contents.arws.sort(by: byName)
        contents.orphanBackups.sort(by: byName)
        return contents
    }

    /// False for a folder, and for a symbolic link: this does not follow one.
    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    /// The ARW files that no DNG claims.
    ///
    /// A DNG claims an ARW when the two have the same base name, or when the
    /// DNG's `originalRawFileName` equals the ARW's file name. Letter case is
    /// ignored. The second rule protects a folder whose DNG files were renamed
    /// on import: without it, a rerun would convert each ARW again.
    ///
    /// An orphan backup claims an ARW by base name, as its DNG would. That
    /// DNG is waiting to be renamed back. A conversion would make a second
    /// DNG of the same photo, with an older backup beside it.
    ///
    /// Each claim blocks conversion, on purpose. No converter writes over a
    /// DNG, and none gets a name that is taken: each one writes the hidden
    /// work file of the ARW, and it does not start when anything has the
    /// name `<base>.dng` (`ConverterRules`). So a wrong "pending" makes a
    /// failed file, "A DNG with this name exists already", or a second DNG
    /// of a photo whose DNG has another name. A wrong "claimed" only leaves
    /// one ARW waiting. Known limit: a DNG that was renamed to another
    /// shot's base name claims that shot's ARW too.
    public static func pending(arws: [URL], dngs: [DNGFile], orphanBackups: [URL]) -> [URL] {
        var claimedBaseNames = Set<String>()
        var claimedFileNames = Set<String>()
        for dng in dngs {
            claimedBaseNames.insert(baseName(dng.url))
            if let original = dng.originalRawFileName { claimedFileNames.insert(original.lowercased()) }
        }
        for backup in orphanBackups {
            // `frame.dng_original` is the backup of `frame.dng`.
            let dng = String(backup.lastPathComponent.dropLast("_original".count))
            claimedBaseNames.insert(baseName(URL(fileURLWithPath: dng)))
        }
        return arws.filter { arw in
            !claimedBaseNames.contains(baseName(arw)) && !claimedFileNames.contains(arw.lastPathComponent.lowercased())
        }
    }

    /// The name with no extension, in lower case.
    private static func baseName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.lowercased()
    }
}
