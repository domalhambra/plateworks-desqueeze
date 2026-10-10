import Foundation

/// What counts as a folder when a person drops one, chooses one, or names
/// one at launch (design, section 5).
public enum FolderChoice {
    /// The folder that `url` names, or nil when it names none.
    ///
    /// A symbolic link to a folder is that folder: the result is the folder
    /// itself, so the window shows its name and not the name of the link. A
    /// package, such as an app or a photo library, is a folder on the disk
    /// and one item to a person. It is not a folder here.
    public static func folder(at url: URL) -> URL? {
        let resolved = url.resolvingSymlinksInPath()
        guard let values = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
              values.isDirectory == true, values.isPackage != true else { return nil }
        return resolved
    }

    /// Why `folder(at:)` gives nil for `url`: one sentence for a person.
    /// The command line tool and the MCP server say these words after the
    /// path, so a file, a package and a path with nothing at it read the
    /// same in both. The window does not: it says "Drop a folder" for each
    /// of the three.
    public static func whyNotAFolder(_ url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path) else { return "Nothing is at this path." }
        if (try? resolved.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
            return "It is a package, such as an app or a photo library, and not a folder of photos."
        }
        return "It is a file, not a folder."
    }
}
