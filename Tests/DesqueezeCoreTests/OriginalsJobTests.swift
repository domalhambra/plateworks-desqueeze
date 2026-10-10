import XCTest
@testable import DesqueezeCore

/// The fifth step of a run on fakes (design 14.2): which ARW reaches the
/// trash function, when, and what the summary says. No disk, and no tool.
final class OriginalsJobTests: XCTestCase {
    let factor = SqueezeFactor(1.5)!
    var h: JobHarness!

    override func setUp() { h = JobHarness() }

    /// The ARW files that reached the trash function, in order. The work
    /// file of a failed conversion goes there too, and is not one of them.
    var originalsGiven: [String] {
        h.backups.filesGiven.map(\.lastPathComponent).filter { $0.lowercased().hasSuffix(".arw") }
    }

    /// The log with no read of the facts: only the calls that touch a file,
    /// or ask the disk about one.
    var calls: [String] { h.log.entries.filter { !$0.hasPrefix("facts ") } }

    func run(_ snapshot: FolderSnapshot, trashOriginals: Bool = true, convert: Bool = true, remove: Bool = false,
             withConverter: Bool = true, withDnglab: Bool = false, cancel: CancelFlag = CancelFlag(),
             progress: (RunProgress) -> Void = { _ in }) -> RunSummary {
        h.job(withConverter: withConverter, withDnglab: withDnglab)
            .run(snapshot, factor: factor, convert: convert, trashOriginals: trashOriginals, remove: remove,
                 cancel: cancel, progress: progress)
    }

    // MARK: The option is off

    // The first break to try: the option is treated as on when it is off.
    func testWithTheOptionOffAConversionThatPassedMovesNoARWAndAsksTheDiskNothing() {
        let summary = run(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"]), trashOriginals: false)
        XCTAssertEqual(summary.converted, 2)
        XCTAssertEqual(originalsGiven, [])
        XCTAssertEqual(h.backups.filesGiven, [], "nothing reaches the trash function")
        XCTAssertEqual(calls.filter { $0.hasPrefix("record ") || $0.hasPrefix("check ") }, [],
                       "no record of an ARW, and no check of a DNG")
        XCTAssertFalse(summary.trashOriginals)
        XCTAssertEqual(summary.originalsInTrash, 0)
        XCTAssertNil(summary.originalsLine)
        XCTAssertEqual(summary.notes, [])
    }

    func testWithTheOptionOffAFailedConversionMovesNoARW() {
        h.converter.failWithPartial = ["X.ARW"]
        let summary = run(h.snapshot(pending: ["X.ARW", "Y.ARW"]), trashOriginals: false)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(originalsGiven, [])
        // The work file of the failed conversion still goes, as before.
        XCTAssertEqual(h.backups.filesGiven.map(\.lastPathComponent), [".X.desqueeze-work.dng"])
    }

    func testWithTheOptionOffACancelledRunMovesNoARW() {
        let flag = CancelFlag()
        h.tag.onWrite = { flag.cancel() }
        let summary = run(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW"]), trashOriginals: false,
                          cancel: flag)
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(h.backups.filesGiven, [])
    }

    func testWithTheOptionOffABlockedDNGMovesNoARW() {
        h.backups.existing = ["X.dng"]
        let summary = run(h.snapshot(pending: ["X.ARW"]), trashOriginals: false)
        XCTAssertEqual(summary.blocked, 1)
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(summary.notes.map(\.kind), [.blockedByBackup])
    }

    func testWithTheOptionOffNoStepIsCountedForAnOriginal() {
        var totals: [Int] = []
        _ = run(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW"]), trashOriginals: false) {
            totals.append($0.total)
        }
        XCTAssertEqual(totals, [3, 3, 3], "the conversion, and two tags")
    }

    // MARK: The option is on, and every line holds

    func testAnARWThatThisRunConvertedGoesToTheTrashAfterItsDNGIsChecked() {
        let summary = run(h.snapshot(pending: ["X.ARW"]))
        XCTAssertEqual(calls, [
            // Line 4: the record, before the converter starts.
            "record X.ARW", "convert X.ARW",
            "write 1.5 1 X.dng", "read X.dng", "trash X.dng",
            // Line 5, then line 4 again, then the move.
            "record X.dng", "check X.dng", "record X.ARW", "trashFile X.ARW",
        ])
        XCTAssertEqual(h.backups.filesGiven, [h.folder.appendingPathComponent("X.ARW")])
        XCTAssertTrue(summary.trashOriginals)
        XCTAssertEqual(summary.originalsInTrash, 1)
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 1 of 1.")
        XCTAssertEqual(summary.notes, [])
        XCTAssertEqual(summary.failed, 0)
        XCTAssertFalse(summary.cancelled)
        XCTAssertFalse(summary.needsAttention)
    }

    // The order: no ARW moves before every tag step has ended.
    func testNoARWMovesBeforeTheTagOfTheLastDNG() throws {
        let summary = run(h.snapshot(dngs: [h.dng("A.dng"), h.dng("B.dng")], pending: ["X.ARW", "Y.ARW"]))
        let firstMove = try XCTUnwrap(calls.firstIndex { $0.hasPrefix("trashFile ") })
        let lastTagCall = try XCTUnwrap(calls.lastIndex {
            $0.hasPrefix("write ") || $0.hasPrefix("read ") || $0.hasPrefix("trash ")
        })
        XCTAssertLessThan(lastTagCall, firstMove)
        XCTAssertEqual(calls.suffix(8), [
            "record X.dng", "check X.dng", "record X.ARW", "trashFile X.ARW",
            "record Y.dng", "check Y.dng", "record Y.ARW", "trashFile Y.ARW",
        ])
        XCTAssertEqual(summary.originalsInTrash, 2)
        XCTAssertEqual(summary.set, 4)
    }

    // Only an ARW that this run converted can go. An ARW whose DNG an
    // earlier run made is not pending, and the run never names it.
    func testOnlyTheARWFilesOfThisRunsConversionsReachTheTrash() {
        _ = run(h.snapshot(dngs: [h.dng("old.dng", at: 1.5)], pending: ["X.ARW"]))
        XCTAssertEqual(originalsGiven, ["X.ARW"])
    }

    func testAConversionByAdobeDNGConverterMovesItsOriginalToo() {
        let summary = run(h.snapshot(pending: ["X.ARW"]), withConverter: true, withDnglab: false)
        XCTAssertEqual([summary.convertedByDnglab, summary.convertedByAdobe], [0, 1])
        XCTAssertEqual(originalsGiven, ["X.ARW"])
    }

    func testAConversionByDnglabWithAFullMatchMovesItsOriginal() {
        h.facts.facts = ["X.ARW": .adapted]
        let summary = run(h.snapshot(pending: ["X.ARW"]), withDnglab: true)
        XCTAssertEqual([summary.convertedByDnglab, summary.convertedByAdobe], [1, 0])
        XCTAssertEqual(originalsGiven, ["X.ARW"])
    }

    // dnglab failed, Adobe DNG Converter converted: one record, before the
    // first converter, and the original moves.
    func testAnARWThatTookTwoConvertersIsRecordedOnceBeforeTheFirst() {
        h.facts.facts = ["X.ARW": .adapted]
        h.dnglab.fail = ["X.ARW"]
        let summary = run(h.snapshot(pending: ["X.ARW"]), withDnglab: true)
        XCTAssertEqual(Array(calls.prefix(3)), ["record X.ARW", "dnglab X.ARW", "convert X.ARW"])
        XCTAssertEqual(summary.convertedByAdobe, 1)
        XCTAssertEqual(originalsGiven, ["X.ARW"])
    }

    // At factor 1 the new DNG is at the value already: the tag step is a
    // skip, and line 3 holds.
    func testADNGThatWasAtTheFactorAlreadyLetsItsOriginalMove() {
        let summary = h.job().run(h.snapshot(pending: ["X.ARW"]), factor: .noStretch, convert: true,
                                  trashOriginals: true)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(originalsGiven, ["X.ARW"])
    }

    // The tag was set and read back. Only the backup stayed.
    func testADNGWhoseBackupTheTrashRefusedIsStillComplete() {
        h.backups.trashError = NamedError(text: "The volume has no Trash.")
        let summary = run(h.snapshot(pending: ["X.ARW"]))
        XCTAssertEqual(summary.notes.map(\.kind), [.backupKept])
        XCTAssertEqual(originalsGiven, ["X.ARW"])
        XCTAssertEqual(summary.originalsInTrash, 1)
    }

    // MARK: Each reason to keep an original

    func testLine1AnARWWhoseConversionFailedStaysAndGetsNoSecondNote() {
        h.converter.fail = ["X.ARW"]
        let summary = run(h.snapshot(pending: ["X.ARW", "Y.ARW"]))
        XCTAssertEqual(originalsGiven, ["Y.ARW"])
        XCTAssertEqual(summary.notes, [.notConverted("X.ARW", detail: "made no DNG")],
                       "its note says enough: no originalKept note")
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 1 of 1.")
        XCTAssertFalse(calls.contains("record X.dng"))
    }

    func testLine2ADNGWithNoFullMatchKeepsItsOriginalAndCostsNoRead() {
        h.facts.facts = ["full.ARW": .adapted, "lens.ARW": .lens]
        let summary = run(h.snapshot(pending: ["full.ARW", "lens.ARW"]), withConverter: false, withDnglab: true)
        XCTAssertEqual(originalsGiven, ["full.ARW"])
        XCTAssertEqual(summary.notes, [
            .convertedUnmatched("lens.dng", rule: .noLensCorrection, facts: .lens),
            FileNote(name: "lens.ARW", kind: .originalKept,
                     message: "The original stays, because its DNG has no full match.", detail: nil),
        ])
        XCTAssertFalse(calls.contains("check lens.dng"))
        XCTAssertEqual(calls.filter { $0 == "record lens.ARW" }.count, 1, "only the record before the conversion")
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 1 of 2.")
        XCTAssertFalse(summary.needsAttention)
        XCTAssertEqual(summary.failed, 0)
    }

    func testLine3ADNGWhoseWriteFailedKeepsItsOriginal() {
        h.tag.failWrites = ["X.dng"]
        let summary = run(h.snapshot(pending: ["X.ARW"]))
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(summary.notes.map(\.kind), [.failed, .originalKept])
        XCTAssertEqual(summary.notes.last, FileNote(
            name: "X.ARW", kind: .originalKept,
            message: "The original stays, because its DNG is not complete.", detail: nil))
        XCTAssertFalse(calls.contains("check X.dng"))
        XCTAssertEqual(summary.originalsInTrash, 0)
    }

    func testLine3ADNGWhoseCheckFailedKeepsItsOriginal() {
        h.tag.wrongReadBack = ["X.dng"]
        let summary = run(h.snapshot(pending: ["X.ARW"]))
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(summary.notes.last?.message, "The original stays, because its DNG is not complete.")
    }

    func testLine3ABlockedDNGKeepsItsOriginal() {
        h.backups.existing = ["X.dng"]
        let summary = run(h.snapshot(pending: ["X.ARW"]))
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(summary.notes.map(\.kind), [.blockedByBackup, .originalKept])
        XCTAssertEqual(summary.notes.last?.message, "The original stays, because its DNG is not complete.")
    }

    // The second break to try: line 4 is skipped.
    func testLine4AnARWThatChangedDuringTheRunStays() {
        // Each: the record before the conversion, then the one before the move.
        let changes: [[FileRecord?]] = [
            [FakeFiles.file(size: 100), FakeFiles.file(size: 101)],
            [FakeFiles.file(modified: 1_000), FakeFiles.file(modified: 1_001)],
            [FakeFiles.file(nanoseconds: 0), FakeFiles.file(nanoseconds: 1)],
            [FakeFiles.file(number: 7), FakeFiles.file(number: 8)],
            [FakeFiles.file(), nil],
            [nil, FakeFiles.file()],
        ]
        for records in changes {
            h = JobHarness()
            h.files.records["X.ARW"] = records
            let summary = run(h.snapshot(pending: ["X.ARW"]))
            XCTAssertEqual(h.backups.filesGiven, [], "\(records)")
            XCTAssertEqual(summary.notes, [FileNote(
                name: "X.ARW", kind: .originalKept, message: "The original changed during the run, so it stays.",
                detail: nil)], "\(records)")
            XCTAssertEqual(summary.originalsInTrash, 0)
            XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 0 of 1.")
        }
    }

    func testLine4ALinkOrAFolderAtTheNameOfTheARWNeverGoes() {
        let cases: [[FileRecord?]] = [[FakeFiles.file(), FakeFiles.notAFile],
                                      [FakeFiles.notAFile, FakeFiles.notAFile]]
        for records in cases {
            h = JobHarness()
            h.files.records["X.ARW"] = records
            let summary = run(h.snapshot(pending: ["X.ARW"]))
            XCTAssertEqual(h.backups.filesGiven, [])
            XCTAssertEqual(summary.notes, [FileNote(
                name: "X.ARW", kind: .originalKept, message: "The original is not a regular file, so it stays.",
                detail: nil)])
        }
    }

    func testLine5ADNGThatIsNotARegularFileWithBytesKeepsItsOriginal() {
        let cases: [(FileRecord?, String)] = [(nil, "X.dng is not a regular file."),
                                              (FakeFiles.notAFile, "X.dng is not a regular file."),
                                              (FakeFiles.file(size: 0), "X.dng has no bytes.")]
        for (record, detail) in cases {
            h = JobHarness()
            h.files.records["X.dng"] = [record]
            let summary = run(h.snapshot(pending: ["X.ARW"]))
            XCTAssertEqual(h.backups.filesGiven, [], detail)
            XCTAssertEqual(summary.notes, [FileNote(
                name: "X.ARW", kind: .originalKept,
                message: "The original stays, because its DNG could not be checked.", detail: detail)])
            XCTAssertFalse(calls.contains("check X.dng"), "exiftool is not asked")
        }
    }

    func testLine5AReadOfTheDNGThatFailsKeepsItsOriginalWithExiftoolsWords() {
        h.tag.failOriginalChecks = ["X.dng"]
        let summary = run(h.snapshot(pending: ["X.ARW"]))
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(summary.notes, [FileNote(
            name: "X.ARW", kind: .originalKept,
            message: "The original stays, because its DNG could not be checked.", detail: "Error: File not found")])
    }

    func testLine5ADNGThatNamesAnotherARWOrHasAnotherScaleKeepsItsOriginal() {
        let atFactor = Scale(horizontal: 1.5, vertical: 1)
        for (tags, detail) in [
            (OriginalCheckTags(originalRawFileName: "other.ARW", scale: atFactor),
             "The OriginalRawFileName of X.dng is other.ARW, not X.ARW."),
            (OriginalCheckTags(originalRawFileName: nil, scale: atFactor), "X.dng has no OriginalRawFileName."),
            (OriginalCheckTags(originalRawFileName: "X.ARW", scale: .noStretch),
             "The DefaultScale of X.dng is 1 1, not 1.5 1."),
            (OriginalCheckTags(originalRawFileName: "X.ARW", scale: nil), "X.dng has no DefaultScale."),
        ] {
            h = JobHarness()
            h.tag.originalCheck["X.dng"] = tags
            let summary = run(h.snapshot(pending: ["X.ARW"]))
            XCTAssertEqual(h.backups.filesGiven, [], detail)
            XCTAssertEqual(summary.notes.map(\.detail), [detail])
            XCTAssertEqual(summary.notes.map(\.kind), [.originalKept])
            // After a failed check of the DNG, the ARW is not read again.
            XCTAssertEqual(calls.filter { $0 == "record X.ARW" }.count, 1, detail)
        }
    }

    // The Trash refuses: the ARW stays with the note. One try, and no
    // other way.
    func testATrashThatRefusesKeepsTheARWWithTheSystemsWordsAndTriesNothingElse() {
        h.backups.trashFileError = NamedError(text: "The volume has no Trash.")
        let summary = run(h.snapshot(pending: ["X.ARW", "Y.ARW"]))
        XCTAssertEqual(calls.filter { $0.hasPrefix("trashFile ") }, ["trashFile X.ARW", "trashFile Y.ARW"],
                       "one try for each ARW")
        XCTAssertEqual(summary.originalsInTrash, 0)
        XCTAssertEqual(summary.notes, [
            FileNote(name: "X.ARW", kind: .originalKept,
                     message: "The original could not go to the Trash, so it stays.",
                     detail: "The volume has no Trash."),
            FileNote(name: "Y.ARW", kind: .originalKept,
                     message: "The original could not go to the Trash, so it stays.",
                     detail: "The volume has no Trash."),
        ])
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 0 of 2.")
        XCTAssertEqual(summary.failed, 0)
        XCTAssertFalse(summary.needsAttention)
        XCTAssertFalse(summary.cancelled)
    }

    // One ARW stays, and the next one still moves.
    func testAnOriginalThatStaysDoesNotStopTheNextOne() {
        h.files.records["X.ARW"] = [FakeFiles.file(size: 100), FakeFiles.file(size: 99)]
        let summary = run(h.snapshot(pending: ["X.ARW", "Y.ARW"]))
        XCTAssertEqual(originalsGiven, ["Y.ARW"])
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 1 of 2.")
    }

    // MARK: Cancel

    // The third break to try: step 5 runs after a cancel.
    func testACancelBeforeTheFifthStepMovesNoARWAndTheRunIsStopped() {
        let flag = CancelFlag()
        // During the last tag: every tag step ends, and step 5 does not start.
        h.tag.onWrite = { if self.h.log.entries.contains("write 1.5 1 Y.dng") { flag.cancel() } }
        let summary = run(h.snapshot(pending: ["X.ARW", "Y.ARW"]), cancel: flag)
        XCTAssertEqual(summary.set, 2, "the file in work completes")
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertFalse(calls.contains { $0.hasPrefix("check ") })
        XCTAssertTrue(summary.cancelled, "the originals are work left undone")
        XCTAssertEqual(summary.originalsInTrash, 0)
        XCTAssertEqual(summary.notes, [], "an ARW that step 5 did not reach gets no note")
        XCTAssertEqual(summary.countsLine, "2 converted · 2 set · 0 skipped · 0 failed · stopped")
    }

    func testACancelDuringAConversionMovesNoARW() {
        let flag = CancelFlag()
        h.converter.onConvert = { flag.cancel() }
        let summary = run(h.snapshot(pending: ["X.ARW", "Y.ARW"]), cancel: flag)
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(h.backups.filesGiven, [])
    }

    func testACancelDuringTheFifthStepLetsTheARWInWorkCompleteAndStartsNoOther() {
        let flag = CancelFlag()
        h.backups.onTrashFile = { flag.cancel() }
        var steps: [String] = []
        let summary = run(h.snapshot(pending: ["X.ARW", "Y.ARW", "Z.ARW"]), cancel: flag) {
            steps.append("\($0.completed)/\($0.total) \($0.name)")
        }
        XCTAssertEqual(originalsGiven, ["X.ARW"])
        XCTAssertFalse(calls.contains("check Y.dng"), "the next ARW does not start")
        XCTAssertEqual(summary.originalsInTrash, 1, "the count is right")
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(summary.notes, [])
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 1 of 3.")
        XCTAssertEqual(steps.last, "7/9 X.ARW")
    }

    // The rule of design 12.1: a cancel during the last file leaves nothing
    // undone, so the run is complete.
    func testACancelDuringTheLastARWOfTheFifthStepLeavesNothingUndone() {
        let flag = CancelFlag()
        h.backups.onTrashFile = { if self.h.log.entries.contains("trashFile Y.ARW") { flag.cancel() } }
        let summary = run(h.snapshot(pending: ["X.ARW", "Y.ARW"]), cancel: flag)
        XCTAssertEqual(originalsGiven, ["X.ARW", "Y.ARW"])
        XCTAssertFalse(summary.cancelled)
        XCTAssertEqual(summary.originalsInTrash, 2)
    }

    // With no original to handle, a cancel during the last tag leaves
    // nothing undone, as before.
    func testACancelDuringTheLastTagWithNoOriginalToMoveIsACompleteRun() {
        let flag = CancelFlag()
        h.tag.onWrite = { flag.cancel() }
        let summary = run(h.snapshot(dngs: [h.dng("A.dng")]), cancel: flag)
        XCTAssertFalse(summary.cancelled)
    }

    // MARK: Remove, no conversion, a read-only folder

    func testRemoveMovesNothingWhateverItIsGiven() {
        let state = h.snapshot(dngs: [h.dng("A.dng", at: 1.5)], pending: ["X.ARW"])
        let summary = run(state, trashOriginals: true, convert: true, remove: true)
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(calls, ["write 1 1 A.dng", "read A.dng", "trash A.dng"])
        XCTAssertFalse(summary.trashOriginals, "Remove has no fifth step")
        XCTAssertNil(summary.originalsLine)
        XCTAssertEqual(summary.originalsInTrash, 0)
    }

    func testARunThatConvertsNothingMovesNothing() {
        let summary = run(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW"]), convert: false)
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 0 of 0.")
        XCTAssertEqual(summary.unconvertedARWs, 1)
    }

    func testWithNoConverterNothingMoves() {
        let summary = run(h.snapshot(pending: ["X.ARW"]), withConverter: false)
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(summary.originalsInTrash, 0)
    }

    func testAReadOnlyFolderMovesNothing() {
        let summary = run(h.snapshot(pending: ["X.ARW"], writable: false))
        XCTAssertEqual(h.log.entries, [])
        XCTAssertEqual(summary.notes.map(\.kind), [.folderReadOnly])
        XCTAssertEqual(summary.originalsInTrash, 0)
    }

    // MARK: Progress (design 14.3)

    func testProgressHasOneMoreStepForEachARWThatTheFifthStepHandles() {
        var steps: [String] = []
        _ = run(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"])) {
            steps.append("\($0.completed)/\($0.total) \($0.name)")
        }
        XCTAssertEqual(steps, [
            "1/7 X.ARW", "2/7 Y.ARW", "3/7 A.dng", "4/7 X.dng", "5/7 Y.dng", "6/7 X.ARW", "7/7 Y.ARW",
        ])
    }

    // An ARW that stays is handled too: it has its step.
    func testAnOriginalThatStaysHasItsStep() {
        h.tag.failWrites = ["X.dng"]
        var steps: [String] = []
        _ = run(h.snapshot(pending: ["X.ARW"])) { steps.append("\($0.completed)/\($0.total) \($0.name)") }
        XCTAssertEqual(steps, ["1/3 X.ARW", "2/3 X.dng", "3/3 X.ARW"])
    }

    // A failed conversion has no tag step and no step for its original.
    func testAFailedConversionTakesTwoStepsOffTheTotal() {
        h.converter.fail = ["X.ARW"]
        var steps: [String] = []
        _ = run(h.snapshot(pending: ["X.ARW", "Y.ARW"])) { steps.append("\($0.completed)/\($0.total) \($0.name)") }
        XCTAssertEqual(steps, ["1/4 X.ARW", "2/4 Y.ARW", "3/4 Y.dng", "4/4 Y.ARW"])
    }

    // MARK: From a folder: the fifth step is inside the lock (design 13.9)

    func testTheFifthStepRunsWhileTheRunHoldsTheLockOfTheFolder() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        try Data("raw".utf8).write(to: folder.appendingPathComponent("X.ARW"))
        let backups = h.backups
        var answerDuringTheMove: String?
        backups.onTrashFile = {
            // A second run in the folder, at the moment of the move.
            switch FolderLock.system.take(folder) {
            case .busy: answerDuringTheMove = "busy"
            case .held(let held):
                held.release()
                answerDuringTheMove = "held"
            default: answerDuringTheMove = "other"
            }
        }
        let summary = try h.job().run(folder: folder, factor: factor, convert: true, trashOriginals: true)
        XCTAssertEqual(summary.originalsInTrash, 1)
        XCTAssertEqual(answerDuringTheMove, "busy", "the lock is held while an original moves")
        guard case .held(let after) = FolderLock.system.take(folder) else {
            return XCTFail("the lock is free after the run")
        }
        after.release()
    }

    // The public entry points pass the option on, and neither has a default
    // for it: a call that leaves it out does not compile.
    func testARunAndAPlanFromAFolderPassTheOptionOn() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        try Data("raw".utf8).write(to: folder.appendingPathComponent("X.ARW"))

        let planOff = try h.job().plan(folder: folder, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(planOff.steps.map(\.action), [.convert, .write])
        let planOn = try h.job().plan(folder: folder, factor: factor, convert: true, trashOriginals: true)
        XCTAssertEqual(planOn.steps.map(\.action), [.convert, .write, .trashOriginal])
        XCTAssertEqual(h.backups.filesGiven, [], "a plan moves nothing")

        let off = try h.job().run(folder: folder, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(off.converted, 1)
        XCTAssertEqual(h.backups.filesGiven, [])
    }
}
