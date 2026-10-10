import XCTest
@testable import DesqueezeCore

/// What a run reports: the kind of each note, the blocked count, the ARW
/// files it left, and the one line of counts.
final class RunSummaryTests: XCTestCase {
    let factor = SqueezeFactor(1.5)!
    var h: JobHarness!

    override func setUp() { h = JobHarness() }

    // MARK: The kind of each note

    // The raw values are the JSON values. A front end reads them.
    func testTheKindsAreTheSevenNamesOfTheDesignAndTheOnesOfSections13And14() {
        XCTAssertEqual(FileNote.Kind.allCases.map(\.rawValue), [
            "orphanBackup", "notConverted", "failed", "blockedByBackup", "leftoverBackup", "backupKept",
            "folderReadOnly", "convertedUnmatched", "originalKept", "noFolderLock",
        ])
    }

    // A note about a volume that gives no folder lock is information
    // (design 13.9): it marks no result as one to look at.
    func testANoteAboutAVolumeWithNoFolderLockNeedsNoAttention() {
        var summary = RunSummary()
        summary.set = 3
        summary.notes = [.noFolderLock(URL(fileURLWithPath: "/tmp/Shoot 1"))]
        XCTAssertFalse(summary.needsAttention)
        XCTAssertEqual(summary.countsLine, "3 set · 0 skipped · 0 failed")
    }

    // MARK: A DNG with no full match (design 13.4)

    static let ending = "Install Adobe DNG Converter for the same file that Lightroom makes."

    // Only rule 4 failed: every tag is written, and the lens correction is
    // what the DNG does not have.
    func testTheNoteOfALensFrameSaysThatTheDNGHasNoLensCorrection() {
        XCTAssertEqual(FileNote.convertedUnmatched("X.dng", rule: .noLensCorrection, facts: .lens), FileNote(
            name: "X.dng", kind: .convertedUnmatched,
            message: "Converted. The DNG has no built-in lens correction. \(Self.ending)",
            detail: "The ARW holds lens-correction data, and dnglab does not write it into the DNG."))
    }

    // The ARW has no word about lens-correction data: the tag is absent, or
    // exiftool could not read it. The note must not say that the ARW holds
    // such data. It says what is known: the ARW does not say.
    func testTheNoteOfAFrameThatDoesNotSayIfItHasLensCorrectionDataSaysSo() {
        let silent = ARWFacts(model: "ILCE-7SM3", iso: 80,
                              daylightLevels: ARWFacts.DaylightLevels(red: 2496, green: 1024, blue: 1617),
                              distortionCorrection: nil, rawFileType: 2)
        XCTAssertEqual(AdobeMatch.match(silent).failed, .noLensCorrection)
        XCTAssertEqual(FileNote.convertedUnmatched("X.dng", rule: .noLensCorrection, facts: silent), FileNote(
            name: "X.dng", kind: .convertedUnmatched,
            message: "Converted. The DNG has no built-in lens correction. \(Self.ending)",
            detail: "The ARW does not say whether it has lens-correction data, and dnglab writes none into the DNG."))
        // Any value that is there, and is not "no data", is data.
        for value in [17, 0, 1] {
            let says = ARWFacts(model: "ILCE-7SM3", iso: 80, daylightLevels: silent.daylightLevels,
                                distortionCorrection: value, rawFileType: 2)
            XCTAssertEqual(FileNote.convertedUnmatched("X.dng", rule: .noLensCorrection, facts: says).detail,
                           "The ARW holds lens-correction data, and dnglab does not write it into the DNG.", "\(value)")
        }
    }

    // Rule 1, 2, 3 or 5 failed: no tag of the match is in the DNG.
    func testTheNoteOfAFrameWithNoTableRowSaysThatTheLevelsAreDnglabsOwn() {
        let levels = "Converted. The levels are dnglab's own. \(Self.ending)"
        let other = ARWFacts(model: "ILCE-7M4", iso: 800, daylightLevels: nil, saysNoLensCorrection: true)
        let cases: [(AdobeMatch.Rule, ARWFacts, String)] = [
            (.model, other, "The table of Adobe's values has no camera ILCE-7M4."),
            (.model, .none, "The camera model could not be read from the ARW."),
            (.iso, .iso1250, "The table of Adobe's values has no row for ISO 1250."),
            (.iso, .none, "The ISO could not be read from the ARW."),
            (.daylightLevels, .none, "The ARW has no daylight levels that the table of Adobe's values can use."),
            (.compressedRaw, .uncompressed,
             "The table of Adobe's values has compressed raw only, and this ARW is another kind."),
            (.compressedRaw, .none, "The kind of raw data could not be read from the ARW."),
        ]
        for (rule, facts, detail) in cases {
            XCTAssertEqual(FileNote.convertedUnmatched("X.dng", rule: rule, facts: facts), FileNote(
                name: "X.dng", kind: .convertedUnmatched, message: levels, detail: detail))
        }
    }

    func testEachNoteOfADNGWithNoFullMatchEndsWithTheSentenceOfTheDesign() {
        XCTAssertEqual(FileNote.installAdobeForTheSameFile, Self.ending)
        for rule in AdobeMatch.Rule.allCases {
            let note = FileNote.convertedUnmatched("X.dng", rule: rule, facts: .none)
            XCTAssertTrue(note.message.hasPrefix("Converted. "), note.message)
            XCTAssertTrue(note.message.hasSuffix(" " + Self.ending), note.message)
            XCTAssertEqual(note.kind, .convertedUnmatched)
        }
    }

    // Such a file is converted. It is not failed and not blocked, so the
    // result is not one to look at.
    func testADNGWithNoFullMatchCountsAsConvertedAndNeedsNoAttention() {
        h.facts.facts = ["X.ARW": .lens]
        let summary = h.job(withConverter: false, withDnglab: true)
            .run(h.snapshot(pending: ["X.ARW"]), factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.notes.map(\.kind), [.convertedUnmatched])
        XCTAssertEqual([summary.converted, summary.convertedByDnglab, summary.convertedByAdobe], [1, 1, 0])
        XCTAssertEqual([summary.failed, summary.blocked, summary.unconvertedARWs], [0, 0, 0])
        XCTAssertFalse(summary.needsAttention)
        XCTAssertEqual(summary.countsLine, "1 converted · 1 set · 0 skipped · 0 failed")
    }

    func testConvertedIsTheSumOfTheTwoConverters() {
        var summary = RunSummary()
        XCTAssertEqual(summary.converted, 0)
        summary.convertedByDnglab = 3
        summary.convertedByAdobe = 4
        XCTAssertEqual(summary.converted, 7)
        XCTAssertEqual(summary.countsLine, "7 converted · 0 set · 0 skipped · 0 failed")
    }

    func testAnOrphanBackupNoteHasItsKind() {
        let summary = h.job().run(h.snapshot(orphans: ["gone.dng_original"]),
                                  factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.notes.map(\.kind), [.orphanBackup])
    }

    func testAFailedConversionNoteHasItsKind() {
        h.converter.fail = ["X.ARW"]
        let summary = h.job().run(h.snapshot(pending: ["X.ARW"]), factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.notes.map(\.kind), [.notConverted])
    }

    func testEachWayAWriteFailsGivesTheKindFailed() {
        h.tag.failWrites = ["write.dng"]
        h.tag.wrongReadBack = ["check.dng"]
        let summary = h.job().run(h.snapshot(dngs: [h.dng("write.dng"), h.dng("check.dng")]),
                                  factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.notes.map(\.message), ["Not changed.", "Not changed. The backup was restored."])
        XCTAssertEqual(summary.notes.map(\.kind), [.failed, .failed])
    }

    func testAFailedRestoreGivesTheKindFailed() {
        h.tag.wrongReadBack = ["A.dng"]
        h.backups.restoreError = NamedError(text: "The volume refused the rename.")
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng")]),
                                  factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.notes.map(\.kind), [.failed])
        XCTAssertEqual(summary.failed, 1)
    }

    func testABlockedFileNoteHasItsKindAndSaysBlocked() {
        h.backups.existing = ["A.dng"]
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng")]),
                                  factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "A.dng", kind: .blockedByBackup,
            message: "Blocked. An older backup, A.dng_original, is beside this file. Move it away, then run again.",
            detail: nil)])
    }

    func testALeftoverBackupNoteHasItsKindAndTheExactSentence() {
        h.backups.existing = ["A.dng"]
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng", at: 1.5)]),
                                  factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "A.dng", kind: .leftoverBackup,
            message: "Already at this value. A backup, A.dng_original, is beside this file.", detail: nil)])
    }

    func testARefusedTrashNoteHasItsKind() {
        h.backups.trashError = NamedError(text: "The Trash is not here.")
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng")]),
                                  factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.notes, [FileNote(
            name: "A.dng", kind: .backupKept,
            message: "Done. The backup stayed beside the file, because the Trash refused it.",
            detail: "The Trash is not here.")])
    }

    func testAReadOnlyFolderNoteHasItsKind() {
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng")], writable: false),
                                  factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.notes.map(\.kind), [.folderReadOnly])
    }

    // MARK: Blocked is not skipped

    func testABlockedFileIsNotInTheSkippedCount() {
        h.backups.existing = ["old backup.dng"]
        let files = [h.dng("old backup.dng"), h.dng("at value.dng", at: 1.5), h.dng("new.dng")]
        let summary = h.job().run(h.snapshot(dngs: files), factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.blocked, 1)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(h.log.entries, ["write 1.5 1 new.dng", "read new.dng", "trash new.dng"])
    }

    // A file at the value with a leftover backup is skipped: it is at the value.
    func testALeftoverBackupFileIsSkippedNotBlocked() {
        h.backups.existing = ["A.dng"]
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng", at: 1.5)]),
                                  factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.blocked, 0)
    }

    // MARK: An empty folder

    // A front end shows `FolderText.noPhotos` for it. A folder with an orphan
    // backup or a pending ARW is not empty, also when the run has no work
    // for it: Remove reports no ARW file, and a stopped run counts nothing.
    func testTheSummaryKnowsWhetherTheFolderWasEmpty() {
        let cases: [(String, FolderSnapshot, Bool)] = [
            ("empty", h.snapshot(), true),
            ("an orphan only", h.snapshot(orphans: ["gone.dng_original"]), false),
            ("an ARW only", h.snapshot(pending: ["X.ARW"]), false),
            ("a DNG only", h.snapshot(dngs: [h.dng("A.dng")]), false),
        ]
        for (name, state, empty) in cases {
            for remove in [false, true] {
                XCTAssertEqual(h.job().run(state, factor: remove ? .noStretch : factor, convert: !remove,
                                           trashOriginals: false,
                                           remove: remove).folderIsEmpty, empty, "run \(name) \(remove)")
                XCTAssertEqual(h.job().plan(state, factor: remove ? .noStretch : factor, convert: !remove,
                                            trashOriginals: false,
                                            remove: remove).summary.folderIsEmpty, empty, "plan \(name) \(remove)")
            }
        }
        XCTAssertEqual(h.job().run(h.snapshot(writable: false),
                                   factor: factor, convert: true, trashOriginals: false).folderIsEmpty, true)
    }

    // MARK: The ARW files a run left

    func testARunThatConvertsEveryPendingARWLeavesNone() {
        let summary = h.job().run(h.snapshot(pending: ["X.ARW", "Y.ARW"]),
                                  factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.converted, 2)
        XCTAssertEqual(summary.unconvertedARWs, 0)
    }

    func testWithNoConverterARunLeavesEveryPendingARW() {
        let summary = h.job(withConverter: false).run(
            h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"]), factor: factor, convert: true,
            trashOriginals: false)
        XCTAssertEqual(summary.unconvertedARWs, 2)
        XCTAssertEqual(summary.set, 1)
        XCTAssertEqual(summary.failed, 0, "a missing converter is not a failed file")
        XCTAssertEqual(summary.notes, [])
    }

    func testARunToldNotToConvertLeavesEveryPendingARW() {
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"]),
                                  factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual(summary.unconvertedARWs, 2)
        XCTAssertEqual(summary.converted, 0)
        XCTAssertEqual(h.log.entries, ["write 1.5 1 A.dng", "read A.dng", "trash A.dng"])
    }

    func testRemoveNeverConvertsAndReportsNoARW() {
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng", at: 1.5)], pending: ["X.ARW", "Y.ARW"]),
                                  factor: .noStretch, convert: false, trashOriginals: false, remove: true)
        XCTAssertEqual(summary.unconvertedARWs, 0)
        XCTAssertEqual(summary.set, 1)
    }

    // Remove is an intent (design 12.1). The same arguments with no intent
    // are a run at factor 1, and it reports the ARW files it left.
    func testARunAtFactorOneWithNoConvertIsNotRemoveAndReportsTheARWFiles() {
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng", at: 1.5)], pending: ["X.ARW", "Y.ARW"]),
                                  factor: .noStretch, convert: false, trashOriginals: false)
        XCTAssertEqual(summary.unconvertedARWs, 2)
        XCTAssertEqual(summary.set, 1)
    }

    func testRemoveNeverConvertsEvenWhenToldToConvert() {
        let summary = h.job().run(h.snapshot(dngs: [h.dng("A.dng", at: 1.5)], pending: ["X.ARW"]),
                                  factor: .noStretch, convert: true, trashOriginals: false, remove: true)
        XCTAssertEqual(summary.converted, 0)
        XCTAssertEqual(summary.unconvertedARWs, 0)
        XCTAssertEqual(h.log.entries, ["write 1 1 A.dng", "read A.dng", "trash A.dng"])
    }

    // The ARW is in `failed`, with a note. It also has no DNG, so it is left.
    func testAFailedConversionIsAlsoAnARWTheRunLeft() {
        h.converter.fail = ["X.ARW"]
        let summary = h.job().run(h.snapshot(pending: ["X.ARW", "Y.ARW"]),
                                  factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.unconvertedARWs, 1)
    }

    func testAStoppedRunLeavesTheARWFilesItDidNotReach() {
        let flag = CancelFlag()
        h.converter.onConvert = { flag.cancel() }
        let summary = h.job().run(h.snapshot(pending: ["X.ARW", "Y.ARW", "Z.ARW"]), factor: factor,
                                  convert: true, trashOriginals: false, cancel: flag)
        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.unconvertedARWs, 2)
    }

    func testAReadOnlyFolderLeavesEveryPendingARWAndRemoveStillReportsNone() {
        let state = h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW"], writable: false)
        XCTAssertEqual(h.job().run(state, factor: factor, convert: true, trashOriginals: false).unconvertedARWs, 1)
        XCTAssertEqual(h.job().run(state, factor: .noStretch, convert: false,
                                   trashOriginals: false, remove: true).unconvertedARWs, 0)
        XCTAssertEqual(h.log.entries, [])
    }

    // MARK: The sentence about the ARW files a run left

    func left(_ count: Int, stopped: Bool = false) -> RunSummary {
        var summary = RunSummary()
        summary.unconvertedARWs = count
        summary.cancelled = stopped
        return summary
    }

    func testARunThatLeftNoARWHasNoSentence() {
        XCTAssertNil(left(0).unconvertedARWsLine(converterAvailable: true))
        XCTAssertNil(left(0).unconvertedARWsLine(converterAvailable: false))
    }

    func testTheSentenceHasTheCount() {
        XCTAssertEqual(left(1).unconvertedARWsLine(converterAvailable: true), "1 ARW file was not converted.")
        XCTAssertEqual(left(12).unconvertedARWsLine(converterAvailable: true), "12 ARW files were not converted.")
    }

    // With neither converter. The reason does not name Adobe DNG Converter
    // alone: dnglab converts, and Adobe's converter is the backup.
    func testTheSentenceSaysWhyWhenNoConverterIsInstalled() {
        XCTAssertEqual(left(1).unconvertedARWsLine(converterAvailable: false),
                       "1 ARW file was not converted. No converter is installed.")
        XCTAssertEqual(left(12).unconvertedARWsLine(converterAvailable: false),
                       "12 ARW files were not converted. No converter is installed.")
    }

    // The job with no converter, to the sentence: the count is the job's own.
    func testTheSentenceOfARunWithNoConverter() {
        let summary = h.job(withConverter: false).run(
            h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"]), factor: factor, convert: true,
            trashOriginals: false)
        XCTAssertEqual(summary.unconvertedARWsLine(converterAvailable: false),
                       "2 ARW files were not converted. No converter is installed.")
    }

    func testTheReportOfARunHasTheSameSentence() {
        let report = RunReport(folder: h.folder, factor: factor, summary: left(12))
        XCTAssertEqual(report.unconvertedARWsLine(converterAvailable: false),
                       left(12).unconvertedARWsLine(converterAvailable: false))
    }

    func testTheReportOfADryRunSaysWouldNotBe() {
        let plan = RunPlan(steps: [], summary: left(2))
        let report = RunReport(folder: h.folder, factor: factor, plan: plan)
        XCTAssertEqual(report.unconvertedARWsLine(converterAvailable: true), "2 ARW files would not be converted.")
        XCTAssertEqual(report.unconvertedARWsLine(converterAvailable: false),
                       "2 ARW files would not be converted. No converter is installed.")
        let one = RunReport(folder: h.folder, factor: factor, plan: RunPlan(steps: [], summary: left(1)))
        XCTAssertEqual(one.unconvertedARWsLine(converterAvailable: true), "1 ARW file would not be converted.")
    }

    // MARK: The line about the two converters (design 13.6)

    func converted(dnglab: Int, adobe: Int) -> RunSummary {
        var summary = RunSummary()
        summary.convertedByDnglab = dnglab
        summary.convertedByAdobe = adobe
        return summary
    }

    func testARunInWhichBothConvertersWorkedSaysHowManyEachConverted() {
        let report = RunReport(folder: h.folder, factor: factor, summary: converted(dnglab: 11, adobe: 1))
        XCTAssertEqual(report.convertersLine, "Converted with dnglab: 11. With Adobe DNG Converter: 1.")
    }

    func testARunInWhichOneConverterWorkedHasNoSuchLine() {
        for (dnglab, adobe) in [(12, 0), (0, 12), (0, 0)] {
            XCTAssertNil(RunReport(folder: h.folder, factor: factor, summary: converted(dnglab: dnglab, adobe: adobe))
                .convertersLine, "dnglab \(dnglab), Adobe \(adobe)")
        }
    }

    // The steps of a dry run name the converter of each ARW, and nothing is
    // converted yet.
    func testADryRunHasNoSuchLine() {
        let plan = RunPlan(steps: [], summary: converted(dnglab: 11, adobe: 1))
        XCTAssertNil(RunReport(folder: h.folder, factor: factor, plan: plan).convertersLine)
    }

    // The window shows the summary, and the tool shows the report. One rule
    // makes the line for both (design 4.4).
    func testTheSummaryOfARunHasTheLineOfItsReport() {
        let summary = converted(dnglab: 11, adobe: 1)
        XCTAssertEqual(summary.convertersLine, "Converted with dnglab: 11. With Adobe DNG Converter: 1.")
        XCTAssertEqual(RunReport(folder: h.folder, factor: factor, summary: summary).convertersLine,
                       summary.convertersLine)
        for (dnglab, adobe) in [(12, 0), (0, 12), (0, 0)] {
            XCTAssertNil(converted(dnglab: dnglab, adobe: adobe).convertersLine, "dnglab \(dnglab), Adobe \(adobe)")
        }
    }

    // MARK: The Lightroom line (design 4.4)

    func testTheLightroomLineShowsWhenTheRunSetAtLeastOnePhoto() {
        let line = "Photos already in Lightroom: Metadata › Read Metadata from File."
        var summary = RunSummary()
        XCTAssertNil(summary.lightroomLine, "a run that set nothing")
        summary.convertedByDnglab = 2
        summary.skipped = 3
        summary.blocked = 1
        summary.failed = 1
        XCTAssertNil(summary.lightroomLine, "converted, skipped, blocked and failed are not set")
        XCTAssertNil(RunReport(folder: h.folder, factor: factor, summary: summary).lightroomLine)
        summary.set = 1
        XCTAssertEqual(summary.lightroomLine, line)
        XCTAssertEqual(RunReport(folder: h.folder, factor: factor, summary: summary).lightroomLine, line,
                       "the report of the tool follows the same rule as the summary of the window")
        // Remove sets photos too.
        XCTAssertEqual(RunReport(folder: h.folder, factor: .noStretch, summary: summary).lightroomLine, line)
    }

    // The summary of a plan counts what a run would set.
    func testADryRunNeverShowsTheLightroomLine() {
        var summary = RunSummary()
        summary.set = 3
        XCTAssertNil(RunReport(folder: h.folder, factor: factor, plan: RunPlan(steps: [], summary: summary)).lightroomLine)
    }

    // MARK: The line of a note, and the result that needs a look

    func testTheLineOfANoteIsItsNameThenItsSentence() {
        XCTAssertEqual(FileNote(name: "x.dng", kind: .failed, message: "Not changed.", detail: "Error").line,
                       "x.dng: Not changed.")
    }

    func testAResultWithAFailedOrABlockedFileNeedsAttention() {
        XCTAssertFalse(RunSummary().needsAttention)
        var summary = RunSummary()
        summary.set = 3
        summary.skipped = 2
        summary.unconvertedARWs = 4
        summary.cancelled = true
        XCTAssertFalse(summary.needsAttention, "a stopped run with no failed file is not an error")
        summary.failed = 1
        XCTAssertTrue(summary.needsAttention)
        summary.failed = 0
        summary.blocked = 1
        XCTAssertTrue(summary.needsAttention)
    }

    func testTheLightroomLineIsTheLineOfTheDesign() {
        XCTAssertEqual(RunSummary.lightroomHint, "Photos already in Lightroom: Metadata › Read Metadata from File.")
    }

    // MARK: The one line of counts

    func line(_ change: (inout RunSummary) -> Void) -> String {
        var summary = RunSummary()
        change(&summary)
        return summary.countsLine
    }

    func testTheCountsLineOfTheDesign() {
        XCTAssertEqual(line { $0.convertedByDnglab = 1; $0.set = 3 }, "1 converted · 3 set · 0 skipped · 0 failed")
    }

    func testTheCountsLineLeavesOutConvertedAndBlockedAtZero() {
        XCTAssertEqual(line { $0.set = 2; $0.skipped = 4; $0.failed = 1 }, "2 set · 4 skipped · 1 failed")
    }

    func testTheCountsLineShowsBlockedBetweenSkippedAndFailedWhenItIsNotZero() {
        XCTAssertEqual(line { $0.set = 2; $0.blocked = 3 }, "2 set · 0 skipped · 3 blocked · 0 failed")
    }

    func testTheCountsLineEndsWithStoppedAfterACancel() {
        XCTAssertEqual(line { $0.set = 1; $0.blocked = 1; $0.cancelled = true },
                       "1 set · 0 skipped · 1 blocked · 0 failed · stopped")
    }
}
