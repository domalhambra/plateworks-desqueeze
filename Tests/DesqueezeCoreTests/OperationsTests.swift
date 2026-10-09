import XCTest
@testable import DesqueezeCore

/// The entry points that the command line tool and the MCP server share.
final class OperationsTests: XCTestCase {
    let exiftool = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool")
    let converterTool = URL(fileURLWithPath: "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter")
    let factor = SqueezeFactor(1.5)!
    var h: JobHarness!
    var shoot: URL!

    override func setUpWithError() throws {
        h = JobHarness()
        shoot = try makeTemporaryFolder()
        for name in ["A.dng", "B.dng", "X.ARW", "gone.dng_original"] {
            try Data(name.utf8).write(to: shoot.appendingPathComponent(name))
        }
        h.tag.rows = [
            TagRow(fileName: "A.dng", scale: .noStretch, originalRawFileName: nil),
            TagRow(fileName: "B.dng", scale: Scale(horizontal: 1.5, vertical: 1), originalRawFileName: "B.ARW"),
        ]
    }

    override func tearDown() { removeTemporaryFolder(shoot) }

    func operations(withConverter: Bool = true) -> DesqueezeOperations {
        DesqueezeOperations(exiftool: exiftool, dngConverter: withConverter ? converterTool : nil,
                            tag: h.tag, converter: withConverter ? h.converter : nil, backups: h.backups)
    }

    func testScanReportsTheFolderAndTheTwoToolsAndChangesNothing() throws {
        let report = try operations().scan(shoot)
        XCTAssertEqual(report, ScanReport(
            folder: shoot.path, writable: true, exiftool: exiftool.path, dngConverter: converterTool.path,
            dngs: [.init(name: "A.dng", scale: "1 1", originalRawFileName: nil, hasBackup: false),
                   .init(name: "B.dng", scale: "1.5 1", originalRawFileName: "B.ARW", hasBackup: false)],
            pendingARWs: ["X.ARW"], orphanBackups: ["gone.dng_original"]))
        XCTAssertEqual(h.log.entries, ["readFolder"])
        XCTAssertNil(try operations(withConverter: false).scan(shoot).dngConverter)
    }

    func testRunDoesTheRunAndReportsIt() throws {
        let report = try operations().run(shoot, factor: factor)
        XCTAssertEqual(h.log.entries, [
            "readFolder", "convert X.ARW",
            "write 1.5 1 A.dng", "read A.dng", "trash A.dng",
            "write 1.5 1 X.dng", "read X.dng", "trash X.dng",
        ])
        XCTAssertEqual(report.folder, shoot.path)
        XCTAssertEqual(report.factor, "1.5")
        XCTAssertFalse(report.dryRun)
        XCTAssertNil(report.steps)
        XCTAssertEqual([report.converted, report.set, report.skipped, report.blocked, report.failed], [1, 2, 1, 0, 0])
        XCTAssertEqual(report.unconvertedARWs, 0)
        XCTAssertEqual(report.notes.map(\.kind), [.orphanBackup])
    }

    func testADryRunChangesNothingAndGivesTheCountsOfTheRunThatFollows() throws {
        let dry = try operations().run(shoot, factor: factor, dryRun: true)
        XCTAssertEqual(h.log.entries, ["readFolder"], "no conversion, no write, no backup moved")
        XCTAssertTrue(dry.dryRun)
        XCTAssertEqual(dry.steps, [
            RunPlan.Step(name: "X.ARW", action: .convert), RunPlan.Step(name: "A.dng", action: .write),
            RunPlan.Step(name: "B.dng", action: .skip), RunPlan.Step(name: "X.dng", action: .write),
        ])

        let real = try operations().run(shoot, factor: factor)
        XCTAssertEqual(RunReport(folder: shoot, factor: factor, summary: RunSummary()).dryRun, real.dryRun)
        XCTAssertEqual([dry.converted, dry.set, dry.skipped, dry.blocked, dry.failed, dry.unconvertedARWs],
                       [real.converted, real.set, real.skipped, real.blocked, real.failed, real.unconvertedARWs])
        XCTAssertEqual(dry.notes, real.notes)
    }

    func testRunWithNoConvertOrNoConverterLeavesTheARWAndSaysHowMany() throws {
        let told = try operations().run(shoot, factor: factor, convert: false)
        XCTAssertEqual(told.converted, 0)
        XCTAssertEqual(told.unconvertedARWs, 1)
        XCTAssertFalse(h.log.entries.contains("convert X.ARW"))

        let missing = try operations(withConverter: false).run(shoot, factor: factor, dryRun: true)
        XCTAssertEqual(missing.unconvertedARWs, 1)
        XCTAssertEqual(missing.steps?.map(\.action).contains(.convert), false)
    }

    func testRemoveWritesNoStretchConvertsNothingAndReportsFactorOne() throws {
        let dry = try operations().remove(shoot, dryRun: true)
        XCTAssertEqual(h.log.entries, ["readFolder"])
        XCTAssertEqual(dry.steps, [RunPlan.Step(name: "A.dng", action: .skip),
                                   RunPlan.Step(name: "B.dng", action: .write)])
        XCTAssertEqual(dry.factor, "1")

        h.log.entries = []
        let report = try operations().remove(shoot)
        XCTAssertEqual(h.log.entries, ["readFolder", "write 1 1 B.dng", "read B.dng", "trash B.dng"])
        XCTAssertEqual(report.factor, "1")
        XCTAssertFalse(report.dryRun)
        XCTAssertEqual([report.converted, report.set, report.skipped], [0, 1, 1])
        XCTAssertEqual(report.unconvertedARWs, 0, "Remove has no ARW work")
    }

    func testRunAndRemovePassCancelAndProgressOn() throws {
        var names: [String] = []
        let flag = CancelFlag()
        h.converter.onConvert = { flag.cancel() }
        let stopped = try operations().run(shoot, factor: factor, cancel: flag) { names.append($0.name) }
        XCTAssertTrue(stopped.stopped)
        XCTAssertEqual(names, ["X.ARW"])
        XCTAssertEqual(stopped.converted, 1)
        XCTAssertEqual(stopped.set, 0)

        names = []
        let removed = try operations().remove(shoot, cancel: CancelFlag()) { names.append($0.name) }
        XCTAssertFalse(removed.stopped)
        XCTAssertEqual(names, ["A.dng", "B.dng"])
    }

    func testEachOperationThrowsWhenTheFolderCannotBeScanned() {
        let missing = shoot.appendingPathComponent("No such folder")
        XCTAssertThrowsError(try operations().scan(missing))
        XCTAssertThrowsError(try operations().run(missing, factor: factor))
        XCTAssertThrowsError(try operations().run(missing, factor: factor, dryRun: true))
        XCTAssertThrowsError(try operations().remove(missing))
        XCTAssertThrowsError(try operations().remove(missing, dryRun: true))
        XCTAssertEqual(h.log.entries, [])
    }

    // The public way in: one runner starts both tools.
    func testTheToolsAreStartedThroughTheGivenRunner() throws {
        let runner = FakeRunner()
        runner.handler = { call in
            ProcessResult(exitCode: 0, stdout: call.arguments.contains("-T") ? "A.dng\t1.5 1\t-\nB.dng\t1.5 1\t-\n" : "",
                          stderr: "")
        }
        let operations = DesqueezeOperations(exiftool: exiftool, dngConverter: converterTool, runner: runner,
                                             backups: h.backups)
        let report = try operations.run(shoot, factor: factor)
        XCTAssertEqual(runner.calls.map(\.executable), [exiftool.path, converterTool.path])
        // The scan gives each file's path with its links resolved, so the names are compared.
        XCTAssertEqual(runner.calls.last?.arguments.map { URL(fileURLWithPath: $0).lastPathComponent },
                       ["-c", "-d", "Shoot 1", "X.ARW"])
        XCTAssertEqual(report.skipped, 2)
        XCTAssertEqual(report.failed, 1, "the fake converter made no DNG")
        XCTAssertEqual(report.notes.map(\.kind), [.orphanBackup, .notConverted])
    }
}
