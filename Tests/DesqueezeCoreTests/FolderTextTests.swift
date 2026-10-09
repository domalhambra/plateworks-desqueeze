import XCTest
@testable import DesqueezeCore

/// The words and the counts that every front end shows about a folder
/// (design, sections 5 and 7). Each test holds the exact text.
final class FolderTextTests: XCTestCase {
    let h = JobHarness()

    func dngs(_ count: Int) -> [DNGFile] { (0..<count).map { h.dng("d\($0).dng") } }
    func arws(_ count: Int) -> [String] { (0..<count).map { "a\($0).ARW" } }
    func orphans(_ count: Int) -> [String] { (1...count).map { "lost\($0).dng_original" } }

    // MARK: The counts line

    func testTheCountsLineIsTheLineOfTheDesign() {
        let snapshot = h.snapshot(dngs: dngs(216), pending: arws(12))
        XCTAssertEqual(snapshot.countsLine(converterAvailable: true), "216 DNG · 12 ARW to convert")
    }

    func testTheCountsLineHasNoARWPartWhenNoARWIsPending() {
        XCTAssertEqual(h.snapshot(dngs: dngs(3)).countsLine(converterAvailable: true), "3 DNG")
        XCTAssertEqual(h.snapshot(dngs: dngs(3)).countsLine(converterAvailable: false), "3 DNG")
    }

    func testTheCountsLineSaysWhyTheARWFilesCannotConvert() {
        let snapshot = h.snapshot(dngs: dngs(2), pending: arws(12))
        XCTAssertEqual(snapshot.countsLine(converterAvailable: false),
                       "2 DNG · 12 ARW cannot be converted: Adobe DNG Converter is not installed")
    }

    func testAFolderWithOnlyARWFilesCountsZeroDNG() {
        XCTAssertEqual(h.snapshot(pending: arws(1)).countsLine(converterAvailable: true), "0 DNG · 1 ARW to convert")
    }

    func testAnEmptyFolderGetsTheSentenceOfTheDesign() {
        XCTAssertEqual(h.snapshot().countsLine(converterAvailable: true), "No DNG or ARW files in this folder.")
        XCTAssertEqual(h.snapshot().countsLine(converterAvailable: false), FolderText.noPhotos)
    }

    // The orphan is the only thing in the folder. The "empty" sentence would
    // hide it, so the counts show.
    func testAFolderWithOnlyAnOrphanBackupIsNotEmpty() {
        XCTAssertEqual(h.snapshot(orphans: orphans(1)).countsLine(converterAvailable: true), "0 DNG")
    }

    // MARK: The run count and the run button

    func testTheRunCountIsTheDNGFilesPlusThePendingARWFilesThatCanConvert() {
        let snapshot = h.snapshot(dngs: dngs(216), pending: arws(12), orphans: orphans(2))
        XCTAssertEqual(snapshot.runCount(converterAvailable: true), 228)
        XCTAssertEqual(snapshot.runCount(converterAvailable: false), 216)
    }

    func testTheRunLabelHasThreeForms() {
        XCTAssertEqual(h.snapshot().runLabel(converterAvailable: true), "Desqueeze")
        XCTAssertEqual(h.snapshot(dngs: dngs(1)).runLabel(converterAvailable: true), "Desqueeze 1 photo")
        XCTAssertEqual(h.snapshot(dngs: dngs(1), pending: arws(1)).runLabel(converterAvailable: true),
                       "Desqueeze 2 photos")
        XCTAssertEqual(h.snapshot(dngs: dngs(216), pending: arws(12)).runLabel(converterAvailable: true),
                       "Desqueeze 228 photos")
    }

    func testTheRunLabelLeavesOutTheARWFilesThatCannotConvert() {
        XCTAssertEqual(h.snapshot(dngs: dngs(1), pending: arws(12)).runLabel(converterAvailable: false),
                       "Desqueeze 1 photo")
        XCTAssertEqual(h.snapshot(pending: arws(12)).runLabel(converterAvailable: false), "Desqueeze")
    }

    // A window with no folder has no snapshot, and still has a button.
    func testTheRunLabelOfACount() {
        XCTAssertEqual(FolderText.runLabel(count: 0), "Desqueeze")
        XCTAssertEqual(FolderText.runLabel(count: 1), "Desqueeze 1 photo")
        XCTAssertEqual(FolderText.runLabel(count: 2), "Desqueeze 2 photos")
    }

    // MARK: The folder messages

    func testAFolderWithNothingToSayHasNoMessage() {
        XCTAssertEqual(h.snapshot(dngs: dngs(2), pending: arws(1)).messages, [])
    }

    func testAReadOnlyFolderGetsTheSentenceOfTheWindow() {
        XCTAssertEqual(h.snapshot(dngs: dngs(1), writable: false).messages,
                       ["This folder is read-only. Desqueeze cannot change its files."])
    }

    func testEachOrphanBackupIsNamedWithTheNameToRenameItTo() {
        XCTAssertEqual(h.snapshot(orphans: ["lost.dng_original", "IMG 2.DNG_original"]).messages, [
            "lost.dng_original: A backup with no DNG beside it. Rename it to lost.dng to get the photo back.",
            "IMG 2.DNG_original: A backup with no DNG beside it. Rename it to IMG 2.DNG to get the photo back.",
        ])
    }

    // The folder line and the note of a run are one sentence, made once.
    func testTheFolderLineOfAnOrphanIsTheLineOfTheNoteOfARun() {
        let snapshot = h.snapshot(orphans: ["lost.dng_original"])
        let summary = h.job().run(snapshot, factor: SqueezeFactor(1.5)!, convert: true)
        XCTAssertEqual(snapshot.messages, summary.notes.map(\.line))
        XCTAssertEqual(summary.notes.map(\.line), [
            "lost.dng_original: A backup with no DNG beside it. Rename it to lost.dng to get the photo back.",
        ])
    }

    func testFiveOrphanBackupsAreAllNamed() {
        let messages = h.snapshot(orphans: orphans(5)).messages
        XCTAssertEqual(messages.count, 5)
        XCTAssertEqual(messages.last, FileNote.orphanBackup(named: "lost5.dng_original").line)
    }

    func testAfterFiveOrphanBackupsTheOthersAreACount() {
        let six = h.snapshot(orphans: orphans(6)).messages
        XCTAssertEqual(Array(six.dropFirst(4)), [FileNote.orphanBackup(named: "lost5.dng_original").line, "and 1 more"])
        XCTAssertEqual(six.count, 6)

        let seven = h.snapshot(orphans: orphans(7)).messages
        XCTAssertEqual(Array(seven.prefix(5)), orphans(5).map { FileNote.orphanBackup(named: $0).line })
        XCTAssertEqual(Array(seven.dropFirst(5)), ["and 2 more"])
    }

    func testTheReadOnlyMessageIsBeforeTheOrphanBackups() {
        XCTAssertEqual(h.snapshot(orphans: orphans(6), writable: false).messages.first, FolderText.readOnly)
        XCTAssertEqual(h.snapshot(orphans: orphans(6), writable: false).messages.count, 7)
    }

    // MARK: A folder that could not be read

    // The window and the command line tool both say this sentence (design,
    // section 8).
    func testTheSentenceForAFolderThatCouldNotBeRead() {
        XCTAssertEqual(FolderText.unreadable, "This folder could not be read.")
    }

    // The command line tool names the path after the sentence.
    func testTheSentenceWithThePathEndsWithThePathAndHasNoPeriod() {
        XCTAssertEqual(FolderText.unreadable(path: "/Volumes/Card/Shoot 1"),
                       "This folder could not be read: /Volumes/Card/Shoot 1")
    }

    // The command line tool prints a list, so it asks for every name.
    func testWithNoLimitEveryOrphanBackupIsNamed() {
        let messages = FolderText.messages(isWritable: true, orphanBackups: orphans(7), namedOrphanLimit: nil)
        XCTAssertEqual(messages, orphans(7).map { FileNote.orphanBackup(named: $0).line })
    }
}
