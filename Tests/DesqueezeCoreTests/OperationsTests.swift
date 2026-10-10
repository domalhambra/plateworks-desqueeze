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

    var scripts: [URL] = []

    override func tearDown() {
        removeTemporaryFolder(shoot)
        scripts.forEach(removeTemporaryFolder)
    }

    let dnglabTool = URL(fileURLWithPath: "/opt/homebrew/bin/dnglab")

    /// As on a Mac with Adobe DNG Converter alone, unless the test says so.
    func operations(withConverter: Bool = true, withDnglab: Bool = false) -> DesqueezeOperations {
        DesqueezeOperations(exiftool: exiftool, dnglab: withDnglab ? dnglabTool : nil,
                            dngConverter: withConverter ? converterTool : nil, tag: h.tag,
                            converters: h.converters(withConverter: withConverter, withDnglab: withDnglab),
                            backups: h.backups)
    }

    func testScanReportsTheFolderAndTheThreeToolsAndChangesNothing() throws {
        let report = try operations(withDnglab: true).scan(shoot)
        XCTAssertEqual(report, ScanReport(
            folder: shoot.path, writable: true, exiftool: exiftool.path, dnglab: dnglabTool.path,
            dngConverter: converterTool.path,
            dngs: [.init(name: "A.dng", scale: "1 1", originalRawFileName: nil, hasBackup: false),
                   .init(name: "B.dng", scale: "1.5 1", originalRawFileName: "B.ARW", hasBackup: false)],
            pendingARWs: ["X.ARW"], orphanBackups: ["gone.dng_original"]))
        XCTAssertEqual(h.log.entries, ["readFolder"], "a scan does not read the ARW facts")
        XCTAssertNil(try operations(withConverter: false, withDnglab: true).scan(shoot).dngConverter)
        XCTAssertNil(try operations().scan(shoot).dnglab)
        XCTAssertEqual(try operations().scan(shoot).dngConverter, converterTool.path)
    }

    // "ARW files that can convert" is true when either converter is installed.
    func testAnARWCanConvertWhenOneConverterOrTheOtherIsInstalled() {
        XCTAssertTrue(operations(withConverter: true, withDnglab: true).canConvert)
        XCTAssertTrue(operations(withConverter: false, withDnglab: true).canConvert)
        XCTAssertTrue(operations(withConverter: true, withDnglab: false).canConvert)
        XCTAssertFalse(operations(withConverter: false, withDnglab: false).canConvert)
        XCTAssertTrue(h.converters(withConverter: false, withDnglab: true).canConvert)
        XCTAssertFalse(h.converters(withConverter: false, withDnglab: false).canConvert)
        XCTAssertFalse(RawConverters.none.canConvert)
    }

    // One source: the converters that the job runs. The two paths are for
    // the report, and do not decide what can convert.
    func testWhatCanConvertIsAskedOfTheConvertersThatTheJobRuns() {
        func operations(paths: Bool, converters: RawConverters) -> DesqueezeOperations {
            DesqueezeOperations(exiftool: exiftool, dnglab: paths ? dnglabTool : nil,
                                dngConverter: paths ? converterTool : nil, tag: h.tag, converters: converters,
                                backups: h.backups)
        }
        XCTAssertTrue(operations(paths: false, converters: h.converters(withConverter: true)).canConvert)
        XCTAssertTrue(operations(paths: false, converters: h.converters(withConverter: false, withDnglab: true))
            .canConvert)
        XCTAssertFalse(operations(paths: true, converters: .none).canConvert)
    }

    // The same choice in the run and in the dry run, through the entry points.
    func testWithBothConvertersAFullMatchGoesToDnglabInTheRunAndInTheDryRun() throws {
        h.facts.facts = ["X.ARW": .adapted]
        let dry = try operations(withDnglab: true).run(shoot, factor: factor, trashOriginals: false, dryRun: true)
        XCTAssertEqual(h.log.entries, ["readFolder", "facts X.ARW"], "two reads, and no converter")
        XCTAssertEqual(dry.steps?.first, RunPlan.Step(name: "X.ARW", action: .convert, converter: .dnglab))
        XCTAssertEqual([dry.converted, dry.convertedByDnglab, dry.convertedByAdobe], [1, 1, 0])

        h.log.entries = []
        let real = try operations(withDnglab: true).run(shoot, factor: factor, trashOriginals: false)
        XCTAssertEqual(Array(h.log.entries.prefix(3)), ["readFolder", "facts X.ARW", "dnglab X.ARW"])
        XCTAssertFalse(h.log.entries.contains("convert X.ARW"), "Adobe DNG Converter is not started")
        XCTAssertEqual([real.converted, real.convertedByDnglab, real.convertedByAdobe], [1, 1, 0])
        XCTAssertEqual(real.notes, dry.notes)
    }

    func testRunDoesTheRunAndReportsIt() throws {
        let report = try operations().run(shoot, factor: factor, trashOriginals: false)
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
        let dry = try operations().run(shoot, factor: factor, trashOriginals: false, dryRun: true)
        XCTAssertEqual(h.log.entries, ["readFolder"], "no conversion, no write, no backup moved")
        XCTAssertTrue(dry.dryRun)
        XCTAssertEqual(dry.steps, [
            RunPlan.Step(name: "X.ARW", action: .convert, converter: .adobe),
            RunPlan.Step(name: "A.dng", action: .write),
            RunPlan.Step(name: "B.dng", action: .skip), RunPlan.Step(name: "X.dng", action: .write),
        ])

        let real = try operations().run(shoot, factor: factor, trashOriginals: false)
        XCTAssertEqual(RunReport(folder: shoot, factor: factor, summary: RunSummary()).dryRun, real.dryRun)
        XCTAssertEqual([dry.converted, dry.set, dry.skipped, dry.blocked, dry.failed, dry.unconvertedARWs],
                       [real.converted, real.set, real.skipped, real.blocked, real.failed, real.unconvertedARWs])
        XCTAssertEqual(dry.notes, real.notes)
    }

    func testRunWithNoConvertOrNoConverterLeavesTheARWAndSaysHowMany() throws {
        let told = try operations().run(shoot, factor: factor, convert: false, trashOriginals: false)
        XCTAssertEqual(told.converted, 0)
        XCTAssertEqual(told.unconvertedARWs, 1)
        XCTAssertFalse(h.log.entries.contains("convert X.ARW"))

        let missing = try operations(withConverter: false).run(shoot,
                                                               factor: factor, trashOriginals: false, dryRun: true)
        XCTAssertEqual(missing.unconvertedARWs, 1)
        XCTAssertEqual(missing.steps?.map(\.action).contains(.convert), false)
    }

    // Remove is an intent, not a guess from the arguments (design 12.1).
    // `run` at factor 1 with no conversion is not Remove: it reports the ARW
    // files it left. Only `remove` leaves that line out.
    func testRunAtFactorOneWithNoConvertReportsTheARWFilesAndRemoveDoesNot() throws {
        let one = SqueezeFactor.noStretch
        let run = try operations().run(shoot, factor: one, convert: false, trashOriginals: false)
        XCTAssertEqual(run.unconvertedARWs, 1)
        XCTAssertEqual(run.converted, 0)

        let dryRun = try operations().run(shoot, factor: one, convert: false, trashOriginals: false, dryRun: true)
        XCTAssertEqual(dryRun.unconvertedARWs, 1)

        h.log.entries = []
        let remove = try operations().remove(shoot)
        XCTAssertEqual(remove.unconvertedARWs, 0)
        XCTAssertEqual(try operations().remove(shoot, dryRun: true).unconvertedARWs, 0)
        XCTAssertEqual(remove.factor, run.factor, "the two differ in their intent only")
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
        let stopped = try operations().run(shoot, factor: factor,
                                           trashOriginals: false, cancel: flag) { names.append($0.name) }
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
        XCTAssertThrowsError(try operations().run(missing, factor: factor, trashOriginals: false))
        XCTAssertThrowsError(try operations().run(missing, factor: factor, trashOriginals: false, dryRun: true))
        XCTAssertThrowsError(try operations().remove(missing))
        XCTAssertThrowsError(try operations().remove(missing, dryRun: true))
        XCTAssertEqual(h.log.entries, [])
    }

    // MARK: A program that a signal ended

    /// A shell script that stands in for a tool. The real runner starts it.
    func script(_ body: String) throws -> URL {
        let folder = try makeTemporaryFolder(named: "tools")
        scripts.append(folder)
        let file = folder.appendingPathComponent("tool.sh")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    func testAnExiftoolThatASignalEndedMakesTheFileFailedWithTheSignalInTheDetail() throws {
        // It reads the folder, and is ended at the first write.
        let fake = try script(#"case "$*" in *" -T "*) printf 'A.dng\t1 1\t-\n';; *) kill -TERM $$;; esac"#)
        let operations = DesqueezeOperations(exiftool: fake, dnglab: nil, dngConverter: nil, backups: h.backups)
        let report = try operations.run(shoot, factor: factor, trashOriginals: false)
        XCTAssertEqual(report.failed, 2, "A.dng, and B.dng whose scale the script does not give")
        XCTAssertEqual(report.set, 0)
        let note = try XCTUnwrap(report.notes.first { $0.kind == .failed && $0.name == "A.dng" })
        XCTAssertEqual(note.message, "Not changed.")
        XCTAssertEqual(note.detail, "The program was ended by signal 15.")
        XCTAssertFalse(h.log.entries.contains("trash A.dng"), "a file that failed discards no backup")
    }

    func testAConverterThatASignalEndedMakesTheARWNotConvertedWithTheSignalInTheDetail() throws {
        let fake = try script("kill -TERM $$")
        let operations = DesqueezeOperations(
            exiftool: exiftool, dnglab: nil, dngConverter: fake, tag: h.tag,
            converters: RawConverters(dnglab: nil, adobe: AdobeConverter(executable: fake, discardLeftover: { _ in }), facts: nil),
            backups: h.backups)
        let report = try operations.run(shoot, factor: factor, trashOriginals: false)
        let note = try XCTUnwrap(report.notes.first { $0.kind == .notConverted })
        XCTAssertEqual(note.name, "X.ARW")
        XCTAssertEqual(note.detail, "The program was ended by signal 15.")
        XCTAssertEqual(report.unconvertedARWs, 1)
    }

    // dnglab is ended by a signal, and there is no Adobe DNG Converter: the
    // ARW failed, with dnglab's line.
    func testADnglabThatASignalEndedMakesTheARWNotConvertedWithTheSignalInTheDetail() throws {
        let fake = try script("kill -TERM $$")
        let operations = DesqueezeOperations(
            exiftool: exiftool, dnglab: fake, dngConverter: nil, tag: h.tag,
            converters: RawConverters(
                dnglab: DnglabConverter(executable: fake, exiftool: exiftool, discardLeftover: { _ in }), adobe: nil,
                facts: h.facts),
            backups: h.backups)
        let report = try operations.run(shoot, factor: factor, trashOriginals: false)
        let note = try XCTUnwrap(report.notes.first { $0.kind == .notConverted })
        XCTAssertEqual(note.name, "X.ARW")
        XCTAssertEqual(note.detail, "The program was ended by signal 15.")
        XCTAssertEqual([report.converted, report.failed, report.unconvertedARWs], [0, 1, 1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: shoot.appendingPathComponent("X.dng").path))
    }

    // MARK: A volume that gives no folder lock (design 13.9)

    /// The operations on the harness's fakes, on a lock that answers
    /// `code`, and with a sink for `--verbose`.
    func operations(lockAnswers code: Int32, verbose: @escaping @Sendable (String) -> Void = { _ in })
        -> DesqueezeOperations {
        let system = FakeLockCalls()
        system.lockCode = code
        return DesqueezeOperations(exiftool: exiftool, dnglab: nil, dngConverter: converterTool, tag: h.tag,
                                   converters: h.converters(), backups: h.backups, lock: system.lock,
                                   verbose: verbose)
    }

    // The command line tool and the MCP server print this report. The note
    // is in it with its kind, the counts are those of a good run, and the
    // sink of `--verbose` gets the number of the error.
    func testOnAVolumeWithNoFolderLockTheReportHasTheNoteAndVerboseHasTheErrorNumber() throws {
        let lines = CallLog()
        let report = try operations(lockAnswers: ENOTSUP, verbose: { lines.entries.append($0) })
            .run(shoot, factor: factor, trashOriginals: false)
        XCTAssertEqual([report.converted, report.set, report.skipped, report.blocked, report.failed], [1, 2, 1, 0, 0])
        XCTAssertEqual(report.notes.first, FileNote(
            name: shoot.lastPathComponent, kind: .noFolderLock, message: FolderLockTests.noLockSentence, detail: nil))
        XCTAssertEqual(report.notes.map(\.kind), [.noFolderLock, .orphanBackup])
        XCTAssertEqual(lines.entries, ["The volume gave no folder lock: error 45, Operation not supported"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try ReportJSON.text(report).utf8))
            as? [String: Any])
        let first = try XCTUnwrap((json["notes"] as? [NSDictionary])?.first)
        XCTAssertEqual(first["kind"] as? String, "noFolderLock")
        XCTAssertEqual(first["name"] as? String, shoot.lastPathComponent)
        XCTAssertEqual(first["message"] as? String, FolderLockTests.noLockSentence)
        XCTAssertTrue(first["detail"] is NSNull)

        // Remove says the same, and a dry run takes no lock and says nothing.
        XCTAssertEqual(try operations(lockAnswers: ENOTSUP).remove(shoot).notes.first?.kind, .noFolderLock)
        XCTAssertEqual(try operations(lockAnswers: ENOTSUP).run(shoot, factor: factor, trashOriginals: false,
                                                                dryRun: true).notes.map(\.kind), [.orphanBackup])
    }

    // A lock call that failed gives no report: the operation throws, with
    // the system's words, and each front end says that the folder could not
    // be read.
    func testALockCallThatFailedGivesNoReport() {
        XCTAssertThrowsError(try operations(lockAnswers: EIO).run(shoot, factor: factor, trashOriginals: false)) {
            XCTAssertEqual($0.localizedDescription, "Input/output error")
        }
        XCTAssertThrowsError(try operations(lockAnswers: EIO).remove(shoot))
        XCTAssertEqual(h.log.entries, [], "no file was read")
    }

    // The public way in: one runner starts every program, also dnglab and
    // the exiftool calls of its match. So `--verbose` shows them all.
    func testWithDnglabEveryProgramIsStartedThroughTheGivenRunner() throws {
        let runner = FakeRunner()
        let shoot = shoot!
        var written: [String] = []
        runner.handler = { call in
            func ok(_ text: String) -> ProcessResult { ProcessResult(exitCode: 0, stdout: text, stderr: "") }
            if call.executable == "/opt/homebrew/bin/dnglab" {
                FileManager.default.createFile(atPath: call.arguments.last!, contents: Data("a DNG".utf8))
                return ok("")
            }
            if call.arguments.contains("-ext") { return ok("A.dng\t1.5 1\t-\nB.dng\t1.5 1\t-\n") }
            if call.arguments.contains("-IFD0:Model") { return ok("X.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\t2\n") }
            if call.arguments.contains("-overwrite_original") {
                written = call.arguments.filter { $0.contains("=") }
                    .map { String($0[$0.index(after: $0.firstIndex(of: "=")!)...]) }
                return ok("    1 image files updated\n")
            }
            if call.arguments.contains("-T") { return ok(written.joined(separator: "\t") + "\n") }
            if call.arguments.first == "-s3" { return ok("1.5 1\n") }
            return ok("    1 image files updated\n")
        }
        let operations = DesqueezeOperations(exiftool: exiftool, dnglab: dnglabTool, dngConverter: converterTool,
                                             runner: runner, backups: h.backups)
        let report = try operations.run(shoot, factor: factor, trashOriginals: false)

        XCTAssertEqual(runner.calls.map { URL(fileURLWithPath: $0.executable).lastPathComponent }, [
            "exiftool",             // the scan
            "exiftool",             // the ARW facts
            "dnglab",               // the conversion
            "exiftool", "exiftool", // the match: the write, then the read-back
            "exiftool", "exiftool", // X.dng: the scale, then its check
        ])
        guard runner.calls.count == 7 else { return XCTFail("\(runner.calls.count) calls, not 7") }
        XCTAssertEqual(runner.calls[2].arguments.map { URL(fileURLWithPath: $0).lastPathComponent },
                       ["convert", "--embed-raw", "false", "X.ARW", ".X.desqueeze-work.dng"])
        XCTAssertEqual(runner.calls[3].arguments.last.map { URL(fileURLWithPath: $0).lastPathComponent },
                       ".X.desqueeze-work.dng", "the match goes into the work file")
        XCTAssertEqual(runner.calls[5].arguments.last.map { URL(fileURLWithPath: $0).lastPathComponent }, "X.dng",
                       "the scale goes into the DNG, after the rename")
        XCTAssertFalse(runner.calls.contains { $0.executable == converterTool.path },
                       "a full match does not start Adobe DNG Converter")
        XCTAssertEqual([report.converted, report.convertedByDnglab, report.convertedByAdobe], [1, 1, 0])
        XCTAssertEqual([report.set, report.skipped, report.failed], [1, 2, 0])
        XCTAssertEqual(report.notes.map(\.kind), [.orphanBackup])
        XCTAssertEqual(try Data(contentsOf: shoot.appendingPathComponent("X.dng")), Data("a DNG".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: shoot.path).contains { $0.hasPrefix(".") },
                       "no work file stays")
    }

    // The public way in: one runner starts both tools.
    func testTheToolsAreStartedThroughTheGivenRunner() throws {
        let runner = FakeRunner()
        runner.handler = { call in
            ProcessResult(exitCode: 0, stdout: call.arguments.contains("-T") ? "A.dng\t1.5 1\t-\nB.dng\t1.5 1\t-\n" : "",
                          stderr: "")
        }
        let operations = DesqueezeOperations(exiftool: exiftool, dnglab: nil, dngConverter: converterTool,
                                             runner: runner, backups: h.backups)
        let report = try operations.run(shoot, factor: factor, trashOriginals: false)
        XCTAssertEqual(runner.calls.map(\.executable), [exiftool.path, converterTool.path])
        // The scan gives each file's path with its links resolved, so the names are compared.
        XCTAssertEqual(runner.calls.last?.arguments.map { URL(fileURLWithPath: $0).lastPathComponent },
                       ["-c", "-d", "Shoot 1", "-o", ".X.desqueeze-work.dng", "X.ARW"])
        XCTAssertEqual(report.skipped, 2)
        XCTAssertEqual(report.failed, 1, "the fake converter made no DNG")
        XCTAssertEqual(report.notes.map(\.kind), [.orphanBackup, .notConverted])
    }
}
