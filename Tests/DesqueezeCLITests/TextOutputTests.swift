import DesqueezeCore
import XCTest
@testable import DesqueezeCLI

/// The text a person reads. Each test holds the whole output.
final class TextOutputTests: XCTestCase {
    let folder = URL(fileURLWithPath: "/Volumes/Card/Shoot 1")

    func scan(dngs: [ScanReport.DNG] = [], arws: [String] = [], orphans: [String] = [], writable: Bool = true,
              converter: String? = "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter")
        -> ScanReport {
        ScanReport(folder: folder.path, writable: writable, exiftool: "/opt/homebrew/bin/exiftool",
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
            "Adobe DNG Converter: /Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter",
        ])
    }

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
            "Adobe DNG Converter: not installed. ARW files cannot be converted.",
        ])
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
            $0.converted = 1
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
            "12 ARW files were not converted. Adobe DNG Converter is not installed.",
        ])
    }

    func testADryRunShowsEachStepThenTheResultOfThatRun() {
        let plan = RunPlan(
            steps: [RunPlan.Step(name: "frame.ARW", action: .convert), RunPlan.Step(name: "a.dng", action: .write),
                    RunPlan.Step(name: "c.dng", action: .skip), RunPlan.Step(name: "d.dng", action: .blocked),
                    RunPlan.Step(name: "frame.dng", action: .write)],
            summary: summary {
                $0.converted = 1
                $0.set = 2
                $0.skipped = 1
                $0.blocked = 1
                $0.unconvertedARWs = 2
                $0.notes = [.orphanBackup(named: "lost.dng_original")]
            })
        let report = RunReport(folder: folder, factor: SqueezeFactor(1.5)!, plan: plan)
        XCTAssertEqual(TextOutput.run(report, converterInstalled: true), [
            "Dry run. No file was changed.",
            "  convert  frame.ARW",
            "  write    a.dng",
            "  skip     c.dng",
            "  blocked  d.dng",
            "  write    frame.dng",
            "A run would give: 1 converted · 2 set · 1 skipped · 1 blocked · 0 failed",
            "lost.dng_original: A backup with no DNG beside it. Rename it to lost.dng to get the photo back.",
            "2 ARW files would not be converted.",
        ])
    }

    func testADryRunWithNoStepHasNoStepLine() {
        let report = RunReport(folder: folder, factor: .noStretch, plan: RunPlan(steps: [], summary: RunSummary()))
        XCTAssertEqual(TextOutput.run(report, converterInstalled: false),
                       ["Dry run. No file was changed.", "A run would give: 0 set · 0 skipped · 0 failed"])
    }
}
