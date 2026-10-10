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

    /// A base name of this many bytes, with the extension of an ARW.
    func arw(baseOf bytes: Int) -> String { String(repeating: "a", count: bytes) + ".ARW" }

    // The work file of an ARW has the base name and 20 bytes more, and a
    // file name has at most 255 bytes.
    func testTheRuleForANameThatIsTooLong() {
        let folder = h.folder
        XCTAssertFalse(ConverterOutput.workNameIsTooLong(for: folder.appendingPathComponent(arw(baseOf: 235))))
        XCTAssertTrue(ConverterOutput.workNameIsTooLong(for: folder.appendingPathComponent(arw(baseOf: 236))))
        // Bytes of UTF-8, not characters.
        let wide = String(repeating: "é", count: 118) + ".ARW"
        XCTAssertTrue(ConverterOutput.workNameIsTooLong(for: folder.appendingPathComponent(wide)))
    }

    // A real run starts no converter for such an ARW, and says "The file
    // name is too long." The dry run must not plan a conversion for it.
    func testAPlanHasNoConvertStepForAnARWWhoseNameIsTooLongAndGivesTheNoteOfTheRun() {
        let long = arw(baseOf: 236)
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

    // A name at the limit still converts.
    func testAPlanStillConvertsAnARWWhoseNameIsAtTheLimit() {
        let plan = dryRun(h.snapshot(pending: [arw(baseOf: 235)]))
        XCTAssertEqual(plan.steps.map(\.action), [.convert, .write, .trashOriginal])
        XCTAssertEqual(plan.summary.failed, 0)
    }
}
