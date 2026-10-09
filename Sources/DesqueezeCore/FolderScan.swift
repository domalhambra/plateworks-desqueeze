import Foundation

/// One DNG in the folder, with what the scan learned about it.
public struct DNGFile: Equatable, Sendable {
    public let url: URL
    /// The current `DefaultScale`. A missing tag reads as 1 and 1.
    public var horizontal: Double
    public var vertical: Double
    /// The source file name that the converter recorded, when it did.
    public var originalRawFileName: String?
    /// True when `<name>_original` was beside the file at scan time.
    public var hasBackup: Bool

    public var name: String { url.lastPathComponent }

    public init(url: URL, horizontal: Double, vertical: Double, originalRawFileName: String?, hasBackup: Bool) {
        self.url = url
        self.horizontal = horizontal
        self.vertical = vertical
        self.originalRawFileName = originalRawFileName
        self.hasBackup = hasBackup
    }
}

public struct FolderContents: Equatable, Sendable {
    public var dngs: [URL]
    public var arws: [URL]
}

public enum FolderScan {
    /// The DNG and ARW files at the top level of `folder`, sorted by name.
    /// Subfolders, hidden files, and other file types are not returned.
    public static func contents(of folder: URL) throws -> FolderContents {
        let items = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [])
        var contents = FolderContents(dngs: [], arws: [])
        for item in items {
            guard !item.lastPathComponent.hasPrefix("."),
                  (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            switch item.pathExtension.lowercased() {
            case "dng": contents.dngs.append(item)
            case "arw": contents.arws.append(item)
            default: break
            }
        }
        let byName: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        contents.dngs.sort(by: byName)
        contents.arws.sort(by: byName)
        return contents
    }

    /// The ARW files that no DNG claims.
    ///
    /// A DNG claims an ARW when the two have the same base name, or when the
    /// DNG's `originalRawFileName` equals the ARW's file name. Letter case is
    /// ignored. The second rule protects a folder whose DNG files were renamed
    /// on import: without it, a rerun would convert each ARW again.
    public static func pending(arws: [URL], dngs: [DNGFile]) -> [URL] {
        var claimedBaseNames = Set<String>()
        var claimedFileNames = Set<String>()
        for dng in dngs {
            claimedBaseNames.insert(dng.url.deletingPathExtension().lastPathComponent.lowercased())
            if let original = dng.originalRawFileName { claimedFileNames.insert(original.lowercased()) }
        }
        return arws.filter { arw in
            !claimedBaseNames.contains(arw.deletingPathExtension().lastPathComponent.lowercased())
                && !claimedFileNames.contains(arw.lastPathComponent.lowercased())
        }
    }
}
