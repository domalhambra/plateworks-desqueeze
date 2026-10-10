import XCTest
@testable import DesqueezeCore

/// The rule for one original (design 14.2), with no job and no tool: the
/// function that decides, the eight sentences of design 14.3, the record of
/// a file, and the check of a DNG.
final class OriginalsTests: XCTestCase {
    let factor = SqueezeFactor(1.5)!

    // MARK: The function that decides

    /// Counts the questions that `decide` asks, in order.
    final class Asked {
        var order: [String] = []
    }

    func decide(fullMatch: Bool = true, atTheFactor: Bool = true, thisRuns: Bool = true, dng: DNGCheck = .passed,
                stillThisRuns: Bool = true, original: OriginalState = .same, asked: Asked = Asked()) -> OriginalDecision {
        OriginalDecision.decide(
            hasFullMatch: fullMatch, dngIsAtTheFactor: atTheFactor,
            dngIsThisRuns: {
                asked.order.append("this run's")
                return thisRuns
            },
            dng: {
                asked.order.append("dng")
                return dng
            },
            dngIsStillThisRuns: {
                asked.order.append("still this run's")
                return stillThisRuns
            },
            original: {
                asked.order.append("original")
                return original
            })
    }

    func testAnOriginalMovesOnlyWhenEveryLineHolds() {
        XCTAssertEqual(decide(), .move)
    }

    func testLine2ADNGWithNoFullMatchKeepsTheOriginal() {
        XCTAssertEqual(decide(fullMatch: false), .keep(.noFullMatch))
    }

    func testLine3ADNGThatIsNotAtTheFactorKeepsTheOriginal() {
        XCTAssertEqual(decide(atTheFactor: false), .keep(.dngNotComplete))
    }

    func testLine4AnOriginalThatChangedStays() {
        XCTAssertEqual(decide(original: .changed), .keep(.changed))
    }

    func testLine4AnOriginalThatIsNoRegularFileStays() {
        XCTAssertEqual(decide(original: .notARegularFile), .keep(.notARegularFile))
    }

    func testAnOriginalThatIsGoneIsNotMovedAndIsNotSaidToStay() {
        XCTAssertEqual(decide(original: .gone), .keep(.gone))
    }

    func testLine5ADNGThatDidNotPassItsCheckKeepsTheOriginalWithTheDetail() {
        XCTAssertEqual(decide(dng: .failed(detail: "Error: File not found")),
                       .keep(.dngNotChecked(detail: "Error: File not found")))
    }

    // The DNG passes the check of line 5, and it is not the file that this
    // run made: the case of the review of 2026-10-10.
    func testLine6ADNGThatIsNotThisRunsFileKeepsTheOriginal() {
        XCTAssertEqual(decide(thisRuns: false), .keep(.dngChanged))
    }

    // No line alone is enough: with every other line failed, the one that
    // holds does not move the file.
    func testNoSingleLineMovesAnOriginal() {
        for (fullMatch, atTheFactor, thisRuns, dng, original) in [
            (true, false, false, DNGCheck.failed(detail: "x"), OriginalState.changed),
            (false, true, false, DNGCheck.failed(detail: "x"), OriginalState.changed),
            (false, false, true, DNGCheck.failed(detail: "x"), OriginalState.changed),
            (false, false, false, DNGCheck.passed, OriginalState.changed),
            (false, false, false, DNGCheck.failed(detail: "x"), OriginalState.same),
        ] {
            let decision = decide(fullMatch: fullMatch, atTheFactor: atTheFactor, thisRuns: thisRuns, dng: dng,
                                  original: original)
            XCTAssertNotEqual(decision, .move)
        }
    }

    // Each line alone, with every other line good, keeps the file.
    func testEachLineAloneKeepsAnOriginal() {
        XCTAssertNotEqual(decide(fullMatch: false), .move)
        XCTAssertNotEqual(decide(atTheFactor: false), .move)
        XCTAssertNotEqual(decide(thisRuns: false), .move)
        XCTAssertNotEqual(decide(dng: .failed(detail: "x")), .move)
        XCTAssertNotEqual(decide(stillThisRuns: false), .move)
        for state in [OriginalState.changed, .notARegularFile, .gone] {
            XCTAssertNotEqual(decide(original: state), .move)
        }
    }

    // An ARW that stays for line 2 or line 3 costs no read of the disk and
    // no exiftool call.
    func testTheReadsAreNotMadeForAnOriginalThatStaysAlready() {
        let asked = Asked()
        _ = decide(fullMatch: false, asked: asked)
        _ = decide(atTheFactor: false, asked: asked)
        XCTAssertEqual(asked.order, [])
    }

    // The order of design 14.2: 6, 5, 4. The DNG is checked first, in two
    // questions: it is this run's file, and it passes its check. The second
    // read of the ARW is the last thing before the move.
    func testTheDNGIsCheckedFirstAndTheOriginalIsReadLast() {
        let asked = Asked()
        XCTAssertEqual(decide(asked: asked), .move)
        XCTAssertEqual(asked.order, ["this run's", "dng", "still this run's", "original"])
    }

    // Line 6 again: the DNG passed its check, and it is no longer the file
    // that the tag step left. The ARW is not read.
    func testLine6IsAskedAgainAfterTheCheckOfTheDNGAndBeforeTheOriginal() {
        let asked = Asked()
        XCTAssertEqual(decide(stillThisRuns: false, original: .changed, asked: asked), .keep(.dngChanged))
        XCTAssertEqual(asked.order, ["this run's", "dng", "still this run's"])
    }

    // The tags of a DNG that is not this run's file say nothing: exiftool
    // is not asked, and the ARW is not read.
    func testAfterLine6FailedTheDNGIsNotCheckedAndTheOriginalIsNotRead() {
        let asked = Asked()
        XCTAssertEqual(decide(thisRuns: false, dng: .failed(detail: "x"), original: .changed, asked: asked),
                       .keep(.dngChanged))
        XCTAssertEqual(asked.order, ["this run's"])
    }

    func testAfterAFailedCheckOfTheDNGTheOriginalIsNotRead() {
        let asked = Asked()
        _ = decide(dng: .failed(detail: "x"), original: .changed, asked: asked)
        XCTAssertEqual(asked.order, ["this run's", "dng"])
    }

    // MARK: The eight sentences (design 14.3)

    func note(_ reason: OriginalDecision.KeepReason) -> FileNote { .originalKept("frame.ARW", because: reason) }

    func testTheSentenceOfLine2() {
        XCTAssertEqual(note(.noFullMatch), FileNote(
            name: "frame.ARW", kind: .originalKept,
            message: "The original stays, because its DNG has no full match.", detail: nil))
    }

    func testTheSentenceOfLine3() {
        XCTAssertEqual(note(.dngNotComplete), FileNote(
            name: "frame.ARW", kind: .originalKept,
            message: "The original stays, because its DNG is not complete.", detail: nil))
    }

    func testTheSentenceOfLine4ForAnOriginalThatChanged() {
        XCTAssertEqual(note(.changed), FileNote(
            name: "frame.ARW", kind: .originalKept,
            message: "The original changed during the run, so it stays.", detail: nil))
    }

    func testTheSentenceOfLine4ForAnOriginalThatIsNoRegularFile() {
        XCTAssertEqual(note(.notARegularFile), FileNote(
            name: "frame.ARW", kind: .originalKept,
            message: "The original is not a regular file, so it stays.", detail: nil))
    }

    func testTheSentenceOfLine5HasTheDetail() {
        XCTAssertEqual(note(.dngNotChecked(detail: "Error: File not found")), FileNote(
            name: "frame.ARW", kind: .originalKept,
            message: "The original stays, because its DNG could not be checked.", detail: "Error: File not found"))
    }

    func testTheSentenceOfLine6() {
        XCTAssertEqual(note(.dngChanged), FileNote(
            name: "frame.ARW", kind: .originalKept,
            message: "The original stays, because its DNG changed during the run.", detail: nil))
    }

    // "It stays" would be false for an ARW that is not there.
    func testTheSentenceForAnOriginalThatIsGoneDoesNotSayThatItStays() {
        XCTAssertEqual(note(.gone), FileNote(
            name: "frame.ARW", kind: .originalKept,
            message: "The original was not in the folder at the end of the run. The app did not move it.",
            detail: nil))
    }

    func testTheSentenceForATrashThatRefusedHasTheSystemsWords() {
        XCTAssertEqual(note(.trashRefused(detail: "The volume has no Trash.")), FileNote(
            name: "frame.ARW", kind: .originalKept,
            message: "The original could not go to the Trash, so it stays.", detail: "The volume has no Trash."))
    }

    func testTheKindIsWrittenAsOriginalKept() {
        XCTAssertEqual(FileNote.Kind.originalKept.rawValue, "originalKept")
    }

    // It is information, as `convertedUnmatched` is: not failed, not
    // blocked, and no "needs attention".
    func testAnOriginalThatStaysNeedsNoAttention() {
        var summary = RunSummary()
        summary.convertedByDnglab = 1
        summary.trashOriginals = true
        summary.notes = [note(.changed)]
        XCTAssertFalse(summary.needsAttention)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.blocked, 0)
    }

    // MARK: The result line (design 14.3)

    func testTheResultLineHasTheTwoCounts() {
        var summary = RunSummary()
        summary.trashOriginals = true
        summary.convertedByDnglab = 11
        summary.convertedByAdobe = 1
        summary.originalsInTrash = 11
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 11 of 12.")
        XCTAssertEqual(RunReport(folder: URL(fileURLWithPath: "/path"), factor: factor, summary: summary).originalsLine,
                       "Originals moved to the Trash: 11 of 12.")
    }

    func testTheResultLineIsThereAlsoWhenNoOriginalMoved() {
        var summary = RunSummary()
        summary.trashOriginals = true
        XCTAssertEqual(summary.originalsLine, "Originals moved to the Trash: 0 of 0.")
    }

    // The line exists only when the option was on.
    func testWithTheOptionOffThereIsNoResultLine() {
        var summary = RunSummary()
        summary.convertedByDnglab = 3
        XCTAssertNil(summary.originalsLine)
        XCTAssertNil(RunReport(folder: URL(fileURLWithPath: "/path"), factor: factor, summary: summary).originalsLine)
    }

    // A dry run moved nothing. Its steps name each ARW.
    func testADryRunHasNoResultLine() {
        var summary = RunSummary()
        summary.trashOriginals = true
        summary.convertedByDnglab = 2
        summary.originalsInTrash = 2
        let dry = RunReport(folder: URL(fileURLWithPath: "/path"), factor: factor,
                            plan: RunPlan(steps: [], summary: summary))
        XCTAssertNil(dry.originalsLine)
        XCTAssertEqual(dry.originalsInTrash, 2, "the count is in the JSON")
    }

    // MARK: The record of a file, compared (design 14.2, line 4)

    let recorded = FakeFiles.file(size: 100, modified: 1_000, nanoseconds: 5, number: 7)

    func testAFileWithTheSameThreeFactsIsTheSame() {
        XCTAssertEqual(OriginalState(recorded: recorded, now: FakeFiles.file(size: 100, modified: 1_000,
                                                                              nanoseconds: 5, number: 7)), .same)
    }

    func testEachOfTheThreeFactsAloneMakesTheFileChanged() {
        XCTAssertEqual(OriginalState(recorded: recorded, now: FakeFiles.file(size: 101, modified: 1_000,
                                                                              nanoseconds: 5, number: 7)), .changed)
        XCTAssertEqual(OriginalState(recorded: recorded, now: FakeFiles.file(size: 100, modified: 1_001,
                                                                              nanoseconds: 5, number: 7)), .changed)
        XCTAssertEqual(OriginalState(recorded: recorded, now: FakeFiles.file(size: 100, modified: 1_000,
                                                                              nanoseconds: 6, number: 7)), .changed)
        XCTAssertEqual(OriginalState(recorded: recorded, now: FakeFiles.file(size: 100, modified: 1_000,
                                                                              nanoseconds: 5, number: 8)), .changed)
    }

    func testAFileThatWasNeverRecordedIsChanged() {
        XCTAssertEqual(OriginalState(recorded: nil, now: recorded), .changed)
    }

    // Nothing has the name now. That is not "changed": the note for
    // "changed" says that the file stays.
    func testAFileThatIsNotThereIsGone() {
        XCTAssertEqual(OriginalState(recorded: recorded, now: nil), .gone)
        XCTAssertEqual(OriginalState(recorded: nil, now: nil), .gone)
        XCTAssertEqual(OriginalState(recorded: FakeFiles.notAFile, now: nil), .gone)
    }

    // The comparison of lines 4 and 6: both records, and every fact equal.
    func testTwoRecordsAreTheSameFileOnlyWhenBothAreThereAndEqual() {
        let same = FakeFiles.file(size: 100, modified: 1_000, nanoseconds: 5, number: 7)
        XCTAssertTrue(FileRecord.isTheSameFile(recorded: recorded, now: same))
        XCTAssertFalse(FileRecord.isTheSameFile(recorded: recorded, now: nil))
        XCTAssertFalse(FileRecord.isTheSameFile(recorded: nil, now: recorded))
        XCTAssertFalse(FileRecord.isTheSameFile(recorded: nil, now: nil), "no record is no proof")
        for other in [FakeFiles.file(size: 101, modified: 1_000, nanoseconds: 5, number: 7),
                      FakeFiles.file(size: 100, modified: 1_001, nanoseconds: 5, number: 7),
                      FakeFiles.file(size: 100, modified: 1_000, nanoseconds: 6, number: 7),
                      FakeFiles.file(size: 100, modified: 1_000, nanoseconds: 5, number: 8),
                      FileRecord(isRegularFile: false, size: 100, modifiedSeconds: 1_000, modifiedNanoseconds: 5,
                                 fileNumber: 7)] {
            XCTAssertFalse(FileRecord.isTheSameFile(recorded: recorded, now: other), "\(other)")
        }
    }

    func testALinkOrAFolderIsNeverTheSame() {
        XCTAssertEqual(OriginalState(recorded: recorded, now: FakeFiles.notAFile), .notARegularFile)
        // Also when the record from before the conversion was the same link.
        XCTAssertEqual(OriginalState(recorded: FakeFiles.notAFile, now: FakeFiles.notAFile), .notARegularFile)
        XCTAssertEqual(OriginalState(recorded: nil, now: FakeFiles.notAFile), .notARegularFile)
        XCTAssertEqual(OriginalState(recorded: FakeFiles.notAFile, now: recorded), .changed)
    }

    // MARK: The record of a file, read from the disk

    func testTheRecordOfARealFileAFolderALinkAndNothing() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let file = folder.appendingPathComponent("frame.ARW")
        try Data("raw".utf8).write(to: file)
        let link = folder.appendingPathComponent("link.ARW")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let dangling = folder.appendingPathComponent("dangling.ARW")
        try FileManager.default.createSymbolicLink(atPath: dangling.path, withDestinationPath: "/nonexistent/x")
        let subfolder = folder.appendingPathComponent("folder.ARW")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: false)

        let record = try XCTUnwrap(FileRecord.read(atPath: file.path))
        XCTAssertTrue(record.isRegularFile)
        XCTAssertEqual(record.size, 3)
        XCTAssertEqual(FileRecord.read(atPath: file.path), record, "a second read of the same file is equal")

        // The read does not follow a link: a link to a regular file is a link.
        XCTAssertEqual(FileRecord.read(atPath: link.path)?.isRegularFile, false)
        XCTAssertNotEqual(FileRecord.read(atPath: link.path)?.fileNumber, record.fileNumber)
        XCTAssertEqual(FileRecord.read(atPath: dangling.path)?.isRegularFile, false)
        XCTAssertEqual(FileRecord.read(atPath: subfolder.path)?.isRegularFile, false)
        XCTAssertNil(FileRecord.read(atPath: folder.appendingPathComponent("none.ARW").path))
    }

    func testAFileThatWasWrittenAgainOrReplacedHasAnotherRecord() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let file = folder.appendingPathComponent("frame.ARW")
        try Data("raw".utf8).write(to: file)
        let before = try XCTUnwrap(FileRecord.read(atPath: file.path))

        // Another file takes the name, with the same bytes and the same
        // date: the file number alone says so.
        let other = folder.appendingPathComponent("other.ARW")
        try Data("raw".utf8).write(to: other)
        let date = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate])
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: other.path)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: other, to: file)
        let replaced = try XCTUnwrap(FileRecord.read(atPath: file.path))
        XCTAssertEqual(replaced.size, before.size)
        XCTAssertNotEqual(replaced.fileNumber, before.fileNumber)
        XCTAssertEqual(OriginalState(recorded: before, now: replaced), .changed)

        // The same file, with one byte more.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("x".utf8))
        try handle.close()
        let longer = try XCTUnwrap(FileRecord.read(atPath: file.path))
        XCTAssertEqual(longer.fileNumber, replaced.fileNumber)
        XCTAssertEqual(OriginalState(recorded: replaced, now: longer), .changed)
    }

    // MARK: The check of the DNG (design 14.2, line 5)

    func check(record: FileRecord? = FakeFiles.file(), arw: String = "frame.ARW", name: String? = "frame.ARW",
               scale: Scale? = Scale(horizontal: 1.5, vertical: 1)) -> DNGCheck {
        DNGCheck.check("frame.dng", record: record, arw: arw, factor: factor,
                       tags: { OriginalCheckTags(originalRawFileName: name, scale: scale) })
    }

    func testADNGWithBytesTheNameOfTheARWAndTheFactorPasses() {
        XCTAssertEqual(check(), .passed)
    }

    func testADNGThatIsNotThereOrIsNoRegularFileFailsAndIsNotRead() {
        for record in [nil, FakeFiles.notAFile] {
            let result = DNGCheck.check("frame.dng", record: record, arw: "frame.ARW", factor: factor, tags: {
                XCTFail("exiftool must not be asked")
                return OriginalCheckTags(originalRawFileName: "frame.ARW", scale: nil)
            })
            XCTAssertEqual(result, .failed(detail: "frame.dng is not a regular file."))
        }
    }

    func testADNGWithNoBytesFailsAndIsNotRead() {
        let result = DNGCheck.check("frame.dng", record: FakeFiles.file(size: 0), arw: "frame.ARW", factor: factor,
                                    tags: {
                                        XCTFail("exiftool must not be asked")
                                        return OriginalCheckTags(originalRawFileName: "frame.ARW", scale: nil)
                                    })
        XCTAssertEqual(result, .failed(detail: "frame.dng has no bytes."))
    }

    func testAReadThatFailsGivesExiftoolsWords() {
        let result = DNGCheck.check("frame.dng", record: FakeFiles.file(), arw: "frame.ARW", factor: factor,
                                    tags: { throw TagError.toolFailed("Error: File not found") })
        XCTAssertEqual(result, .failed(detail: "Error: File not found"))
    }

    func testADNGThatNamesNoARWOrAnotherARWFails() {
        XCTAssertEqual(check(name: nil), .failed(detail: "frame.dng has no OriginalRawFileName."))
        XCTAssertEqual(check(name: "other.ARW"),
                       .failed(detail: "The OriginalRawFileName of frame.dng is other.ARW, not frame.ARW."))
        // The claim of the scan ignores letter case. This check does not.
        XCTAssertEqual(check(name: "FRAME.arw"),
                       .failed(detail: "The OriginalRawFileName of frame.dng is FRAME.arw, not frame.ARW."))
    }

    // exiftool prints a control character as a period (design 13.9). The
    // name of the ARW is compared in that form.
    func testANameWithAControlCharacterIsComparedAsExiftoolPrintsIt() {
        XCTAssertEqual(check(arw: "a\tb.ARW", name: "a.b.ARW"), .passed)
        XCTAssertEqual(check(arw: "a\tb.ARW", name: "a\tb.ARW"),
                       .failed(detail: "The OriginalRawFileName of frame.dng is a\tb.ARW, not a.b.ARW."))
    }

    func testADNGWithNoScaleOrAnotherScaleFails() {
        XCTAssertEqual(check(scale: nil), .failed(detail: "frame.dng has no DefaultScale."))
        XCTAssertEqual(check(scale: .noStretch), .failed(detail: "The DefaultScale of frame.dng is 1 1, not 1.5 1."))
        XCTAssertEqual(check(scale: Scale(horizontal: 1.5, vertical: 2)),
                       .failed(detail: "The DefaultScale of frame.dng is 1.5 2, not 1.5 1."))
    }

    // The comparison of design 4.3, step 3: a neighbor factor is no match.
    func testTheFactorIsComparedAsTheTagStepComparesIt() {
        XCTAssertEqual(check(scale: Scale(horizontal: 1.50004, vertical: 1)), .passed)
        XCTAssertEqual(check(scale: Scale(horizontal: 1.5001, vertical: 1)),
                       .failed(detail: "The DefaultScale of frame.dng is 1.5001 1, not 1.5 1."))
    }

    // MARK: The exiftool read (design 14.2, line 5)

    func testTheReadHasExactlyTheArgumentsOfTheDesign() throws {
        let runner = FakeRunner()
        runner.handler = { _ in ProcessResult(exitCode: 0, stdout: "frame.ARW\t1.5 1\n", stderr: "") }
        let dng = URL(fileURLWithPath: "/tmp/Shoot 1/frame.dng")
        let tags = try ScaleTag(exiftool: URL(fileURLWithPath: "/x/exiftool"), runner: runner).readOriginalCheck(dng)
        XCTAssertEqual(runner.calls, [FakeRunner.Call(executable: "/x/exiftool", arguments: [
            "-m", "-n", "-T", "-IFD0:OriginalRawFileName", "-SubIFD:DefaultScale", "/tmp/Shoot 1/frame.dng",
        ])])
        XCTAssertEqual(tags, OriginalCheckTags(originalRawFileName: "frame.ARW",
                                               scale: Scale(horizontal: 1.5, vertical: 1)))
    }

    // exiftool 13.55, 2026-10-10, for a file that is not there: no row on
    // standard output, exit code 1, and this line on standard error.
    func testARowThatIsNotThereThrowsWithExiftoolsWords() {
        let runner = FakeRunner()
        runner.handler = { _ in
            ProcessResult(exitCode: 1, stdout: "", stderr: "Error: File not found - /tmp/Shoot 1/frame.dng\n")
        }
        let tag = ScaleTag(exiftool: URL(fileURLWithPath: "/x/exiftool"), runner: runner)
        XCTAssertThrowsError(try tag.readOriginalCheck(URL(fileURLWithPath: "/tmp/Shoot 1/frame.dng"))) {
            XCTAssertEqual($0 as? TagError, .toolFailed("Error: File not found"))
        }
    }

    // Each text here is what exiftool 13.55 printed on 2026-10-10 for
    // `-m -n -T -IFD0:OriginalRawFileName -SubIFD:DefaultScale <file>`, on
    // copies of a DNG that Adobe DNG Converter 18.7 made from `sample.ARW`.
    func testTheParserReadsRealExiftoolOutput() {
        // The DNG as the converter made it.
        XCTAssertEqual(ScaleTag.parseOriginalCheck("sample.ARW\t1 1\n"),
                       OriginalCheckTags(originalRawFileName: "sample.ARW", scale: .noStretch))
        // After `-SubIFD:DefaultScale=1.5 1`, and after `=1.3333 1`.
        XCTAssertEqual(ScaleTag.parseOriginalCheck("sample.ARW\t1.5 1\n"),
                       OriginalCheckTags(originalRawFileName: "sample.ARW", scale: Scale(horizontal: 1.5, vertical: 1)))
        XCTAssertEqual(ScaleTag.parseOriginalCheck("sample.ARW\t1.3333 1\n")?.scale,
                       Scale(horizontal: 1.3333, vertical: 1))
        // After `-IFD0:OriginalRawFileName=`: the DNG names no ARW.
        XCTAssertEqual(ScaleTag.parseOriginalCheck("-\t1 1\n"),
                       OriginalCheckTags(originalRawFileName: nil, scale: .noStretch))
        // A name that was written with a tab in it: exiftool prints a period.
        XCTAssertEqual(ScaleTag.parseOriginalCheck("a.bc.ARW\t1 1\n")?.originalRawFileName, "a.bc.ARW")
        // A file of nine bytes that is no DNG: one row, exit code 0.
        XCTAssertEqual(ScaleTag.parseOriginalCheck("-\t-\n"), OriginalCheckTags(originalRawFileName: nil, scale: nil))
        // A file that is not there: nothing on standard output.
        XCTAssertNil(ScaleTag.parseOriginalCheck(""))
    }

    func testALineThatIsNoRowOfTwoCellsIsNoRow() {
        XCTAssertNil(ScaleTag.parseOriginalCheck("sample.ARW\n"))
        XCTAssertNil(ScaleTag.parseOriginalCheck("sample.ARW\t1 1\textra\n"))
    }

    // MARK: The words of the window (design 14.4)

    func testTheLabelOfTheCheckbox() {
        XCTAssertEqual(FolderText.trashOriginalsLabel, "Move the original ARW files to the Trash")
    }

    func testTheLineUnderTheCheckboxForOneAndForMany() {
        XCTAssertEqual(FolderText.trashOriginalsLine(count: 1),
                       "1 original ARW file goes to the Trash after its DNG file passes the check.")
        XCTAssertEqual(FolderText.trashOriginalsLine(count: 2),
                       "2 original ARW files go to the Trash after their DNG files pass the check.")
        XCTAssertEqual(FolderText.trashOriginalsLine(count: 12),
                       "12 original ARW files go to the Trash after their DNG files pass the check.")
    }

    // The text of design 14.4, in the words of Finder's "Move to Trash".
    // The part about the originals is the same for one and for many. The
    // first text, "…move 12 originals to the Trash", was cut at the
    // window's width.
    func testTheRunLabelWithTheOriginals() {
        XCTAssertEqual(FolderText.runLabel(count: 228, originalsToTrash: 12),
                       "Desqueeze 228 photos, move 12 ARW to Trash")
        XCTAssertEqual(FolderText.runLabel(count: 2, originalsToTrash: 1), "Desqueeze 2 photos, move 1 ARW to Trash")
        XCTAssertEqual(FolderText.runLabel(count: 1, originalsToTrash: 1), "Desqueeze 1 photo, move 1 ARW to Trash")
        XCTAssertEqual(FolderText.runLabel(count: 9_999, originalsToTrash: 9_999),
                       "Desqueeze 9999 photos, move 9999 ARW to Trash")
    }

    // With the box off, or with no original to move, the label is the one
    // of design 5.
    func testTheRunLabelWithNoOriginalIsThePlainLabel() {
        XCTAssertEqual(FolderText.runLabel(count: 228, originalsToTrash: 0), "Desqueeze 228 photos")
        XCTAssertEqual(FolderText.runLabel(count: 1, originalsToTrash: 0), "Desqueeze 1 photo")
        XCTAssertEqual(FolderText.runLabel(count: 0, originalsToTrash: 0), "Desqueeze")
    }

    func testTheOriginalsThatCanMoveAreThePendingARWFilesThatCanConvert() {
        let h = JobHarness()
        let state = h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"])
        XCTAssertEqual(state.convertibleARWs(converterAvailable: true), 2)
        XCTAssertEqual(state.convertibleARWs(converterAvailable: false), 0)
        XCTAssertEqual(h.snapshot(dngs: [h.dng("A.dng")]).convertibleARWs(converterAvailable: true), 0)
    }

    // An ARW whose name is too long gets no converter (design 13.9), so no
    // run can move it. The box and its count follow the rule of the run and
    // of the plan: 222 letters convert, and 223 do not.
    func testAnARWWhoseNameIsTooLongIsNoOriginalThatCanMove() {
        let h = JobHarness()
        let longest = String(repeating: "n", count: 222) + ".ARW"
        let tooLong = String(repeating: "n", count: 223) + ".ARW"
        XCTAssertEqual(h.snapshot(pending: [tooLong]).convertibleARWs(converterAvailable: true), 0,
                       "the box does not show for this folder")
        XCTAssertEqual(h.snapshot(pending: [longest]).convertibleARWs(converterAvailable: true), 1)
        let mixed = h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", longest, tooLong])
        XCTAssertEqual(mixed.convertibleARWs(converterAvailable: true), 2)
        XCTAssertEqual(mixed.convertibleARWs(converterAvailable: false), 0)

        // The plan has a step for the same ARW files, and for no other.
        let plan = h.job().plan(mixed, factor: factor, convert: true, trashOriginals: true)
        XCTAssertEqual(plan.steps.filter { $0.action == .convert }.count, 2)
        XCTAssertEqual(plan.steps.filter { $0.action == .trashOriginal }.map(\.name), ["X.ARW", longest])
        XCTAssertEqual(plan.summary.originalsInTrash, mixed.convertibleARWs(converterAvailable: true))
    }

    // The run button still counts an ARW whose name is too long: the run
    // takes the file, and its note says what to do. With the file out of
    // the count, a folder that holds only this file would have no button
    // to press, and no word about why.
    func testTheRunCountKeepsAnARWWhoseNameIsTooLong() {
        let h = JobHarness()
        let tooLong = String(repeating: "n", count: 223) + ".ARW"
        XCTAssertEqual(h.snapshot(pending: [tooLong]).runCount(converterAvailable: true), 1)
        XCTAssertEqual(h.snapshot(pending: [tooLong]).runCount(converterAvailable: false), 0)
        XCTAssertEqual(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", tooLong])
            .runCount(converterAvailable: true), 3)
    }
}
