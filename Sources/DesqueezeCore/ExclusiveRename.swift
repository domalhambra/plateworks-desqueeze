import Foundation

/// Gives a file a new name, and fails when anything has that name
/// (design 13.3, step 5).
///
/// A plain `rename` replaces what is at the new name. This one never does:
/// the work file of a converter gets the name `<base>.dng` only when the
/// name is free, so a DNG that another program made at the wrong moment is
/// never replaced.
///
/// **Two paths.**
///
/// 1. `renamex_np` with `RENAME_EXCL`. The system checks the name and
///    renames in one step. APFS and HFS+ have it.
/// 2. When the system says that the volume does not have that call
///    (`ENOTSUP`): a check of the name that does not follow a link, and then
///    a plain `rename`. Between the check and the rename there is a moment
///    in which another program can take the name. ExFAT takes this path for
///    a name that is free.
///
/// Measured on this Mac (macOS 27) on disk images: APFS, case-sensitive APFS
/// and HFS+ answer `EEXIST` for a name that is taken and rename to a name
/// that is free. ExFAT answers `EEXIST` for a name that is taken, and
/// `ENOTSUP` for a name that is free. `ExclusiveRenameVolumeTests` pins
/// APFS and ExFAT.
public struct ExclusiveRename: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The file has the new name.
        case moved
        /// Something has the new name: a file, a folder, or a link, also a
        /// link that points at nothing. Nothing changed.
        case nameTaken
        /// The system refused for another reason. The value is its `errno`.
        /// Nothing changed.
        case failed(Int32)

        /// The system's words for the `errno` of `failed`.
        public static func words(for code: Int32) -> String { String(cString: strerror(code)) }
    }

    /// `renamex_np(from, to, RENAME_EXCL)`: 0, or the `errno`.
    let renameExclusive: @Sendable (String, String) -> Int32
    /// True when anything has the name. It must not follow a link.
    let exists: @Sendable (String) -> Bool
    /// `rename(from, to)`: 0, or the `errno`.
    let rename: @Sendable (String, String) -> Int32

    /// Tests inject the three calls to drive each outcome.
    init(renameExclusive: @escaping @Sendable (String, String) -> Int32,
         exists: @escaping @Sendable (String) -> Bool,
         rename: @escaping @Sendable (String, String) -> Int32) {
        self.renameExclusive = renameExclusive
        self.exists = exists
        self.rename = rename
    }

    /// The calls of the system.
    public static let system = ExclusiveRename(
        renameExclusive: { renamex_np($0, $1, UInt32(RENAME_EXCL)) == 0 ? 0 : errno },
        exists: { ConverterOutput.exists(atPath: $0) },
        rename: { Foundation.rename($0, $1) == 0 ? 0 : errno })

    public func move(_ file: URL, to name: URL) -> Outcome {
        switch renameExclusive(file.path, name.path) {
        case 0: return .moved
        case EEXIST: return .nameTaken
        case ENOTSUP:
            guard !exists(name.path) else { return .nameTaken }
            let code = rename(file.path, name.path)
            return code == 0 ? .moved : .failed(code)
        case let code: return .failed(code)
        }
    }
}
