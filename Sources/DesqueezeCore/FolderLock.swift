import Foundation

/// One run in a folder at a time (design 13.9).
///
/// A second run that starts while the first works would send the first
/// run's work file to the Trash as a leftover, and each run could then act
/// on the other's half-written file. So a run takes this lock for its whole
/// length, and a second run does not start. A scan and a dry run take no
/// lock: they change no file.
///
/// **How.** The run opens the folder itself, read-only, and asks for
/// `flock(descriptor, LOCK_EX | LOCK_NB)`. No lock file is made, and nothing
/// in the folder changes. The lock is advisory: it stops only a program that
/// asks for the same lock, so Finder, Lightroom, exiftool and the converters
/// work in the folder as before. The descriptor is opened with `O_CLOEXEC`,
/// so no program that the run starts takes the lock with it.
///
/// **Measured on this Mac** (macOS 27.2, 2026-10-10), on the startup volume
/// and on disk images of APFS, HFS+, ExFAT and MS-DOS (FAT32). All four gave
/// the same answers:
///
/// - `flock` on the descriptor of a folder gives the lock.
/// - A second `open` and `flock` in the same process answers `EWOULDBLOCK`
///   (35, the same number as `EAGAIN`). The lock belongs to the open file
///   description, not to the process. So two runs in one process stop each
///   other as two processes do.
/// - A second process answers `EWOULDBLOCK` while the first holds the lock.
/// - The lock goes with the close of the descriptor, and with the end of
///   the process, also an end by `SIGKILL`. No stale lock stays behind.
/// - Files in a locked folder can be made, renamed and removed.
///
/// So none of the local volumes gave "no lock". That answer is for a
/// volume that is not local. It was not measured: this Mac has no network
/// volume to test on.
///
/// **What each answer of `flock` means here.**
///
/// | Answer | Meaning |
/// |---|---|
/// | 0 | The lock is this run's. |
/// | `EWOULDBLOCK` | Another run holds it. This run does not start. |
/// | `ENOTSUP`, `EOPNOTSUPP`, `ENOLCK` | The volume has no such lock. The run goes on without one. |
/// | `EISDIR` | The same. Apple's published source of the SMB file system answers this for a folder. |
/// | Any other number | The same. The folder was opened, so it can be read, and the scan that follows reports a folder that cannot. A lock that no volume of this kind gives must not stop every run on it. |
///
/// A folder that cannot be opened is not a question for the lock. The run
/// then takes the path of a folder that could not be read.
public struct FolderLock: Sendable {
    /// What every front end says when another run holds the lock. The only
    /// place that makes this sentence.
    public static let busyMessage = "Another Desqueeze run is working in this folder. Wait for it to end, "
        + "then run again."

    /// Thrown by `DesqueezeJob.run(folder:)` when another run holds the
    /// lock. The run did not start: it read no file and changed none.
    public struct Busy: Error, Equatable, LocalizedError {
        public init() {}

        /// `FolderLock.busyMessage`.
        public var errorDescription: String? { FolderLock.busyMessage }
    }

    /// What one try to take the lock gave.
    public enum Taken: Sendable {
        /// The lock is the caller's, until `Held.release`.
        case held(Held)
        /// Another run holds the lock: in another process, or in this one.
        case busy
        /// The volume gave no lock for a folder. The value is the `errno` of
        /// `flock`. The run goes on without a lock.
        case noLockOnThisVolume(Int32)
        /// The folder could not be opened. The value is the `errno` of
        /// `open`. No lock was asked for.
        case unreadable(Int32)
    }

    /// A lock that is held. It stays held until `release`, or until the
    /// process ends. Nothing releases it for the caller: a lock that is
    /// forgotten stops the next run, and does not let two runs in.
    public final class Held: @unchecked Sendable {
        private let guardLock = NSLock()
        private var close: (@Sendable () -> Void)?

        init(close: @escaping @Sendable () -> Void) {
            self.close = close
        }

        /// Gives the lock up. A second call does nothing.
        public func release() {
            guardLock.lock()
            let close = self.close
            self.close = nil
            guardLock.unlock()
            close?()
        }
    }

    /// `open(path, O_RDONLY | O_CLOEXEC)`: the descriptor and 0, or -1 and
    /// the `errno`.
    let open: @Sendable (String) -> (descriptor: Int32, code: Int32)
    /// `flock(descriptor, LOCK_EX | LOCK_NB)`: 0, or the `errno`.
    let lock: @Sendable (Int32) -> Int32
    /// `close(descriptor)`. It gives the lock up.
    let close: @Sendable (Int32) -> Void

    /// Tests inject the three calls to drive each answer.
    init(open: @escaping @Sendable (String) -> (descriptor: Int32, code: Int32),
         lock: @escaping @Sendable (Int32) -> Int32,
         close: @escaping @Sendable (Int32) -> Void) {
        self.open = open
        self.lock = lock
        self.close = close
    }

    /// The calls of the system.
    public static let system = FolderLock(
        open: {
            let descriptor = Foundation.open($0, O_RDONLY | O_CLOEXEC)
            return (descriptor, descriptor < 0 ? errno : 0)
        },
        lock: { flock($0, LOCK_EX | LOCK_NB) == 0 ? 0 : errno },
        close: { _ = Foundation.close($0) })

    /// Tries once to take the lock on `folder`. It never waits.
    public func take(_ folder: URL) -> Taken {
        let opened = open(folder.path)
        guard opened.descriptor >= 0 else { return .unreadable(opened.code) }
        let descriptor = opened.descriptor
        let close = close
        switch lock(descriptor) {
        case 0:
            return .held(Held(close: { close(descriptor) }))
        case EWOULDBLOCK:
            close(descriptor)
            return .busy
        case let code:
            close(descriptor)
            return .noLockOnThisVolume(code)
        }
    }
}
