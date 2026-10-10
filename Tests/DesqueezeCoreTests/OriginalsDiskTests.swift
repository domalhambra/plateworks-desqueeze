import XCTest
@testable import DesqueezeCore

/// The fifth step of a run on the real disk (design 14.2): real files in a
/// temporary folder, the real `FileRecord.read`, and the real `FileBackups`
/// with an injected trash function. The converter and the tag are fakes, so
/// these tests need no tool and no fixture, and they never skip.
///
/// The tests of `OriginalsJobTests` give the job paths that do not exist.
/// A delete of such a path does nothing, so no test there can see one. Here
/// the ARW is a real file: a delete, or a move by any way but the injected
/// function, changes what the folder holds.
final class OriginalsDiskTests: XCTestCase {
    let factor = SqueezeFactor(1.5)!
    /// What stands for the only copy of a photo.
    let arwBytes = Data("the only copy of a photo".utf8)
    var folder: URL!

    override func setUpWithError() throws {
        folder = try makeTemporaryFolder()
    }

    override func tearDown() {
        if let folder { removeTemporaryFolder(folder) }
    }

    /// A converter that makes a real DNG file beside the ARW, and starts no
    /// program. It writes `<base>.dng` with bytes, as line 5 asks.
    struct WritingConverter: RawConverter {
        func convert(_ arw: URL, facts: ARWFacts) throws -> Conversion {
            let dng = ConverterOutput.url(for: arw)
            try Data("the DNG of \(arw.lastPathComponent)".utf8).write(to: dng)
            return Conversion(dng: dng, unmatched: nil)
        }
    }

    /// Counts the reads of one file name, from any thread.
    final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        /// The number of this read: 1 for the first.
        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }
    }

    /// The names that a trash function got, from any thread.
    final class Names: @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return names
        }

        func add(_ name: String) {
            lock.lock()
            names.append(name)
            lock.unlock()
        }
    }

    func names(in directory: URL? = nil) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: (directory ?? folder).path).sorted()
    }

    /// A folder that stands for the Trash, beside the photo folder, and
    /// backups that move each file into it. Nothing is removed.
    func makeTrash() throws -> (folder: URL, backups: FileBackups) {
        let trash = folder.deletingLastPathComponent().appendingPathComponent("Test trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return (trash, try FileBackups.fromEnvironment([FileBackups.testFolderVariable: trash.path]).backups)
    }

    /// The job on the real disk, with the fake converter and the fake tag.
    ///
    /// - Parameter afterARead: called after each read of `X.dng`, with the
    ///   number of that read: 1 is the record after the conversion, 2 the
    ///   check before the tag step, 3 the record after a tag step that
    ///   wrote, 4 line 6 at the fifth step, 5 line 5, and 6 line 6 again,
    ///   after the exiftool read of line 5.
    func job(backups: FileBackups, afterARead: @escaping @Sendable (Int) -> Void = { _ in }) -> DesqueezeJob {
        let log = CallLog()
        let reads = Reads()
        return DesqueezeJob(
            tag: FakeTag(log: log, backups: FakeBackups(log: log)),
            converters: RawConverters(dnglab: nil, adobe: WritingConverter(), facts: FakeFacts(log: log)),
            backups: backups,
            fileRecord: { path in
                let record = FileRecord.read(atPath: path)
                if URL(fileURLWithPath: path).lastPathComponent == "X.dng" { afterARead(reads.next()) }
                return record
            })
    }

    /// Puts another file at `X.dng`, as an outside rename does: the DNG of
    /// another photo, which a program moved over the run's own DNG.
    func replaceTheDNG() {
        let other = folder.appendingPathComponent("from another shoot.tmp")
        try? Data("the DNG of another X.ARW".utf8).write(to: other)
        XCTAssertEqual(rename(other.path, folder.appendingPathComponent("X.dng").path), 0)
    }

    // MARK: No delete after a refusal (design 14.2)

    // The Trash refuses the ARW. The ARW is a real file, so a delete in
    // place of the move, or a second way to move it, would show here: the
    // folder would hold no ARW. Seen to fail with
    // `try? FileManager.default.removeItem(at: original.arw)` in the `catch`
    // of the move.
    func testATrashThatRefusesLeavesTheRealARWInTheFolderWithItsBytes() throws {
        let arw = folder.appendingPathComponent("X.ARW")
        try arwBytes.write(to: arw)
        let before = try XCTUnwrap(FileRecord.read(atPath: arw.path))
        let asked = Names()
        let refusing = FileBackups(trash: { file in
            asked.add(file.lastPathComponent)
            throw NamedError(text: "The volume has no Trash.")
        })

        let summary = try job(backups: refusing).run(folder: folder, factor: factor, convert: true,
                                                     trashOriginals: true)

        XCTAssertEqual(try names(), ["X.ARW", "X.dng"], "the ARW is in the folder")
        XCTAssertEqual(try Data(contentsOf: arw), arwBytes, "with its bytes")
        XCTAssertEqual(FileRecord.read(atPath: arw.path), before, "and it is the same file")
        XCTAssertEqual(summary.notes, [
            // The fake tag makes no backup file, so the Trash refuses that
            // too. The DNG is still complete.
            FileNote(name: "X.dng", kind: .backupKept,
                     message: "Done. The backup stayed beside the file, because the Trash refused it.",
                     detail: "The volume has no Trash."),
            FileNote(name: "X.ARW", kind: .originalKept,
                     message: "The original could not go to the Trash, so it stays.",
                     detail: "The volume has no Trash."),
        ])
        XCTAssertEqual(asked.all, ["X.dng_original", "X.ARW"], "one try for the ARW, and no other file")
        XCTAssertEqual(summary.originalsInTrash, 0)
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 0 of 1.")
    }

    // MARK: Line 6 on the real disk (design 14.2)

    // The control of the two tests below: with no other program in the
    // folder, the real records hold, and the ARW moves with its bytes.
    func testWithNoOtherProgramTheRealARWMovesToTheInjectedTrash() throws {
        try arwBytes.write(to: folder.appendingPathComponent("X.ARW"))
        let (trash, backups) = try makeTrash()

        let summary = try job(backups: backups).run(folder: folder, factor: factor, convert: true,
                                                    trashOriginals: true)

        XCTAssertEqual(try names(), ["X.dng"])
        XCTAssertEqual(try names(in: trash), ["X.ARW"])
        XCTAssertEqual(try Data(contentsOf: trash.appendingPathComponent("X.ARW")), arwBytes)
        XCTAssertEqual(summary.originalsInTrash, 1)
        XCTAssertEqual(summary.notes.map(\.kind), [.backupKept], "the fake tag makes no backup file to move")
    }

    // Another file takes the name of the DNG directly after the first
    // record. The fake check of line 5 passes for it, as the real check
    // passed for the DNG of another `frame.ARW` in the review of 2026-10-10.
    func testARealDNGThatIsReplacedAfterItsConversionKeepsTheARW() throws {
        let arw = folder.appendingPathComponent("X.ARW")
        try arwBytes.write(to: arw)
        let (trash, backups) = try makeTrash()
        let job = job(backups: backups, afterARead: { [self] in if $0 == 1 { replaceTheDNG() } })

        let summary = try job.run(folder: folder, factor: factor, convert: true, trashOriginals: true)

        XCTAssertEqual(try names(), ["X.ARW", "X.dng"], "the ARW stays")
        XCTAssertEqual(try Data(contentsOf: arw), arwBytes)
        XCTAssertEqual(try names(in: trash), [])
        XCTAssertEqual(summary.notes.last, FileNote(
            name: "X.ARW", kind: .originalKept,
            message: "The original stays, because its DNG changed during the run.", detail: nil))
        XCTAssertEqual([summary.set, summary.failed], [1, 0], "the DNG at the name is still tagged")
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 0 of 1.")
    }

    // Another file takes the name directly after the record that follows
    // the tag step.
    func testARealDNGThatIsReplacedAfterItsTagStepKeepsTheARW() throws {
        let arw = folder.appendingPathComponent("X.ARW")
        try arwBytes.write(to: arw)
        let (trash, backups) = try makeTrash()
        let job = job(backups: backups, afterARead: { [self] in if $0 == 3 { replaceTheDNG() } })

        let summary = try job.run(folder: folder, factor: factor, convert: true, trashOriginals: true)

        XCTAssertEqual(try names(), ["X.ARW", "X.dng"], "the ARW stays")
        XCTAssertEqual(try Data(contentsOf: arw), arwBytes)
        XCTAssertEqual(try names(in: trash), [])
        XCTAssertEqual(summary.notes.last, FileNote(
            name: "X.ARW", kind: .originalKept,
            message: "The original stays, because its DNG changed during the run.", detail: nil))
        XCTAssertEqual(summary.originalsInTrash, 0)
    }

    // Another file takes the name at the fifth step: after the read of
    // line 6 (read 4), or after the read of line 5 and before exiftool
    // opens the file (read 5). The check of line 5 passes for it. The read
    // after that check sees that it is not the file that the tag step left.
    func testARealDNGThatIsReplacedAfterTheReadOfLine6KeepsTheARW() throws {
        try assertTheARWStaysWhenTheDNGIsReplaced(afterRead: 4)
    }

    func testARealDNGThatIsReplacedAfterTheReadOfLine5KeepsTheARW() throws {
        try assertTheARWStaysWhenTheDNGIsReplaced(afterRead: 5)
    }

    func assertTheARWStaysWhenTheDNGIsReplaced(afterRead read: Int, line: UInt = #line) throws {
        let arw = folder.appendingPathComponent("X.ARW")
        try arwBytes.write(to: arw)
        let (trash, backups) = try makeTrash()
        let job = job(backups: backups, afterARead: { [self] in if $0 == read { replaceTheDNG() } })

        let summary = try job.run(folder: folder, factor: factor, convert: true, trashOriginals: true)

        XCTAssertEqual(try names(), ["X.ARW", "X.dng"], "the ARW stays", line: line)
        XCTAssertEqual(try Data(contentsOf: arw), arwBytes, line: line)
        XCTAssertEqual(try names(in: trash), [], line: line)
        XCTAssertEqual(summary.notes.last, FileNote(
            name: "X.ARW", kind: .originalKept,
            message: "The original stays, because its DNG changed during the run.", detail: nil), line: line)
        XCTAssertEqual(summary.originalsInTrash, 0, line: line)
    }

    // The ARW is gone at the fifth step: another program moved it away.
    // Nothing reaches the trash function, and the note does not say "it
    // stays" (design 14.3).
    func testARealARWThatIsGoneAtTheFifthStepGetsItsOwnSentence() throws {
        let arw = folder.appendingPathComponent("X.ARW")
        try arwBytes.write(to: arw)
        let (trash, backups) = try makeTrash()
        let elsewhere = folder.deletingLastPathComponent().appendingPathComponent("moved away.ARW")
        // Read 4 is line 6 at the fifth step: the ARW goes before line 4.
        let job = job(backups: backups, afterARead: { if $0 == 4 { _ = rename(arw.path, elsewhere.path) } })

        let summary = try job.run(folder: folder, factor: factor, convert: true, trashOriginals: true)

        XCTAssertEqual(try names(), ["X.dng"])
        XCTAssertEqual(try names(in: trash), [], "the app did not move it")
        XCTAssertEqual(try Data(contentsOf: elsewhere), arwBytes)
        XCTAssertEqual(summary.notes.last, FileNote(
            name: "X.ARW", kind: .originalKept,
            message: "The original was not in the folder at the end of the run. The app did not move it.",
            detail: nil))
        XCTAssertEqual(summary.originalsInTrash, 0)
    }
}
