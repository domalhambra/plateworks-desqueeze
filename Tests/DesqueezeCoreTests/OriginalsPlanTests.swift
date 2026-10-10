import XCTest
@testable import DesqueezeCore

/// The dry run of a run that moves the originals (design 14.3), and the dry
/// run of an ARW whose name is too long (design 13.9). No disk, and no tool.
final class OriginalsPlanTests: XCTestCase {
    let factor = SqueezeFactor(1.5)!
    var h: JobHarness!

    override func setUp() { h = JobHarness() }

    func dryRun(_ snapshot: FolderSnapshot, trashOriginals: Bool = true, convert: Bool = true, remove: Bool = false,
                withConverter: Bool = true, withDnglab: Bool = false) -> RunPlan {
        h.job(withConverter: withConverter, withDnglab: withDnglab)
            .plan(snapshot, factor: factor, convert: convert, trashOriginals: trashOriginals, remove: remove)
    }

    func names(_ plan: RunPlan, _ action: RunPlan.Action) -> [String] {
        plan.steps.filter { $0.action == action }.map(\.name)
    }

    // MARK: The steps

    func testAPlanHasOneStepForEachOriginalAfterTheWriteSteps() {
        let state = h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"])
        let plan = dryRun(state)
        XCTAssertEqual(plan.steps, [
            RunPlan.Step(name: "X.ARW", action: .convert, converter: .adobe),
            RunPlan.Step(name: "Y.ARW", action: .convert, converter: .adobe),
            RunPlan.Step(name: "A.dng", action: .write),
            RunPlan.Step(name: "X.dng", action: .write),
            RunPlan.Step(name: "Y.dng", action: .write),
            RunPlan.Step(name: "X.ARW", action: .trashOriginal),
            RunPlan.Step(name: "Y.ARW", action: .trashOriginal),
        ])
        XCTAssertTrue(plan.summary.trashOriginals)
        XCTAssertEqual(plan.summary.originalsInTrash, 2, "the count that a run gives when every step passes")
        XCTAssertEqual(plan.summary.notes, [])
    }

    // The first break to try: the option is treated as on when it is off.
    func testWithTheOptionOffAPlanHasNoSuchStep() {
        let plan = dryRun(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"]), trashOriginals: false)
        XCTAssertEqual(names(plan, .trashOriginal), [])
        XCTAssertEqual(plan.steps.count, 5)
        XCTAssertFalse(plan.summary.trashOriginals)
        XCTAssertEqual(plan.summary.originalsInTrash, 0)
        XCTAssertEqual(plan.summary.notes, [])
    }

    // The plan knows which conversions get the `convertedUnmatched` note
    // (design 13.4), and gives those no such step.
    func testAConversionWithNoFullMatchGetsNoStepAndTheNoteOfTheRun() {
        h.facts.facts = ["full.ARW": .adapted, "lens.ARW": .lens]
        let plan = dryRun(h.snapshot(pending: ["full.ARW", "lens.ARW"]), withConverter: false, withDnglab: true)
        XCTAssertEqual(names(plan, .trashOriginal), ["full.ARW"])
        XCTAssertEqual(plan.summary.originalsInTrash, 1)
        XCTAssertEqual(plan.summary.notes, [
            .convertedUnmatched("lens.dng", rule: .noLensCorrection, facts: .lens),
            FileNote(name: "lens.ARW", kind: .originalKept,
                     message: "The original stays, because its DNG has no full match.", detail: nil),
        ])
    }

    // With both converters, Adobe DNG Converter gets the frame with no full
    // match: its DNG is complete, and the original moves.
    func testWithBothConvertersEveryConversionHasItsStep() {
        h.facts.facts = ["full.ARW": .adapted, "lens.ARW": .lens]
        let plan = dryRun(h.snapshot(pending: ["full.ARW", "lens.ARW"]), withDnglab: true)
        XCTAssertEqual(names(plan, .trashOriginal), ["full.ARW", "lens.ARW"])
        XCTAssertEqual(plan.summary.notes, [])
    }

    func testANewDNGThatWouldBeBlockedGetsNoStepForItsOriginal() {
        h.backups.existing = ["X.dng"]
        let plan = dryRun(h.snapshot(pending: ["X.ARW", "Y.ARW"]))
        XCTAssertEqual(names(plan, .trashOriginal), ["Y.ARW"])
        XCTAssertEqual(plan.summary.notes, [
            .blockedByBackup("X.dng"),
            FileNote(name: "X.ARW", kind: .originalKept,
                     message: "The original stays, because its DNG is not complete.", detail: nil),
        ])
    }

    // At factor 1 the new DNG is at the value already. Its tag step is a
    // skip, and the original still moves.
    func testAtFactorOneTheOriginalOfASkippedDNGHasItsStep() {
        let plan = h.job().plan(h.snapshot(pending: ["X.ARW"]), factor: .noStretch, convert: true,
                                trashOriginals: true)
        XCTAssertEqual(plan.steps.map(\.action), [.convert, .skip, .trashOriginal])
    }

    func testAPlanForRemoveHasNoSuchStepWhateverItIsGiven() {
        let state = h.snapshot(dngs: [h.dng("A.dng", at: 1.5)], pending: ["X.ARW"])
        let plan = dryRun(state, trashOriginals: true, convert: true, remove: true)
        XCTAssertEqual(plan.steps, [RunPlan.Step(name: "A.dng", action: .write)])
        XCTAssertFalse(plan.summary.trashOriginals)
        XCTAssertEqual(plan.summary.originalsInTrash, 0)
    }

    func testAPlanThatConvertsNothingHasNoSuchStep() {
        let state = h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW"])
        XCTAssertEqual(names(dryRun(state, convert: false), .trashOriginal), [])
        XCTAssertEqual(names(dryRun(state, withConverter: false), .trashOriginal), [])
        XCTAssertEqual(names(dryRun(h.snapshot(pending: ["X.ARW"], writable: false)), .trashOriginal), [])
    }

    // A plan asks the disk nothing about an ARW or a DNG, starts no check,
    // and moves nothing.
    func testAPlanReadsNoRecordStartsNoCheckAndMovesNothing() {
        h.facts.facts = ["X.ARW": .adapted]
        _ = dryRun(h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"]), withDnglab: true)
        XCTAssertEqual(h.log.entries, ["facts X.ARW Y.ARW"])
        XCTAssertEqual(h.backups.filesGiven, [])
    }

    // MARK: The JSON of the steps

    func testAStepOfAnOriginalIsWrittenWithItsNameAndItsActionAndNoConverter() throws {
        let plan = dryRun(h.snapshot(pending: ["X.ARW"]))
        let report = RunReport(folder: h.folder, factor: factor, plan: plan)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try ReportJSON.text(report).utf8))
            as? NSDictionary)
        XCTAssertEqual(json["steps"] as? [NSDictionary], [
            ["name": "X.ARW", "action": "convert", "converter": "adobe"],
            ["name": "X.dng", "action": "write"],
            ["name": "X.ARW", "action": "trashOriginal"],
        ])
        XCTAssertEqual(json["trashOriginals"] as? Bool, true)
        XCTAssertEqual(json["originalsInTrash"] as? Int, 1)
        XCTAssertEqual(json["dryRun"] as? Bool, true)
    }

    // The two keys are always there (design 14.3).
    func testTheTwoKeysAreInTheJSONWithTheOptionOffAndOn() throws {
        func json(_ report: RunReport) throws -> NSDictionary {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try ReportJSON.text(report).utf8)) as? NSDictionary)
        }
        let state = h.snapshot(pending: ["X.ARW"])
        let off = try json(RunReport(folder: h.folder, factor: factor,
                                     summary: h.job().run(state, factor: factor, convert: true,
                                                          trashOriginals: false)))
        XCTAssertEqual(off["trashOriginals"] as? Bool, false)
        XCTAssertEqual(off["originalsInTrash"] as? Int, 0)

        h = JobHarness()
        let on = try json(RunReport(folder: h.folder, factor: factor,
                                    summary: h.job().run(state, factor: factor, convert: true,
                                                         trashOriginals: true)))
        XCTAssertEqual(on["trashOriginals"] as? Bool, true)
        XCTAssertEqual(on["originalsInTrash"] as? Int, 1)
        XCTAssertNil(on["steps"], "a real run has no steps")

        let dryOff = try json(RunReport(folder: h.folder, factor: factor, plan: dryRun(state, trashOriginals: false)))
        XCTAssertEqual(dryOff["trashOriginals"] as? Bool, false)
        XCTAssertEqual(dryOff["originalsInTrash"] as? Int, 0)
    }

    // MARK: A name that is too long (design 13.9)

    /// A base name of this many letters, with the extension of an ARW.
    func arw(baseOf letters: Int, of letter: String = "a") -> String {
        String(repeating: letter, count: letters) + ".ARW"
    }

    // The longest name that the app makes for an ARW is exiftool's
    // temporary file beside the work file: the base name and 33 more
    // units. A file name has at most 255 UTF-16 units, in its decomposed
    // form. So a base name of 222 units is the longest.
    func testTheRuleForANameThatIsTooLong() {
        let folder = h.folder
        func tooLong(_ name: String) -> Bool {
            ConverterOutput.nameIsTooLong(for: folder.appendingPathComponent(name))
        }
        XCTAssertFalse(tooLong(arw(baseOf: 222)))
        XCTAssertTrue(tooLong(arw(baseOf: 223)))
        // Units of UTF-16, not bytes: "あ" is three bytes and one unit.
        XCTAssertFalse(tooLong(arw(baseOf: 222, of: "\u{3042}")))
        XCTAssertTrue(tooLong(arw(baseOf: 223, of: "\u{3042}")))
        // The decomposed form: "é" is one unit as typed, and two on the disk.
        XCTAssertFalse(tooLong(arw(baseOf: 111, of: "\u{E9}")))
        XCTAssertTrue(tooLong(arw(baseOf: 112, of: "\u{E9}")))
    }

    // The rule has no number of its own for the 33 units: it measures the
    // name that the two functions of the core make. So this test spells
    // that name, and holds the functions to it.
    func testTheLongestNameIsExiftoolsTemporaryFileBesideTheWorkFile() {
        let arw = h.folder.appendingPathComponent("frame 1.ARW")
        let work = ConverterOutput.workURL(for: arw)
        XCTAssertEqual(ConverterOutput.exiftoolLeftoverURL(for: work).lastPathComponent,
                       ".frame 1.desqueeze-work.dng_exiftool_tmp")
        XCTAssertEqual(ConverterOutput.longestFileName, 255)
    }

    // A real run starts no converter for such an ARW, and says "The file
    // name is too long." The dry run must not plan a conversion for it.
    func testAPlanHasNoConvertStepForAnARWWhoseNameIsTooLongAndGivesTheNoteOfTheRun() {
        let long = arw(baseOf: 223)
        let state = h.snapshot(pending: [long, "X.ARW"])

        // The run, on the real converters with a scripted runner: no
        // program starts for the long name.
        let tools = ScriptedTools()
        let real = DesqueezeJob(tag: h.tag, converters: tools.converters(backups: h.backups), backups: h.backups)
        let note = FileNote(name: long, kind: .notConverted, message: "Not converted.",
                            detail: "The file name is too long. Shorten it, then run again.")

        for withDnglab in [true, false] {
            h = JobHarness()
            let plan = dryRun(state, withDnglab: withDnglab)
            XCTAssertEqual(names(plan, .convert), ["X.ARW"], "no convert step for the long name")
            XCTAssertEqual(names(plan, .write), ["X.dng"], "and no DNG of it to tag")
            XCTAssertEqual(names(plan, .trashOriginal), ["X.ARW"], "and so no step for its original")
            XCTAssertEqual(plan.summary.notes, [note])
            XCTAssertEqual(plan.summary.failed, 1)
            XCTAssertEqual(plan.summary.converted, 1)
            XCTAssertEqual(plan.summary.unconvertedARWs, 1)
            XCTAssertEqual(plan.summary.originalsInTrash, 1)
        }

        // The same file in the run: the note, the counts, and no program.
        let longAlone = h.snapshot(pending: [long])
        let summary = real.run(longAlone, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(summary.notes, [note])
        XCTAssertEqual(tools.calls(to: ScriptedTools.dnglab) + tools.calls(to: ScriptedTools.adobe), [])
        h = JobHarness()
        let planned = dryRun(longAlone, trashOriginals: false, withDnglab: true)
        XCTAssertEqual(planned.steps, [])
        XCTAssertEqual(planned.summary, summary, "the plan and the run give one summary")
    }

    // A name at the limit still converts, in each way of counting: 222
    // letters, 222 "あ", and 111 "é".
    func testAPlanStillConvertsAnARWWhoseNameIsAtTheLimit() {
        for name in [arw(baseOf: 222), arw(baseOf: 222, of: "\u{3042}"), arw(baseOf: 111, of: "\u{E9}")] {
            let plan = dryRun(h.snapshot(pending: [name]))
            XCTAssertEqual(plan.steps.map(\.action), [.convert, .write, .trashOriginal], name)
            XCTAssertEqual(plan.summary.failed, 0, name)
        }
    }

    // The dry run and the run give one answer at each side of the boundary
    // (design 13.9): the same function decides for both. The run is on the
    // real converter of Adobe's program, with a fake disk and a fake
    // program, so no file is written.
    func testThePlanAndTheRunGiveOneAnswerAtEachSideOfTheBoundary() {
        let note = "The file name is too long. Shorten it, then run again."
        for (name, converts) in [(arw(baseOf: 222), true), (arw(baseOf: 223), false),
                                 (arw(baseOf: 235), false),
                                 (arw(baseOf: 222, of: "\u{3042}"), true), (arw(baseOf: 223, of: "\u{3042}"), false),
                                 (arw(baseOf: 111, of: "\u{E9}"), true), (arw(baseOf: 112, of: "\u{E9}"), false)] {
            h = JobHarness()
            let state = h.snapshot(pending: [name])
            let what = "\(name.count - 4) letters of \(name.prefix(1))"

            let disk = FakeDisk()
            let runner = FakeRunner()
            runner.handler = { call in
                disk.paths.insert(FakeAdobe.output(of: call.arguments))
                return ProcessResult(exitCode: 0, stdout: "", stderr: "")
            }
            let adobe = AdobeConverter(
                executable: ScriptedTools.adobe, runner: runner, discardLeftover: { _ in },
                fileExists: { disk.exists($0) }, fileSize: { disk.size($0) },
                fileIsRegular: { disk.isRegularFile($0) },
                rename: { from, to in
                    disk.move(from.path, to: to.path)
                    return .moved
                })
            let summary = DesqueezeJob(tag: h.tag, converters: RawConverters(dnglab: nil, adobe: adobe, facts: nil),
                                       backups: h.backups)
                .run(state, factor: factor, convert: true, trashOriginals: false)
            XCTAssertEqual(runner.calls.count, converts ? 1 : 0, "the run: \(what)")
            XCTAssertEqual(summary.notes.map(\.detail), converts ? [] : [note], "the run: \(what)")

            h = JobHarness()
            let plan = dryRun(state, trashOriginals: false)
            XCTAssertEqual(names(plan, .convert), converts ? [name] : [], "the plan: \(what)")
            XCTAssertEqual(plan.summary.notes.map(\.detail), converts ? [] : [note], "the plan: \(what)")
            XCTAssertEqual(plan.summary, summary, "the plan and the run give one summary: \(what)")
        }
    }
}
