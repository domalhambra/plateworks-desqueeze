import XCTest
@testable import DesqueezeCore

/// The sentence of design 13.9. The tests hold the text here, not through
/// the core's constant, so a change of the constant fails them.
let folderBusySentence = "Another Desqueeze run is working in this folder. Wait for it to end, then run again."

/// A `FolderLock` on three fake calls, with a record of each call.
final class FakeLockCalls: @unchecked Sendable {
    /// The descriptor that `open` gives.
    static let descriptor: Int32 = 7

    /// Each call, in order: `open <folder name>`, `flock 7`, `close 7`.
    var calls: [String] = []
    /// What `open` answers: 0, or the `errno`.
    var openCode: Int32 = 0
    /// What `flock` answers: 0, or the `errno`.
    var lockCode: Int32 = 0
    /// What the first calls of `flock` answer, in order. After the last
    /// one, `flock` answers `lockCode`.
    var firstLockCodes: [Int32] = []
    /// Gets each call too, so a test can see the order of the lock and of
    /// the tools.
    var log: CallLog?

    private func record(_ call: String) {
        calls.append(call)
        log?.entries.append(call)
    }

    var lock: FolderLock {
        FolderLock(
            open: { [self] in
                record("open \(URL(fileURLWithPath: $0).lastPathComponent)")
                return openCode == 0 ? (Self.descriptor, 0) : (-1, openCode)
            },
            lock: { [self] in
                record("flock \($0)")
                return firstLockCodes.isEmpty ? lockCode : firstLockCodes.removeFirst()
            },
            close: { [self] in record("close \($0)") })
    }
}

/// What `FolderLock.take` does with each answer of the system, on fakes.
final class FolderLockTests: XCTestCase {
    let folder = URL(fileURLWithPath: "/tmp/Shoot 1")
    var system: FakeLockCalls!

    override func setUp() { system = FakeLockCalls() }

    func testTheSentenceIsTheOneOfTheDesign() {
        XCTAssertEqual(FolderLock.busyMessage, folderBusySentence)
        XCTAssertEqual(FolderLock.Busy().localizedDescription, folderBusySentence)
    }

    func testTheLockIsOneOpenAndOneFlockAndTheReleaseIsOneClose() throws {
        guard case .held(let held) = system.lock.take(folder) else { return XCTFail("the lock was not taken") }
        XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7"], "held: the descriptor stays open")
        held.release()
        XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7", "close 7"])
        // A second close could close a descriptor that something else got.
        held.release()
        XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7", "close 7"], "a second release does nothing")
    }

    func testALockThatAnotherRunHoldsIsBusyAndTheDescriptorIsClosed() {
        system.lockCode = EWOULDBLOCK
        guard case .busy = system.lock.take(folder) else { return XCTFail("EWOULDBLOCK is a lock that is held") }
        XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7", "close 7"])
    }

    // The six answers of a volume that has no such lock (design 13.9).
    // EISDIR is the answer of the SMB file system for a folder.
    func testAVolumeThatGivesNoLockForAFolderIsNotBusyAndNotUnreadable() {
        for code in [ENOTSUP, EOPNOTSUPP, ENOLCK, EISDIR, ENOSYS, EINVAL] {
            system = FakeLockCalls()
            system.lockCode = code
            guard case .noLockOnThisVolume(let answered) = system.lock.take(folder) else {
                XCTFail("errno \(code) must be a volume with no lock")
                continue
            }
            XCTAssertEqual(answered, code)
            XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7", "close 7"], "errno \(code)")
        }
    }

    // Any other answer is no word about the lock: the system failed. The
    // run must not go on as if the volume had no lock. Until 2026-10-10
    // every answer but EWOULDBLOCK meant "no lock, go on".
    func testAnyOtherAnswerIsAFailureAndNotAVolumeWithNoLock() {
        for code in [EIO, EPERM, EACCES, ENOMEM, ESTALE, 9_999] as [Int32] {
            system = FakeLockCalls()
            system.lockCode = code
            guard case .failed(let answered) = system.lock.take(folder) else {
                XCTFail("errno \(code) must be a failure of the lock call")
                continue
            }
            XCTAssertEqual(answered, code)
            XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7", "close 7"], "errno \(code)")
        }
    }

    // The system says that the descriptor is bad. Then it is not this
    // run's to close: the number can be another file's by now.
    func testADescriptorThatTheSystemCallsBadIsNotClosed() {
        system.lockCode = EBADF
        guard case .failed(let code) = system.lock.take(folder) else { return XCTFail("EBADF is a failure") }
        XCTAssertEqual(code, EBADF)
        XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7"], "no close of a bad descriptor")
    }

    // A signal broke the call, and the call said nothing about the lock.
    // The same descriptor is asked again.
    func testAnInterruptedCallIsAskedAgain() {
        system.firstLockCodes = [EINTR, EINTR]
        guard case .held(let held) = system.lock.take(folder) else { return XCTFail("the third answer is the lock") }
        XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7", "flock 7", "flock 7"])
        held.release()
        XCTAssertEqual(system.calls.last, "close 7")

        // The answer after the interrupt decides, whatever it is.
        system = FakeLockCalls()
        system.firstLockCodes = [EINTR]
        system.lockCode = EWOULDBLOCK
        guard case .busy = system.lock.take(folder) else { return XCTFail("busy after one interrupt") }
        XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7", "flock 7", "close 7"])

        system = FakeLockCalls()
        system.firstLockCodes = [EINTR]
        system.lockCode = ENOTSUP
        guard case .noLockOnThisVolume(ENOTSUP) = system.lock.take(folder) else {
            return XCTFail("no lock after one interrupt")
        }
    }

    // A call that is interrupted every time does not hold the run for
    // ever. After a small fixed number of tries it is any other error.
    func testACallThatIsInterruptedEveryTimeIsAFailureAfterAFixedNumberOfTries() {
        system.lockCode = EINTR
        guard case .failed(let code) = system.lock.take(folder) else { return XCTFail("EINTR, in the end, fails") }
        XCTAssertEqual(code, EINTR)
        XCTAssertEqual(FolderLock.triesAfterAnInterrupt, 3)
        XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7", "flock 7", "flock 7", "flock 7", "close 7"],
                       "the first call, and three more")
    }

    // MARK: The sentences

    /// The sentence of design 13.9 for a volume that gives no lock. Held
    /// here, so a change of the core's sentence fails the tests.
    static let noLockSentence = "This volume gives no folder lock. Do not start a second run in this folder "
        + "while this run works."

    func testTheNoteOfAVolumeWithNoLockIsTheSentenceOfTheDesignOnTheNameOfTheFolder() {
        XCTAssertEqual(FileNote.noFolderLock(folder), FileNote(
            name: "Shoot 1", kind: .noFolderLock, message: Self.noLockSentence, detail: nil))
    }

    // What `--verbose` adds: the number of the error, and the system's
    // words for it.
    func testTheVerboseLineOfAVolumeWithNoLockHasTheErrorNumber() {
        XCTAssertEqual(FolderLock.noLockLine(code: ENOTSUP),
                       "The volume gave no folder lock: error 45, Operation not supported")
        XCTAssertEqual(FolderLock.noLockLine(code: EISDIR), "The volume gave no folder lock: error 21, Is a directory")
    }

    // The error of a lock call that failed: the system's words, for the
    // detail line of "This folder could not be read".
    func testTheErrorOfALockCallThatFailedSaysTheSystemsWords() {
        XCTAssertEqual(FolderLock.Failed(code: EIO).localizedDescription, "Input/output error")
        XCTAssertEqual(FolderLock.Failed(code: EBADF).localizedDescription, "Bad file descriptor")
    }

    func testAFolderThatCannotBeOpenedIsUnreadableAndNoLockIsAskedFor() {
        system.openCode = EACCES
        guard case .unreadable(let code) = system.lock.take(folder) else {
            return XCTFail("a failed open is an unreadable folder")
        }
        XCTAssertEqual(code, EACCES)
        XCTAssertEqual(system.calls, ["open Shoot 1"], "no flock and no close of a descriptor that is not there")
    }
}

/// The system's own lock, on a temporary folder of the startup volume.
final class FolderLockSystemTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws { folder = try makeTemporaryFolder() }
    override func tearDown() { removeTemporaryFolder(folder) }

    // The lock belongs to the open file description, so a second run in the
    // same process is stopped as a second process is.
    func testASecondTakeInTheSameProcessIsBusyUntilTheFirstIsReleased() throws {
        guard case .held(let first) = FolderLock.system.take(folder) else { return XCTFail("the first take") }
        guard case .busy = FolderLock.system.take(folder) else {
            first.release()
            return XCTFail("the second take must be busy while the first is held")
        }
        first.release()
        guard case .held(let third) = FolderLock.system.take(folder) else {
            return XCTFail("the lock is free after the release")
        }
        third.release()
    }

    func testTheLockMakesNoFileAndChangesNoFileInTheFolder() throws {
        let photo = folder.appendingPathComponent("A.dng")
        try Data("x".utf8).write(to: photo)
        guard case .held(let held) = FolderLock.system.take(folder) else { return XCTFail("the take") }
        defer { held.release() }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["A.dng"])
        // The lock is advisory: a file in a locked folder can be made,
        // renamed and removed, as exiftool and the converters do.
        let work = folder.appendingPathComponent(".A.desqueeze-work.dng")
        try Data("y".utf8).write(to: work)
        try FileManager.default.moveItem(at: work, to: folder.appendingPathComponent("B.dng"))
        try FileManager.default.removeItem(at: photo)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["B.dng"])
    }

    func testAFolderThatIsNotThereIsUnreadable() {
        guard case .unreadable(let code) = FolderLock.system.take(folder.appendingPathComponent("No such folder")) else {
            return XCTFail("nothing is at the path")
        }
        XCTAssertEqual(code, ENOENT)
    }

    // A program that the run starts must not take the lock with it: the
    // lock goes when the run ends, also while a converter still works. So
    // the descriptor on the folder has the flag that closes it in a new
    // program.
    func testTheDescriptorOfTheLockIsClosedInAProgramThatTheRunStarts() throws {
        guard case .held(let held) = FolderLock.system.take(folder) else { return XCTFail("the take") }
        defer { held.release() }
        let wanted = folder.resolvingSymlinksInPath().path
        var found = 0
        for descriptor in 0..<min(getdtablesize(), 4096) {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(descriptor, F_GETPATH, &path) == 0,
                  URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().path == wanted else { continue }
            found += 1
            XCTAssertEqual(fcntl(descriptor, F_GETFD) & FD_CLOEXEC, FD_CLOEXEC,
                           "descriptor \(descriptor) on the folder stays open in a program that the run starts")
        }
        XCTAssertEqual(found, 1, "the lock is one descriptor on the folder")
    }
}

/// The lock on a volume that is not APFS. The image is made and attached by
/// `ExclusiveRenameVolumeTests`, which also detaches it.
extension ExclusiveRenameVolumeTests {
    // Measured 2026-10-10: ExFAT gives the lock for a folder, as APFS does.
    // So the path "no lock on this volume" is not the path of an ExFAT card.
    func testOnExFATAFolderLockIsHeldAndASecondTakeIsBusy() throws {
        let shoot = try volume("ExFAT", named: "lock")
        guard case .held(let held) = FolderLock.system.take(shoot) else {
            return XCTFail("ExFAT gave no lock for a folder")
        }
        defer { held.release() }
        guard case .busy = FolderLock.system.take(shoot) else {
            return XCTFail("the second take on ExFAT must be busy")
        }
    }
}

/// One run in a folder at a time: what `DesqueezeJob.run(folder:)` does with
/// the lock (design 13.9). Fakes for the tools, and a real temporary folder.
final class FolderLockJobTests: XCTestCase {
    let factor = SqueezeFactor(1.5)!
    var shoot: URL!
    var h: JobHarness!
    var system: FakeLockCalls!

    override func setUpWithError() throws {
        shoot = try makeTemporaryFolder()
        h = JobHarness()
        system = FakeLockCalls()
        system.log = h.log
    }

    override func tearDown() { removeTemporaryFolder(shoot) }

    /// A job on the harness's fakes and on the fake lock.
    func job() -> DesqueezeJob {
        DesqueezeJob(tag: h.tag, converters: h.converters(), backups: h.backups, lock: system.lock)
    }

    /// One DNG at no stretch and one pending ARW.
    func makeShoot() throws {
        for name in ["A.dng", "X.ARW"] { try Data("x".utf8).write(to: shoot.appendingPathComponent(name)) }
        h.tag.rows = [TagRow(fileName: "A.dng", scale: .noStretch, originalRawFileName: nil)]
    }

    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: shoot.path).sorted()
    }

    func testARunDoesNotStartWhileAnotherRunHoldsTheLock() throws {
        try makeShoot()
        system.lockCode = EWOULDBLOCK
        XCTAssertThrowsError(try job().run(folder: shoot, factor: factor, convert: true, trashOriginals: false)) {
            XCTAssertEqual($0 as? FolderLock.Busy, FolderLock.Busy())
            XCTAssertEqual($0.localizedDescription, folderBusySentence)
        }
        XCTAssertEqual(h.log.entries, ["open Shoot 1", "flock 7", "close 7"],
                       "no call to exiftool and none to a converter")
        XCTAssertEqual(try names(), ["A.dng", "X.ARW"])
    }

    func testRemoveDoesNotStartWhileAnotherRunHoldsTheLock() throws {
        try makeShoot()
        system.lockCode = EWOULDBLOCK
        XCTAssertThrowsError(try job().run(folder: shoot,
                                           factor: .noStretch, convert: false, trashOriginals: false, remove: true)) {
            XCTAssertTrue($0 is FolderLock.Busy)
        }
        XCTAssertEqual(h.log.entries, ["open Shoot 1", "flock 7", "close 7"])
    }

    func testTheLockIsTakenBeforeTheScanAndHeldToTheLastFile() throws {
        try makeShoot()
        let summary = try job().run(folder: shoot, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(h.log.entries, [
            "open Shoot 1", "flock 7",
            "readFolder", "convert X.ARW",
            "write 1.5 1 A.dng", "read A.dng", "trash A.dng",
            "write 1.5 1 X.dng", "read X.dng", "trash X.dng",
            "close 7",
        ])
    }

    // The six answers of a volume that has no such lock. The run goes on,
    // and its result says so with one note, on the name of the folder. The
    // note is information: nothing failed, and nothing was blocked.
    func testOnAVolumeWithNoSuchLockTheRunGoesOnWithoutOneAndSaysSo() throws {
        try makeShoot()
        for code in [ENOTSUP, EOPNOTSUPP, ENOLCK, EISDIR, ENOSYS, EINVAL] {
            h.log.entries = []
            h.tag.rows = [TagRow(fileName: "A.dng", scale: .noStretch, originalRawFileName: nil)]
            system.lockCode = code
            let summary = try job().run(folder: shoot, factor: factor, convert: false, trashOriginals: false)
            XCTAssertEqual(summary.set, 1, "errno \(code)")
            XCTAssertEqual(h.log.entries, [
                "open Shoot 1", "flock 7", "close 7",
                "readFolder", "write 1.5 1 A.dng", "read A.dng", "trash A.dng",
            ], "errno \(code)")
            XCTAssertEqual(summary.notes, [FileNote(
                name: "Shoot 1", kind: .noFolderLock, message: FolderLockTests.noLockSentence, detail: nil)],
                           "errno \(code)")
            XCTAssertEqual([summary.failed, summary.blocked], [0, 0], "errno \(code)")
            XCTAssertFalse(summary.needsAttention, "errno \(code): the note is information")
        }
    }

    // The note is about the folder, so it is the first one: before the
    // orphan backups, and before the note of each file.
    func testTheNoteOfAVolumeWithNoLockIsTheFirstNote() throws {
        try makeShoot()
        try Data("x".utf8).write(to: shoot.appendingPathComponent("gone.dng_original"))
        h.tag.failWrites = ["A.dng"]
        system.lockCode = ENOTSUP
        let summary = try job().run(folder: shoot, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual(summary.notes.map(\.kind), [.noFolderLock, .orphanBackup, .failed])
        XCTAssertTrue(summary.needsAttention, "the file that failed still needs attention")
    }

    // Remove takes the lock too, so it says the same.
    func testRemoveOnAVolumeWithNoSuchLockGoesOnAndSaysSo() throws {
        try makeShoot()
        h.tag.rows = [TagRow(fileName: "A.dng", scale: Scale(horizontal: 1.5, vertical: 1), originalRawFileName: nil)]
        system.lockCode = EOPNOTSUPP
        let summary = try job().run(folder: shoot, factor: .noStretch, convert: false, trashOriginals: false,
                                    remove: true)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.notes.map(\.kind), [.noFolderLock])
    }

    // A run that has the lock says nothing about it.
    func testARunThatHoldsTheLockHasNoSuchNote() throws {
        try makeShoot()
        let summary = try job().run(folder: shoot, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual(summary.notes, [])
    }

    // `--verbose` also says the number of the error. The line comes at the
    // moment of the lock, so it stands before the first command.
    func testOnAVolumeWithNoSuchLockVerboseSaysTheErrorNumberBeforeTheScan() throws {
        try makeShoot()
        system.lockCode = ENOLCK
        let log = h.log
        let job = DesqueezeJob(tag: h.tag, converters: h.converters(), backups: h.backups, lock: system.lock,
                               verbose: { log.entries.append("verbose: \($0)") })
        _ = try job.run(folder: shoot, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual(Array(h.log.entries.prefix(5)), [
            "open Shoot 1", "flock 7", "close 7",
            "verbose: The volume gave no folder lock: error 77, No locks available", "readFolder",
        ])

        // With the lock, `--verbose` has no such line.
        h.log.entries = []
        system.lockCode = 0
        _ = try job.run(folder: shoot, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual(h.log.entries.filter { $0.hasPrefix("verbose") }, [])
    }

    // A signal broke the lock call. The run asks again, gets the lock, and
    // is a run as any other: it holds the lock to its last file.
    func testAfterAnInterruptedLockCallTheRunAsksAgainAndHoldsTheLock() throws {
        try makeShoot()
        system.firstLockCodes = [EINTR]
        let summary = try job().run(folder: shoot, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.notes, [], "the run has the lock")
        XCTAssertEqual(h.log.entries, [
            "open Shoot 1", "flock 7", "flock 7",
            "readFolder", "write 1.5 1 A.dng", "read A.dng", "trash A.dng",
            "close 7",
        ])
    }

    // Any other answer of the lock call stops the run before it reads a
    // file, on the path of a folder that could not be read. The error has
    // the system's words, for the detail line. Until 2026-10-10 the run
    // went on with no lock, and said nothing.
    func testAnyOtherAnswerOfTheLockCallStopsTheRunBeforeItReadsAFile() throws {
        try makeShoot()
        for code in [EIO, EPERM, EINTR] {
            h.log.entries = []
            system.lockCode = code
            XCTAssertThrowsError(try job().run(folder: shoot, factor: factor, convert: true, trashOriginals: false),
                                 "errno \(code)") {
                XCTAssertEqual($0 as? FolderLock.Failed, FolderLock.Failed(code: code))
                XCTAssertEqual($0.localizedDescription, String(cString: strerror(code)))
                XCTAssertFalse($0 is FolderLock.Busy)
            }
            XCTAssertEqual(h.log.entries.filter { !$0.hasPrefix("flock") }, ["open Shoot 1", "close 7"],
                           "errno \(code): no call to exiftool and none to a converter")
            XCTAssertEqual(try names(), ["A.dng", "X.ARW"])
        }
    }

    func testABadDescriptorStopsTheRunAndIsNotClosed() throws {
        try makeShoot()
        system.lockCode = EBADF
        XCTAssertThrowsError(try job().run(folder: shoot, factor: factor, convert: true, trashOriginals: false)) {
            XCTAssertEqual($0 as? FolderLock.Failed, FolderLock.Failed(code: EBADF))
        }
        XCTAssertEqual(h.log.entries, ["open Shoot 1", "flock 7"], "no close, no exiftool and no converter")
        XCTAssertEqual(try names(), ["A.dng", "X.ARW"])
    }

    func testTheLockIsReleasedAfterARunWithAFileThatFailed() throws {
        try makeShoot()
        h.tag.failWrites = ["A.dng"]
        let summary = try job().run(folder: shoot, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7", "close 7"])
        XCTAssertEqual(h.log.entries.last, "close 7", "released after the last file, not before")
    }

    func testTheLockIsReleasedAfterARunThatWasCancelled() throws {
        try makeShoot()
        let flag = CancelFlag()
        h.converter.onConvert = { flag.cancel() }
        let summary = try job().run(folder: shoot, factor: factor, convert: true, trashOriginals: false, cancel: flag)
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(system.calls, ["open Shoot 1", "flock 7", "close 7"])
        XCTAssertEqual(h.log.entries.last, "close 7")
    }

    func testTheLockIsReleasedAfterARunWhoseScanThrows() throws {
        try makeShoot()
        h.tag.readFolderError = TagError.toolFailed("Error: exiftool did not start")
        XCTAssertThrowsError(try job().run(folder: shoot, factor: factor, convert: true, trashOriginals: false)) {
            XCTAssertEqual($0 as? TagError, .toolFailed("Error: exiftool did not start"))
        }
        XCTAssertEqual(h.log.entries, ["open Shoot 1", "flock 7", "readFolder", "close 7"])
    }

    // The existing path of a folder that could not be read: the scan's own
    // error, in the words that a front end shows already.
    func testAFolderThatCannotBeOpenedGivesTheErrorOfTheScanAndChangesNothing() throws {
        let missing = shoot.appendingPathComponent("No such folder")
        var scanError: Error?
        XCTAssertThrowsError(try FolderScanner(tag: h.tag, backups: h.backups).snapshot(of: missing)) { scanError = $0 }
        XCTAssertThrowsError(try realJob().run(folder: missing, factor: factor, convert: true, trashOriginals: false)) {
            XCTAssertEqual($0.localizedDescription, scanError?.localizedDescription)
        }
        XCTAssertEqual(h.log.entries, [])
    }

    // An open that fails for a folder that the scan can still read: the run
    // does not go on without having asked for the lock.
    func testAFolderThatCannotBeOpenedStopsTheRunAlsoWhenTheScanPasses() throws {
        try makeShoot()
        system.openCode = EMFILE
        XCTAssertThrowsError(try job().run(folder: shoot, factor: factor, convert: true, trashOriginals: false)) {
            XCTAssertEqual(($0 as? POSIXError)?.code, .EMFILE)
        }
        XCTAssertEqual(h.log.entries, ["open Shoot 1", "readFolder"], "a scan, and no write and no converter")
        XCTAssertEqual(try names(), ["A.dng", "X.ARW"])
    }

    func testADryRunTakesNoLock() throws {
        try makeShoot()
        system.lockCode = EWOULDBLOCK
        let plan = try job().plan(folder: shoot, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(plan.summary.set, 2)
        XCTAssertEqual(system.calls, [], "a dry run changes no file, so it asks for no lock")
        // And so it has no word about a volume with no lock.
        system.lockCode = ENOTSUP
        XCTAssertEqual(try job().plan(folder: shoot, factor: factor, convert: true, trashOriginals: false)
            .summary.notes, [])
        XCTAssertEqual(system.calls, [])
    }

    // MARK: The system's lock

    /// A job on the harness's fakes and on the system's lock: the default.
    func realJob() -> DesqueezeJob { h.job() }

    func testWithTheSystemsLockARunIsRefusedWhileTheFolderIsLockedAndPassesAfterTheRelease() throws {
        try makeShoot()
        guard case .held(let other) = FolderLock.system.take(shoot) else { return XCTFail("the take") }
        XCTAssertThrowsError(try realJob().run(folder: shoot, factor: factor, convert: true, trashOriginals: false)) {
            XCTAssertTrue($0 is FolderLock.Busy, "\($0)")
        }
        XCTAssertEqual(h.log.entries, [], "no call to exiftool and none to a converter")
        // A scan and a dry run are allowed while a run works.
        XCTAssertEqual(try FolderScanner(tag: h.tag, backups: h.backups).snapshot(of: shoot).dngs.count, 1)
        XCTAssertEqual(try realJob().plan(folder: shoot,
                                          factor: factor, convert: true, trashOriginals: false).summary.set, 2)
        h.log.entries = []

        other.release()
        XCTAssertEqual(try realJob().run(folder: shoot, factor: factor, convert: false, trashOriginals: false).set, 1)
    }

    func testTwoRunsInARowBothPass() throws {
        try makeShoot()
        let first = try realJob().run(folder: shoot, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual(first.set, 1)
        // The first run released the lock. What a real scan reads now:
        h.tag.rows = [TagRow(fileName: "A.dng", scale: Scale(horizontal: 1.5, vertical: 1), originalRawFileName: nil)]
        let second = try realJob().run(folder: shoot, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual(second.skipped, 1)
        // And after a run that threw.
        h.tag.readFolderError = TagError.toolFailed("Error: exiftool did not start")
        XCTAssertThrowsError(try realJob().run(folder: shoot, factor: factor, convert: false, trashOriginals: false))
        h.tag.readFolderError = nil
        XCTAssertEqual(try realJob().run(folder: shoot,
                                         factor: factor, convert: false, trashOriginals: false).skipped, 1)
    }
}
