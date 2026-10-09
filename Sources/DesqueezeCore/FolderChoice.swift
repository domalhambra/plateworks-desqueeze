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
}
