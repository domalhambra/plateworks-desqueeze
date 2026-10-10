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
/// **What each answer of `flock` means here** (design 13.9).
///
/// | Answer | Meaning |
/// |---|---|
/// | 0 | The lock is this run's. |
/// | `EWOULDBLOCK` | Another run holds it. This run does not start. |
/// | `ENOTSUP`, `EOPNOTSUPP`, `ENOLCK`, `ENOSYS`, `EINVAL` | The volume has no such lock. The run goes on without one, and its result says so with one note (`FileNote.noFolderLock`). |
/// | `EISDIR` | The same. Apple's published source of the SMB file system answers this for a folder. |
/// | `EINTR` | A signal broke the call, and the call said nothing. It is asked again, `triesAfterAnInterrupt` times at most. After that it is any other number. |
/// | Any other number | The system failed, and nothing is known about the lock. The run does not start: it must not work in a folder that another run can hold. The front end says that the folder could not be read, with the system's words. For `EBADF` the descriptor is not closed: the system says that it is not this run's. |
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

    /// Thrown by `DesqueezeJob.run(folder:)` when the lock call failed, and
    /// its answer says nothing about the lock (`Taken.failed`). The run did
    /// not start: it read no file and changed none. A front end shows it as
    /// a folder that could not be read, with these words on the detail line.
    public struct Failed: Error, Equatable, LocalizedError {
        /// The `errno` of `flock`.
        public let code: Int32

        public init(code: Int32) {
            self.code = code
        }

        /// The system's words for `code`, and nothing else.
        public var errorDescription: String? { String(cString: strerror(code)) }
    }

    /// The answers of `flock` that say "this volume has no such lock"
    /// (design 13.9). No other answer lets a run go on without a lock.
    static let answersOfAVolumeWithNoLock: Set<Int32> = [ENOTSUP, EOPNOTSUPP, ENOLCK, EISDIR, ENOSYS, EINVAL]

    /// How many more times `flock` is asked after a signal broke the call
    /// (`EINTR`). After the last one, `EINTR` is a failure as any other.
    static let triesAfterAnInterrupt = 3

    /// What `--verbose` says when the volume gave no lock: the number of
    /// the error, and the system's words for it. The note of the result has
    /// the sentence for a person (`FileNote.noFolderLock`). The only place
    /// that makes this line.
    static func noLockLine(code: Int32) -> String {
        "The volume gave no folder lock: error \(code), \(String(cString: strerror(code)))"
    }

    /// What one try to take the lock gave.
    public enum Taken: Sendable {
        /// The lock is the caller's, until `Held.release`.
        case held(Held)
        /// Another run holds the lock: in another process, or in this one.
        case busy
        /// The volume gave no lock for a folder. The value is the `errno` of
        /// `flock`, one of `answersOfAVolumeWithNoLock`. The run goes on
        /// without a lock, and says so.
        case noLockOnThisVolume(Int32)
        /// The folder could not be opened. The value is the `errno` of
        /// `open`. No lock was asked for.
        case unreadable(Int32)
        /// The lock call failed, and its answer says nothing about the
        /// lock. The value is the `errno` of `flock`. The run does not
        /// start.
        case failed(Int32)
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

    /// Tries to take the lock on `folder`. It never waits for another run.
    /// It asks `flock` once, and again only after a signal broke the call.
    public func take(_ folder: URL) -> Taken {
        let opened = open(folder.path)
        guard opened.descriptor >= 0 else { return .unreadable(opened.code) }
        let descriptor = opened.descriptor
        let close = close
        var answer = lock(descriptor)
        var triesLeft = Self.triesAfterAnInterrupt
        while answer == EINTR, triesLeft > 0 {
            answer = lock(descriptor)
            triesLeft -= 1
        }
        switch answer {
        case 0:
            return .held(Held(close: { close(descriptor) }))
        case EWOULDBLOCK:
            close(descriptor)
            return .busy
        case let code where Self.answersOfAVolumeWithNoLock.contains(code):
            close(descriptor)
            return .noLockOnThisVolume(code)
        case EBADF:
            // The system says that the descriptor is not open. A close
            // could then close a file that something else has opened under
            // the same number.
            return .failed(EBADF)
        case let code:
            close(descriptor)
            return .failed(code)
        }
    }
}
