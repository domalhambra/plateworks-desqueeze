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
            // Line 6: the first record of the DNG, directly after the
            // conversion.
            "record X.dng",
            // Line 6: the first record must hold directly before the tag
            // step. Then the tag step, and the second record directly
            // after it.
            "record X.dng", "write 1.5 1 X.dng", "read X.dng", "trash X.dng", "record X.dng",
            // Line 6, then line 5, then line 6 again, then line 4 again,
            // then the move.
            "record X.dng", "record X.dng", "check X.dng", "record X.dng", "record X.ARW", "trashFile X.ARW",
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
        XCTAssertEqual(calls.suffix(12), [
            "record X.dng", "record X.dng", "check X.dng", "record X.dng", "record X.ARW", "trashFile X.ARW",
            "record Y.dng", "record Y.dng", "check Y.dng", "record Y.dng", "record Y.ARW", "trashFile Y.ARW",
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
            // No record from before the conversion counts as changed.
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

    // "It stays" would be false for an ARW that is not there (design 14.3).
    func testAnARWThatIsGoneAtTheFifthStepGetsItsOwnSentenceAndNothingReachesTheTrash() {
        // Each: the record before the conversion, then the one before the move.
        for records: [FileRecord?] in [[FakeFiles.file(), nil], [nil, nil]] {
            h = JobHarness()
            h.files.records["X.ARW"] = records
            let summary = run(h.snapshot(pending: ["X.ARW"]))
            XCTAssertEqual(h.backups.filesGiven, [], "\(records)")
            XCTAssertEqual(summary.notes, [FileNote(
                name: "X.ARW", kind: .originalKept,
                message: "The original was not in the folder at the end of the run. The app did not move it.",
                detail: nil)], "\(records)")
            XCTAssertEqual(summary.originalsInTrash, 0)
            XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 0 of 1.")
            XCTAssertFalse(summary.needsAttention)
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
            // The four reads of line 6 give the same file. The fifth read
            // is the one of line 5.
            let made = FakeFiles.file()
            h.files.records["X.dng"] = [made, made, made, made, record]
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

    // MARK: Line 6: the DNG is the file that this run made

    /// The note of line 6 (design 14.3).
    let dngChanged = FileNote(name: "X.ARW", kind: .originalKept,
                              message: "The original stays, because its DNG changed during the run.", detail: nil)
    /// The DNG as the conversion made it, and as the tag step left it:
    /// exiftool writes a new file, so every fact differs.
    let made = FakeFiles.file(size: 100, modified: 1_000, nanoseconds: 0, number: 7)
    let tagged = FakeFiles.file(size: 104, modified: 1_002, nanoseconds: 5, number: 8)

    // The reads of the DNG, in order: after the conversion, before the tag
    // step, after a tag step that wrote, then at the fifth step line 6,
    // line 5, and line 6 again. A tag step that skipped has no read after
    // it.

    // The fourth break to try: line 6 is skipped. This is the case of the
    // review of 2026-10-10: another photo's DNG took the name after the
    // conversion, and it would pass line 5.
    func testLine6ADNGThatWasReplacedBetweenItsConversionAndItsTagStepKeepsItsOriginalAndIsStillTagged() {
        for other: FileRecord? in [
            FakeFiles.file(size: 101, modified: 1_000, nanoseconds: 0, number: 7),
            FakeFiles.file(size: 100, modified: 1_001, nanoseconds: 0, number: 7),
            FakeFiles.file(size: 100, modified: 1_000, nanoseconds: 1, number: 7),
            FakeFiles.file(size: 100, modified: 1_000, nanoseconds: 0, number: 9),
        ] {
            h = JobHarness()
            // The other file stays at the name to the end of the run.
            h.files.records["X.dng"] = [made, other]
            let summary = run(h.snapshot(pending: ["X.ARW"]))
            XCTAssertEqual(h.backups.filesGiven, [], "\(String(describing: other))")
            XCTAssertEqual(summary.notes, [dngChanged], "\(String(describing: other))")
            // The DNG is tagged as any DNG in the folder is.
            XCTAssertEqual(calls.filter { $0.hasSuffix(" X.dng") && !$0.hasPrefix("record ") },
                           ["write 1.5 1 X.dng", "read X.dng", "trash X.dng"])
            XCTAssertEqual([summary.converted, summary.set, summary.failed, summary.blocked], [1, 1, 0, 0])
            // Line 6 stands before lines 5 and 4: neither is asked.
            XCTAssertFalse(calls.contains("check X.dng"))
            XCTAssertEqual(calls.filter { $0 == "record X.ARW" }.count, 1, "only the record before the conversion")
            XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 0 of 1.")
            XCTAssertFalse(summary.needsAttention)
        }
    }

    func testLine6ADNGThatWasReplacedBetweenItsTagStepAndTheFifthStepKeepsItsOriginal() {
        for now: FileRecord? in [
            FakeFiles.file(size: 105, modified: 1_002, nanoseconds: 5, number: 8),
            FakeFiles.file(size: 104, modified: 1_003, nanoseconds: 5, number: 8),
            FakeFiles.file(size: 104, modified: 1_002, nanoseconds: 6, number: 8),
            FakeFiles.file(size: 104, modified: 1_002, nanoseconds: 5, number: 9),
            // The file of the first record is back. It is not the file
            // that the tag step left.
            made,
            // Nothing has the name now.
            nil,
        ] {
            h = JobHarness()
            h.files.records["X.dng"] = [made, made, tagged, now]
            let summary = run(h.snapshot(pending: ["X.ARW"]))
            XCTAssertEqual(h.backups.filesGiven, [], "\(String(describing: now))")
            XCTAssertEqual(summary.notes, [dngChanged], "\(String(describing: now))")
            XCTAssertEqual(summary.set, 1)
            XCTAssertFalse(calls.contains("check X.dng"))
            XCTAssertEqual(calls.filter { $0 == "record X.ARW" }.count, 1)
        }
    }

    // A DNG with no record cannot be shown to be the run's own.
    func testLine6ADNGWithNoRecordKeepsItsOriginal() {
        let cases: [[FileRecord?]] = [
            // No record after the conversion.
            [nil, made, tagged, tagged, tagged],
            [nil, nil, tagged, tagged, tagged],
            // No record after the tag step.
            [made, made, nil, tagged, tagged],
            [made, made, nil, nil, nil],
        ]
        for records in cases {
            h = JobHarness()
            h.files.records["X.dng"] = records
            let summary = run(h.snapshot(pending: ["X.ARW"]))
            XCTAssertEqual(h.backups.filesGiven, [], "\(records)")
            XCTAssertEqual(summary.notes, [dngChanged], "\(records)")
        }
    }

    // exiftool writes a new file, so the second record differs from the
    // first. The second one is the one that must hold at the fifth step.
    //
    // A known limit (design 14.7): the run cannot tell exiftool's new file
    // from a file that another program put at the name while the tag step
    // worked. Both are "another file after the tag step". Such a file is
    // taken as the run's own, and only line 5 can still keep the ARW.
    func testLine6ATagStepThatWroteChangesTheRecordAndTheOriginalMoves() {
        h.files.records["X.dng"] = [made, made, tagged]
        let summary = run(h.snapshot(pending: ["X.ARW"]))
        XCTAssertEqual(originalsGiven, ["X.ARW"])
        XCTAssertEqual(summary.notes, [])
        XCTAssertEqual(summary.originalsInTrash, 1)
        XCTAssertEqual(calls.filter { $0 == "record X.dng" }.count, 6)
    }

    // At factor 1 the new DNG is at the value already. The tag step writes
    // nothing, the DNG is the file of the first record to the end, and the
    // original moves.
    func testLine6ATagStepThatWasSkippedLeavesTheRecordAndTheOriginalMoves() {
        h.files.records["X.dng"] = [made]
        let summary = h.job().run(h.snapshot(pending: ["X.ARW"]), factor: .noStretch, convert: true,
                                  trashOriginals: true)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(calls, [
            "record X.ARW", "convert X.ARW", "record X.dng",
            // The tag step: no write. The check before it, and no new
            // record after it: the first record is the second one too.
            "record X.dng",
            "record X.dng", "record X.dng", "check X.dng", "record X.dng", "record X.ARW", "trashFile X.ARW",
        ])
        XCTAssertEqual(originalsGiven, ["X.ARW"])
        XCTAssertEqual(summary.notes, [])
    }

    // The same skip, and the DNG is another file at the fifth step.
    func testLine6ADNGThatWasReplacedAfterASkippedTagStepKeepsItsOriginal() {
        h.files.records["X.dng"] = [made, made, made, tagged]
        let summary = h.job().run(h.snapshot(pending: ["X.ARW"]), factor: .noStretch, convert: true,
                                  trashOriginals: true)
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(summary.notes, [dngChanged])
    }

    // Line 6 is asked again after the exiftool read of line 5 (order 2, 3,
    // 6, 5, 6 again, 4). A DNG of another `frame.ARW` that has the factor
    // can take the name after the first read of line 6, or after the read
    // of line 5 and before exiftool opens the file. It passes line 5. It is
    // not the file that the tag step left, so the ARW stays.
    func testLine6ADNGThatWasReplacedAtTheFifthStepAfterTheFirstReadOfLine6KeepsItsOriginal() {
        let other = FakeFiles.file(size: 104, modified: 1_002, nanoseconds: 5, number: 9)
        let cases: [[FileRecord?]] = [
            // After the fourth read: line 5 and the read after it see the other file.
            [made, made, tagged, tagged, other],
            // After the fifth read: only the read after exiftool sees it.
            [made, made, tagged, tagged, tagged, other],
            [made, made, tagged, tagged, tagged, nil],
        ]
        for records in cases {
            h = JobHarness()
            h.files.records["X.dng"] = records
            let summary = run(h.snapshot(pending: ["X.ARW"]))
            XCTAssertEqual(h.backups.filesGiven, [], "\(records)")
            XCTAssertEqual(summary.notes, [dngChanged], "\(records)")
            XCTAssertTrue(calls.contains("check X.dng"), "line 5 was asked, and it passed")
            XCTAssertEqual(calls.filter { $0 == "record X.dng" }.count, 6)
            XCTAssertEqual(calls.filter { $0 == "record X.ARW" }.count, 1, "the ARW is not read again")
        }
    }

    // A tag step that skipped wrote nothing, so the DNG must still be the
    // file of the first record. The run takes no new record after a skip:
    // a file that takes the name in that gap would become "the run's own".
    func testLine6ADNGThatWasReplacedDirectlyAfterTheCheckBeforeASkippedTagStepKeepsItsOriginal() {
        let other = FakeFiles.file(number: 9)
        // The swap comes after the second read, at factor 1.
        h.files.records["X.dng"] = [made, made, other]
        let summary = h.job().run(h.snapshot(pending: ["X.ARW"]), factor: .noStretch, convert: true,
                                  trashOriginals: true)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(summary.notes, [dngChanged])
    }

    // Line 3 stands before line 6: a DNG that changed and whose tag step
    // failed keeps its original for line 3.
    func testLine3IsAskedBeforeLine6() {
        h.files.records["X.dng"] = [made, tagged]
        h.tag.failWrites = ["X.dng"]
        let summary = run(h.snapshot(pending: ["X.ARW"]))
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(summary.notes.last?.message, "The original stays, because its DNG is not complete.")
    }

    // One DNG changed, and the next original still moves. A DNG that an
    // earlier run made has no record: the run does not ask the disk about it.
    func testLine6IsAskedForEachDNGOfThisRunAndForNoOther() {
        h.files.records["X.dng"] = [made, tagged]
        let summary = run(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"]))
        XCTAssertEqual(originalsGiven, ["Y.ARW"])
        XCTAssertEqual(summary.notes, [dngChanged])
        XCTAssertEqual(summary.set, 3)
        XCTAssertFalse(calls.contains("record A.dng"))
    }

    // With the option off, the run asks the disk nothing about a DNG.
    func testWithTheOptionOffNoDNGIsRecorded() {
        _ = run(h.snapshot(pending: ["X.ARW"]), trashOriginals: false)
        XCTAssertEqual(calls, ["convert X.ARW", "write 1.5 1 X.dng", "read X.dng", "trash X.dng"])
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
