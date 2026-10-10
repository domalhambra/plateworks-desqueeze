import DesqueezeCore
import XCTest
@testable import DesqueezeCLI

/// The text a person reads. Each test holds the whole output.
final class TextOutputTests: XCTestCase {
    let folder = URL(fileURLWithPath: "/Volumes/Card/Shoot 1")

    func scan(dngs: [ScanReport.DNG] = [], arws: [String] = [], orphans: [String] = [], writable: Bool = true,
              dnglab: String? = nil,
              converter: String? = "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter")
        -> ScanReport {
        ScanReport(folder: folder.path, writable: writable, exiftool: "/opt/homebrew/bin/exiftool", dnglab: dnglab,
                   dngConverter: converter, dngs: dngs, pendingARWs: arws, orphanBackups: orphans)
    }

    func dng(_ name: String, _ scale: String?, backup: Bool = false) -> ScanReport.DNG {
        ScanReport.DNG(name: name, scale: scale, originalRawFileName: nil, hasBackup: backup)
    }

    func testAScanShowsTheTableThenTheARWFilesThenTheMessagesThenTheTools() {
        let report = scan(
            dngs: [dng("a.dng", "1.5 1"), dng("a long name 0001.dng", "1 1"), dng("junk.dng", nil, backup: true)],
            arws: ["b.ARW", "c.ARW"], orphans: ["lost.dng_original"], writable: false)
        XCTAssertEqual(TextOutput.scan(report), [
            "/Volumes/Card/Shoot 1",
            "",
            "DNG files: 3",
            "  Name                  Scale",
            "  a.dng                 1.5 1",
            "  a long name 0001.dng  1 1",
            "  junk.dng              unknown  (a backup is beside it)",
            "",
            "ARW files with no DNG: 2",
            "  b.ARW",
            "  c.ARW",
            "",
            "This folder is read-only. Desqueeze cannot change its files.",
            "lost.dng_original: A backup with no DNG beside it. Rename it to lost.dng to get the photo back.",
            "",
            "exiftool: /opt/homebrew/bin/exiftool",
            "dnglab: not installed",
            "Adobe DNG Converter: /Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter",
            "dnglab is faster and opens no window. Install it with: brew install dnglab",
        ])
    }

    // No ARW is pending, so no advice follows the three tools.
    func testAScanWithNoMessageAndNoConverter() {
        XCTAssertEqual(TextOutput.scan(scan(dngs: [dng("a.dng", "2 1")], converter: nil)), [
            "/Volumes/Card/Shoot 1",
            "",
            "DNG files: 1",
            "  Name   Scale",
            "  a.dng  2 1",
            "",
            "ARW files with no DNG: 0",
            "",
            "exiftool: /opt/homebrew/bin/exiftool",
            "dnglab: not installed",
            "Adobe DNG Converter: not installed",
        ])
    }

    // MARK: The three tools and the advice (design 13.5)

    static let adobe = "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter"

    /// The lines of a scan from the line of exiftool on.
    func tools(arws: [String] = ["b.ARW"], dnglab: String?, converter: String?) -> [String] {
        let lines = TextOutput.scan(scan(arws: arws, dnglab: dnglab, converter: converter))
        return Array(lines[(lines.firstIndex(of: "exiftool: /opt/homebrew/bin/exiftool") ?? lines.endIndex)...])
    }

    func testWithBothConvertersAScanNamesTheThreeToolsInOrderAndGivesNoAdvice() {
        XCTAssertEqual(tools(dnglab: "/opt/homebrew/bin/dnglab", converter: Self.adobe), [
            "exiftool: /opt/homebrew/bin/exiftool",
            "dnglab: /opt/homebrew/bin/dnglab",
            "Adobe DNG Converter: \(Self.adobe)",
        ])
    }

    func testWithDnglabAloneAScanSaysThatAdobeIsAnOptionalBackup() {
        XCTAssertEqual(tools(dnglab: "/opt/homebrew/bin/dnglab", converter: nil), [
            "exiftool: /opt/homebrew/bin/exiftool",
            "dnglab: /opt/homebrew/bin/dnglab",
            "Adobe DNG Converter: not installed",
            "Adobe DNG Converter is not installed. It is an optional backup for photos that dnglab cannot match.",
        ])
    }

    func testWithAdobeAloneAScanSaysThatDnglabIsFaster() {
        XCTAssertEqual(tools(dnglab: nil, converter: Self.adobe), [
            "exiftool: /opt/homebrew/bin/exiftool",
            "dnglab: not installed",
            "Adobe DNG Converter: \(Self.adobe)",
            "dnglab is faster and opens no window. Install it with: brew install dnglab",
        ])
    }

    // The scan says that the ARW files cannot be converted, then what to do
    // about it. Before, the two "not installed" lines and the install line
    // never said that the ARW files wait.
    func testWithNeitherConverterAScanSaysThatTheARWFilesCannotConvertThenGivesTheInstallCommand() {
        XCTAssertEqual(tools(arws: ["b.ARW", "c.ARW"], dnglab: nil, converter: nil), [
            "exiftool: /opt/homebrew/bin/exiftool",
            "dnglab: not installed",
            "Adobe DNG Converter: not installed",
            "2 ARW cannot be converted: no converter is installed",
            "Install dnglab with: brew install dnglab",
        ])
    }

    // With no ARW pending, the ARW files are not the topic: no sentence, no
    // advice. Nor does one converter make the sentence true.
    func testTheSentenceAboutARWFilesThatCannotConvertNeedsAPendingARWAndNeitherConverter() {
        XCTAssertEqual(tools(arws: [], dnglab: nil, converter: nil), [
            "exiftool: /opt/homebrew/bin/exiftool", "dnglab: not installed", "Adobe DNG Converter: not installed",
        ])
        XCTAssertFalse(tools(dnglab: nil, converter: Self.adobe).joined().contains("cannot be converted"))
        XCTAssertFalse(tools(dnglab: "/opt/homebrew/bin/dnglab", converter: nil).joined().contains("cannot be converted"))
    }

    // The advice is the core's line, so the window says the same words. With
    // no pending ARW there is none, in every state.
    func testTheAdviceOfAScanIsTheLineOfTheCoreAndNeedsAPendingARW() {
        for (dnglab, converter) in [("/opt/homebrew/bin/dnglab", nil), (nil, Self.adobe), (nil, nil)] as [(String?, String?)] {
            let report = scan(arws: ["b.ARW"], dnglab: dnglab, converter: converter)
            XCTAssertEqual(TextOutput.scan(report).last, report.converterAdvice)
            XCTAssertNotNil(report.converterAdvice)
            XCTAssertEqual(tools(arws: [], dnglab: dnglab, converter: converter).count, 3,
                           "three tools and no advice")
        }
    }

    func testAScanOfAnEmptyFolderSaysSo() {
        XCTAssertEqual(Array(TextOutput.scan(scan()).prefix(4)), [
            "/Volumes/Card/Shoot 1",
            "",
            "No DNG or ARW files in this folder.",
            "",
        ])
    }

    // The orphan is the only thing in the folder. It must not be lost behind
    // an "empty folder" line.
    func testAScanOfAFolderWithOnlyAnOrphanBackupReportsIt() {
        XCTAssertEqual(Array(TextOutput.scan(scan(orphans: ["lost.dng_original"])).prefix(7)), [
            "/Volumes/Card/Shoot 1",
            "",
            "DNG files: 0",
            "",
            "ARW files with no DNG: 0",
            "",
            "lost.dng_original: A backup with no DNG beside it. Rename it to lost.dng to get the photo back.",
        ])
    }

    // The messages are the core's, in the core's order, so the window and the
    // tool say the same words. The tool prints a list: it names every orphan.
    func testTheMessagesOfAScanAreTheMessagesOfTheCoreWithEveryOrphanNamed() {
        let orphans = (1...7).map { "lost\($0).dng_original" }
        let lines = TextOutput.scan(scan(orphans: orphans, writable: false))
        let messages = FolderText.messages(isWritable: false, orphanBackups: orphans, namedOrphanLimit: nil)
        XCTAssertEqual(messages.count, 8)
        XCTAssertEqual(Array(lines.dropFirst(6).prefix(8)), messages)
        XCTAssertFalse(lines.contains { $0.hasSuffix("more") })
    }

    // MARK: A run

    func summary(_ change: (inout RunSummary) -> Void) -> RunSummary {
        var summary = RunSummary()
        change(&summary)
        return summary
    }

    func testARunShowsTheLineOfTheWindowThenOneLineForEachNote() {
        let report = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, summary: summary {
            $0.convertedByAdobe = 1
            $0.set = 3
            $0.notes = [
                .orphanBackup(named: "lost.dng_original"),
                FileNote(name: "x.dng", kind: .failed,
                         message: "The change failed, and the backup could not be restored. The backup is x.dng_original.",
                         detail: "The tag did not read back as 1.5 1.\nRestore: The volume refused the rename."),
            ]
        })
        XCTAssertEqual(TextOutput.run(report, converterInstalled: true), [
            "1 converted · 3 set · 0 skipped · 0 failed",
            "lost.dng_original: A backup with no DNG beside it. Rename it to lost.dng to get the photo back.",
            "x.dng: The change failed, and the backup could not be restored. The backup is x.dng_original.",
            "    The tag did not read back as 1.5 1.",
            "    Restore: The volume refused the rename.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])
    }

    func testARunShowsBlockedAndStoppedWhenTheyApply() {
        let report = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, summary: summary {
            $0.skipped = 2
            $0.blocked = 1
            $0.cancelled = true
        })
        XCTAssertEqual(TextOutput.run(report, converterInstalled: true),
                       ["0 set · 2 skipped · 1 blocked · 0 failed · stopped"])
    }

    func testARunSaysHowManyARWFilesItLeftAndWhyWhenTheConverterIsMissing() {
        let one = RunReport(folder: folder, factor: SqueezeFactor(2)!, summary: summary { $0.unconvertedARWs = 1 })
        XCTAssertEqual(TextOutput.run(one, converterInstalled: true),
                       ["0 set · 0 skipped · 0 failed", "1 ARW file was not converted."])
        let many = RunReport(folder: folder, factor: SqueezeFactor(2)!, summary: summary { $0.unconvertedARWs = 12 })
        XCTAssertEqual(TextOutput.run(many, converterInstalled: false), [
            "0 set · 0 skipped · 0 failed",
            "12 ARW files were not converted. No converter is installed.",
        ])
    }

    // A DNG with no full match has a note as every other file has: the
    // line, then the reason below it. Its sentences are the core's.
    func testARunShowsTheNoteOfADNGWithNoFullMatch() {
        let report = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, summary: summary {
            $0.convertedByDnglab = 1
            $0.set = 1
            $0.notes = [FileNote(
                name: "frame.dng", kind: .convertedUnmatched,
                message: "Converted. The DNG has no built-in lens correction. "
                    + "Install Adobe DNG Converter for the same file that Lightroom makes.",
                detail: "The ARW holds lens-correction data, and dnglab does not write it into the DNG.")]
        })
        XCTAssertEqual(TextOutput.run(report, converterInstalled: true), [
            "1 converted · 1 set · 0 skipped · 0 failed",
            "frame.dng: Converted. The DNG has no built-in lens correction. "
                + "Install Adobe DNG Converter for the same file that Lightroom makes.",
            "    The ARW holds lens-correction data, and dnglab does not write it into the DNG.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])
    }

    // A run on a volume that gives no folder lock has one note more, on the
    // name of the folder (design 13.9). It is a line as every other note,
    // and the first one. The sentence is the core's.
    func testARunShowsTheNoteOfAVolumeWithNoFolderLock() {
        let report = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, summary: summary {
            $0.set = 2
            $0.notes = [FileNote(
                name: "Shoot 1", kind: .noFolderLock,
                message: "This volume gives no folder lock. Do not start a second run in this folder while "
                    + "this run works.",
                detail: nil)]
        })
        XCTAssertEqual(TextOutput.run(report, converterInstalled: true), [
            "2 set · 0 skipped · 0 failed",
            "Shoot 1: This volume gives no folder lock. Do not start a second run in this folder while this "
                + "run works.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])
    }

    func testADryRunShowsEachStepThenTheResultOfThatRun() {
        let plan = RunPlan(
            steps: [RunPlan.Step(name: "frame.ARW", action: .convert, converter: .dnglab),
                    RunPlan.Step(name: "a.dng", action: .write),
                    RunPlan.Step(name: "c.dng", action: .skip), RunPlan.Step(name: "d.dng", action: .blocked),
                    RunPlan.Step(name: "frame.dng", action: .write)],
            summary: summary {
                $0.convertedByDnglab = 1
                $0.set = 2
                $0.skipped = 1
                $0.blocked = 1
                $0.unconvertedARWs = 2
                $0.notes = [.orphanBackup(named: "lost.dng_original")]
            })
        let report = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, plan: plan)
        XCTAssertEqual(TextOutput.run(report, converterInstalled: true), [
            "Dry run. No file was changed.",
            "  convert  frame.ARW  with dnglab",
            "  write    a.dng",
            "  skip     c.dng",
            "  blocked  d.dng",
            "  write    frame.dng",
            "A run would give: 1 converted · 2 set · 1 skipped · 1 blocked · 0 failed",
            "lost.dng_original: A backup with no DNG beside it. Rename it to lost.dng to get the photo back.",
            "2 ARW files would not be converted.",
        ])
    }

    // A convert step names the converter that gets the ARW first.
    func testADryRunNamesTheConverterOfEachConvertStep() {
        let plan = RunPlan(
            steps: [RunPlan.Step(name: "frame.ARW", action: .convert, converter: .dnglab),
                    RunPlan.Step(name: "lens.ARW", action: .convert, converter: .adobe),
                    RunPlan.Step(name: "frame.dng", action: .write), RunPlan.Step(name: "lens.dng", action: .write)],
            summary: summary {
                $0.convertedByDnglab = 1
                $0.convertedByAdobe = 1
                $0.set = 2
            })
        let report = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, plan: plan)
        XCTAssertEqual(TextOutput.run(report, converterInstalled: true), [
            "Dry run. No file was changed.",
            "  convert  frame.ARW  with dnglab",
            "  convert  lens.ARW  with Adobe DNG Converter",
            "  write    frame.dng",
            "  write    lens.dng",
            "A run would give: 2 converted · 2 set · 0 skipped · 0 failed",
        ])
    }

    // When both converters did work, one line after the counts says how
    // many each converted.
    func testARunInWhichBothConvertersWorkedSaysSoAfterTheCounts() {
        let report = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, summary: summary {
            $0.convertedByDnglab = 11
            $0.convertedByAdobe = 1
            $0.set = 12
            $0.unconvertedARWs = 1
            $0.notes = [.orphanBackup(named: "lost.dng_original")]
        })
        XCTAssertEqual(TextOutput.run(report, converterInstalled: true), [
            "12 converted · 12 set · 0 skipped · 0 failed",
            "Converted with dnglab: 11. With Adobe DNG Converter: 1.",
            "lost.dng_original: A backup with no DNG beside it. Rename it to lost.dng to get the photo back.",
            "1 ARW file was not converted.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])
    }

    func testARunInWhichOneConverterWorkedHasNoLineAboutTheConverters() {
        for (dnglab, adobe) in [(12, 0), (0, 12)] {
            let report = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, summary: summary {
                $0.convertedByDnglab = dnglab
                $0.convertedByAdobe = adobe
                $0.set = 12
            })
            XCTAssertEqual(TextOutput.run(report, converterInstalled: true), [
                "12 converted · 12 set · 0 skipped · 0 failed",
                "Photos already in Lightroom: Metadata › Read Metadata from File.",
            ])
        }
    }

    // The sentence is made once, in `FolderText`.
    func testARunOnAnEmptyFolderSaysSoInPlaceOfTheCounts() {
        var empty = RunSummary()
        empty.folderIsEmpty = true
        let report = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, summary: empty)
        XCTAssertEqual(TextOutput.run(report, converterInstalled: true), [FolderText.noPhotos])
        XCTAssertEqual(FolderText.noPhotos, "No DNG or ARW files in this folder.")

        let dry = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, plan: RunPlan(steps: [], summary: empty))
        XCTAssertEqual(TextOutput.run(dry, converterInstalled: true), ["Dry run. No file was changed.", FolderText.noPhotos])
    }

    func testADryRunWithNoStepHasNoStepLine() {
        let report = RunReport(folder: folder, factor: .noStretch, plan: RunPlan(steps: [], summary: RunSummary()))
        XCTAssertEqual(TextOutput.run(report, converterInstalled: false),
                       ["Dry run. No file was changed.", "A run would give: 0 set · 0 skipped · 0 failed"])
    }
}
