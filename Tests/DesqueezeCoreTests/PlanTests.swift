import XCTest
@testable import DesqueezeCore

/// The one decision that the run and the dry run share, and the dry run.
final class PlanTests: XCTestCase {
    let factor = SqueezeFactor(1.5)!
    var h: JobHarness!

    override func setUp() { h = JobHarness() }

    // MARK: The decision for one DNG

    func decide(_ horizontal: Double?, backup: Bool, factor: SqueezeFactor? = nil) -> TagDecision {
        TagDecision.decide(scale: horizontal.map { Scale(horizontal: $0, vertical: 1) },
                           hasBackup: backup, factor: factor ?? self.factor)
    }

    func testAKnownScaleAtTheFactorIsSkippedWithOrWithoutABackup() {
        XCTAssertEqual(decide(1.5, backup: false), .skip)
        XCTAssertEqual(decide(1.5, backup: true), .skip)
        XCTAssertEqual(decide(1, backup: true, factor: .noStretch), .skip)
    }

    func testAnOlderBackupBlocksAFileThatIsNotAtTheFactor() {
        XCTAssertEqual(decide(1, backup: true), .blocked)
        XCTAssertEqual(decide(2, backup: true), .blocked)
        XCTAssertEqual(decide(1.5, backup: true, factor: .noStretch), .blocked)
    }

    func testAFileThatIsNotAtTheFactorAndHasNoBackupIsWritten() {
        XCTAssertEqual(decide(1, backup: false), .write)
        XCTAssertEqual(decide(1.5, backup: false, factor: .noStretch), .write)
        XCTAssertEqual(decide(1.5001, backup: false), .write, "a neighbor factor is not a match")
    }

    // "Unknown" is never "already at this value", for Apply or for Remove.
    func testAnUnknownScaleIsNeverSkipped() {
        XCTAssertEqual(decide(nil, backup: false), .write)
        XCTAssertEqual(decide(nil, backup: false, factor: .noStretch), .write)
        XCTAssertEqual(decide(nil, backup: true), .blocked)
        XCTAssertEqual(decide(nil, backup: true, factor: .noStretch), .blocked)
    }

    func testAScaleWithAVerticalStretchIsNotAtAnyFactor() {
        let tall = Scale(horizontal: 1.5, vertical: 2)
        XCTAssertEqual(TagDecision.decide(scale: tall, hasBackup: false, factor: factor), .write)
    }

    // MARK: The dry run

    /// The harness has Adobe DNG Converter alone unless a test says so, so a
    /// `convert` step names it unless the test names dnglab.
    func step(_ name: String, _ action: RunPlan.Action, by converter: ConverterKind? = nil) -> RunPlan.Step {
        RunPlan.Step(name: name, action: action, converter: converter ?? (action == .convert ? .adobe : nil))
    }

    // MARK: The converter of each `convert` step (design 13.4 and 13.6)

    /// Three pending files: a full match, a lens frame, and a file with no facts.
    func threeKinds() -> FolderSnapshot {
        h.facts.facts = ["full.ARW": .adapted, "lens.ARW": .lens]
        return h.snapshot(pending: ["full.ARW", "lens.ARW", "unread.ARW"])
    }

    func testWithBothConvertersAPlanGivesAFullMatchToDnglabAndEveryOtherARWToAdobe() {
        let plan = h.job(withDnglab: true).plan(threeKinds(), factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(Array(plan.steps.prefix(3)), [
            step("full.ARW", .convert, by: .dnglab), step("lens.ARW", .convert, by: .adobe),
            step("unread.ARW", .convert, by: .adobe),
        ])
        XCTAssertEqual([plan.summary.converted, plan.summary.convertedByDnglab, plan.summary.convertedByAdobe],
                       [3, 1, 2])
        XCTAssertEqual(plan.summary.notes, [], "Adobe DNG Converter makes the file that Lightroom makes: no note")
        XCTAssertEqual(h.log.entries, ["facts full.ARW lens.ARW unread.ARW"], "one read, and no converter")
    }

    func testWithDnglabAloneAPlanGivesEveryARWToDnglabWithANoteForEachOneWithNoFullMatch() {
        let plan = h.job(withConverter: false, withDnglab: true).plan(threeKinds(), factor: factor, convert: true,
                                                                      trashOriginals: false)
        XCTAssertEqual(Array(plan.steps.prefix(3)), [
            step("full.ARW", .convert, by: .dnglab), step("lens.ARW", .convert, by: .dnglab),
            step("unread.ARW", .convert, by: .dnglab),
        ])
        XCTAssertEqual([plan.summary.converted, plan.summary.convertedByDnglab, plan.summary.convertedByAdobe],
                       [3, 3, 0])
        XCTAssertEqual(plan.summary.notes, [
            .convertedUnmatched("lens.dng", rule: .noLensCorrection, facts: .lens),
            .convertedUnmatched("unread.dng", rule: .model, facts: .none),
        ])
        XCTAssertEqual(plan.summary.failed, 0)
        XCTAssertEqual(plan.summary.unconvertedARWs, 0)
        XCTAssertEqual(h.log.entries, ["facts full.ARW lens.ARW unread.ARW"])
    }

    // With Adobe alone no fact changes the choice, so the plan does not read them.
    func testWithAdobeAloneAPlanGivesEveryARWToAdobeAndReadsNoFacts() {
        let plan = h.job().plan(threeKinds(), factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(Array(plan.steps.prefix(3)), [
            step("full.ARW", .convert, by: .adobe), step("lens.ARW", .convert, by: .adobe),
            step("unread.ARW", .convert, by: .adobe),
        ])
        XCTAssertEqual([plan.summary.convertedByDnglab, plan.summary.convertedByAdobe], [0, 3])
        XCTAssertEqual(h.log.entries, [])
    }

    func testAPlanThatConvertsNothingReadsNoFacts() {
        let state = threeKinds()
        XCTAssertEqual(h.job(withConverter: false).plan(state,
                                                        factor: factor, convert: true, trashOriginals: false).steps, [])
        XCTAssertEqual(h.job(withDnglab: true).plan(state,
                                                    factor: factor, convert: false, trashOriginals: false).steps, [])
        XCTAssertEqual(h.job(withDnglab: true).plan(state, factor: factor, convert: true,
                                                    trashOriginals: false, remove: true).steps, [])
        let readOnly = h.snapshot(pending: ["full.ARW"], writable: false)
        XCTAssertEqual(h.job(withDnglab: true).plan(readOnly,
                                                    factor: factor, convert: true, trashOriginals: false).steps, [])
        let noARW = h.snapshot(dngs: [h.dng("A.dng", at: 1.5)])
        XCTAssertEqual(h.job(withDnglab: true).plan(noARW, factor: factor, convert: true,
                                                    trashOriginals: false).steps, [step("A.dng", .skip)])
        XCTAssertEqual(h.log.entries, [], "no read of the facts, and no converter")
    }

    // Only a `convert` step has a converter.
    func testNoOtherStepHasAConverter() {
        h.backups.existing = ["held.dng"]
        let state = h.snapshot(dngs: [h.dng("Z.dng"), h.dng("done.dng", at: 1.5), h.dng("held.dng")],
                               pending: ["A.ARW"])
        h.facts.facts = ["A.ARW": .adapted]
        let plan = h.job(withDnglab: true).plan(state, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(plan.steps.map(\.converter), [.dnglab, nil, nil, nil, nil])
        XCTAssertEqual(plan.steps.map(\.action), [.convert, .write, .skip, .blocked, .write])
    }

    func testAPlanListsEachConversionThenEachDNGTheNewOnesLast() {
        h.backups.existing = ["held.dng"]
        let state = h.snapshot(dngs: [h.dng("Z.dng"), h.dng("done.dng", at: 1.5), h.dng("held.dng")],
                               pending: ["A.ARW", "B.ARW"])
        let plan = h.job().plan(state, factor: factor, convert: true, trashOriginals: false)

        XCTAssertEqual(plan.steps, [
            step("A.ARW", .convert), step("B.ARW", .convert),
            step("Z.dng", .write), step("done.dng", .skip), step("held.dng", .blocked),
            step("A.dng", .write), step("B.dng", .write),
        ])
        XCTAssertEqual(plan.summary.converted, 2)
        XCTAssertEqual(plan.summary.set, 3)
        XCTAssertEqual(plan.summary.skipped, 1)
        XCTAssertEqual(plan.summary.blocked, 1)
        XCTAssertEqual(plan.summary.failed, 0)
        XCTAssertEqual(plan.summary.unconvertedARWs, 0)
        XCTAssertFalse(plan.summary.cancelled)
        XCTAssertEqual(plan.summary.notes.map(\.kind), [.blockedByBackup])
        XCTAssertEqual(h.log.entries, [], "a plan converts nothing, writes nothing, and moves no backup")
        XCTAssertEqual(h.backups.existing, ["held.dng"])
    }

    // The converter writes no stretch. So at factor 1 the new DNG is at the
    // value already, and at any other factor it is written.
    func testAPlanKnowsThatAConversionMakesADNGWithNoStretch() {
        let state = h.snapshot(pending: ["X.ARW"])
        XCTAssertEqual(h.job().plan(state, factor: .noStretch, convert: true, trashOriginals: false).steps,
                       [step("X.ARW", .convert), step("X.dng", .skip)])
        XCTAssertEqual(h.job().plan(state, factor: factor, convert: true, trashOriginals: false).steps,
                       [step("X.ARW", .convert), step("X.dng", .write)])
    }

    func testAPlanForRemoveConvertsNothingAndReportsNoARW() {
        let state = h.snapshot(dngs: [h.dng("A.dng", at: 1.5), h.dng("B.dng", at: 1), h.dng("C.dng", at: nil)],
                               pending: ["X.ARW"])
        let plan = h.job().plan(state, factor: .noStretch, convert: false, trashOriginals: false, remove: true)
        XCTAssertEqual(plan.steps, [step("A.dng", .write), step("B.dng", .skip), step("C.dng", .write)])
        XCTAssertEqual(plan.summary.converted, 0)
        XCTAssertEqual(plan.summary.unconvertedARWs, 0)
    }

    // Remove never converts, whatever `convert` says. The plan must not list
    // a conversion for a Remove that was given `convert: true`.
    func testAPlanForRemoveHasNoConvertStepEvenWhenConvertIsTrue() {
        let state = h.snapshot(dngs: [h.dng("A.dng", at: 1.5)], pending: ["X.ARW"])
        let plan = h.job().plan(state, factor: .noStretch, convert: true, trashOriginals: false, remove: true)
        XCTAssertEqual(plan.steps, [step("A.dng", .write)])
        XCTAssertEqual(plan.summary.converted, 0)
        XCTAssertEqual(plan.summary.unconvertedARWs, 0)
    }

    // Remove writes 1 1. A factor that rides along beside `remove` is ignored.
    func testAPlanForRemoveDecidesAtNoStretchWhateverFactorItWasGiven() {
        let state = h.snapshot(dngs: [h.dng("at factor.dng", at: 1.5), h.dng("plain.dng", at: 1)])
        let plan = h.job().plan(state, factor: factor, convert: false, trashOriginals: false, remove: true)
        XCTAssertEqual(plan.steps, [step("at factor.dng", .write), step("plain.dng", .skip)])
        XCTAssertEqual(plan.summary.set, 1)
        XCTAssertEqual(plan.summary.skipped, 1)
    }

    // Remove is an intent. A plan at factor 1 with no conversion is not one.
    func testAPlanAtFactorOneWithNoConvertStillReportsTheARWFiles() {
        let state = h.snapshot(dngs: [h.dng("A.dng", at: 1.5)], pending: ["X.ARW"])
        let plan = h.job().plan(state, factor: .noStretch, convert: false, trashOriginals: false)
        XCTAssertEqual(plan.steps, [step("A.dng", .write)])
        XCTAssertEqual(plan.summary.unconvertedARWs, 1)
    }

    func testAPlanWithNoConverterOrNoConvertLeavesTheARWFiles() {
        let state = h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW", "Y.ARW"])
        for plan in [h.job(withConverter: false).plan(state, factor: factor, convert: true, trashOriginals: false),
                     h.job().plan(state, factor: factor, convert: false, trashOriginals: false)] {
            XCTAssertEqual(plan.steps, [step("A.dng", .write)])
            XCTAssertEqual(plan.summary.converted, 0)
            XCTAssertEqual(plan.summary.unconvertedARWs, 2)
        }
    }

    func testAPlanForAReadOnlyFolderHasNoStepAndTheOneNote() {
        let state = h.snapshot(dngs: [h.dng("A.dng")], pending: ["X.ARW"], orphans: ["gone.dng_original"],
                               writable: false)
        let plan = h.job().plan(state, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(plan.steps, [])
        XCTAssertEqual(plan.summary.notes.map(\.kind), [.folderReadOnly])
        XCTAssertEqual(plan.summary.set, 0)
    }

    func testAPlanNamesEachOrphanBackupFirstAndPlansNoStepForIt() {
        h.backups.existing = ["A.dng"]
        let state = h.snapshot(dngs: [h.dng("A.dng", at: 1.5)], orphans: ["gone.dng_original"])
        let plan = h.job().plan(state, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(plan.steps, [step("A.dng", .skip)])
        XCTAssertEqual(plan.summary.notes.map(\.kind), [.orphanBackup, .leftoverBackup])
        XCTAssertEqual(plan.summary.notes.map(\.name), ["gone.dng_original", "A.dng"])
    }

    // MARK: The dry run and the run cannot disagree

    /// One folder state, built on a fresh set of fakes each time: a run
    /// changes its fakes.
    struct Scenario {
        let name: String
        let factor: SqueezeFactor
        let convert: Bool
        var remove = false
        var trashOriginals = false
        var withConverter = true
        var withDnglab = false
        let build: (JobHarness) -> FolderSnapshot

        func job(_ h: JobHarness) -> DesqueezeJob { h.job(withConverter: withConverter, withDnglab: withDnglab) }
    }

    var scenarios: [Scenario] {
        let mixed: (JobHarness) -> FolderSnapshot = { h in
            h.backups.existing = ["held.dng", "leftover.dng", "held unknown.dng"]
            return h.snapshot(
                dngs: [h.dng("plain.dng"), h.dng("at value.dng", at: 1.5), h.dng("held.dng", at: 2),
                       h.dng("leftover.dng", at: 1.5), h.dng("unknown.dng", at: nil),
                       h.dng("held unknown.dng", at: nil), h.dng("unstretched.dng", at: 1)],
                pending: ["X.ARW", "Y.ARW"], orphans: ["gone.dng_original", "LOUD.DNG_ORIGINAL"])
        }
        // A full match, a lens frame, an ISO with no row, and a file with no facts.
        let kinds: (JobHarness) -> FolderSnapshot = { h in
            h.facts.facts = ["full.ARW": .adapted, "lens.ARW": .lens, "iso.ARW": .iso1250]
            return h.snapshot(dngs: [h.dng("plain.dng"), h.dng("at value.dng", at: 1.5)],
                              pending: ["full.ARW", "iso.ARW", "lens.ARW", "unread.ARW"])
        }
        return [
            Scenario(name: "both converters", factor: factor, convert: true, withDnglab: true, build: kinds),
            Scenario(name: "both converters at factor 1", factor: .noStretch, convert: true, withDnglab: true,
                     build: kinds),
            Scenario(name: "dnglab alone", factor: factor, convert: true, withConverter: false, withDnglab: true,
                     build: kinds),
            Scenario(name: "Adobe alone", factor: factor, convert: true, build: kinds),
            Scenario(name: "neither converter", factor: factor, convert: true, withConverter: false, build: kinds),
            Scenario(name: "both converters, no convert", factor: factor, convert: false, withDnglab: true,
                     build: kinds),
            Scenario(name: "both converters, remove", factor: .noStretch, convert: true, remove: true,
                     withDnglab: true, build: kinds),
            Scenario(name: "both converters, the mixed folder", factor: factor, convert: true, withDnglab: true,
                     build: mixed),
            Scenario(name: "apply", factor: factor, convert: true, build: mixed),
            Scenario(name: "apply at factor 1", factor: .noStretch, convert: true, build: mixed),
            Scenario(name: "apply, no convert", factor: factor, convert: false, build: mixed),
            Scenario(name: "apply, no converter", factor: factor, convert: true, withConverter: false, build: mixed),
            Scenario(name: "apply at factor 1, no convert", factor: .noStretch, convert: false, build: mixed),
            Scenario(name: "remove", factor: .noStretch, convert: false, remove: true, build: mixed),
            Scenario(name: "remove, asked to convert", factor: .noStretch, convert: true, remove: true, build: mixed),
            Scenario(name: "remove, given a free factor", factor: factor, convert: true, remove: true, build: mixed),
            // The originals, on request (design 14). In a run on the fakes
            // every line of design 14.2 holds, as a plan assumes.
            Scenario(name: "both converters, the originals", factor: factor, convert: true, trashOriginals: true,
                     withDnglab: true, build: kinds),
            Scenario(name: "dnglab alone, the originals", factor: factor, convert: true, trashOriginals: true,
                     withConverter: false, withDnglab: true, build: kinds),
            Scenario(name: "Adobe alone, the originals", factor: factor, convert: true, trashOriginals: true,
                     build: kinds),
            Scenario(name: "the mixed folder, the originals", factor: factor, convert: true, trashOriginals: true,
                     build: mixed),
            Scenario(name: "at factor 1, the originals", factor: .noStretch, convert: true, trashOriginals: true,
                     withDnglab: true, build: kinds),
            Scenario(name: "neither converter, the originals", factor: factor, convert: true, trashOriginals: true,
                     withConverter: false, build: kinds),
            Scenario(name: "no convert, the originals", factor: factor, convert: false, trashOriginals: true,
                     build: mixed),
            Scenario(name: "remove, asked for the originals", factor: .noStretch, convert: true, remove: true,
                     trashOriginals: true, build: mixed),
            Scenario(name: "a blocked new DNG, the originals", factor: factor, convert: true, trashOriginals: true) {
                $0.backups.existing = ["X.dng"]
                return $0.snapshot(pending: ["X.ARW", "Y.ARW"])
            },
            Scenario(name: "read-only, the originals", factor: factor, convert: true, trashOriginals: true) {
                $0.snapshot(dngs: [$0.dng("A.dng")], pending: ["X.ARW"], writable: false)
            },
            Scenario(name: "only ARW files", factor: factor, convert: true) { $0.snapshot(pending: ["X.ARW"]) },
            Scenario(name: "only an orphan", factor: factor, convert: true) {
                $0.snapshot(orphans: ["gone.dng_original"])
            },
            Scenario(name: "empty", factor: factor, convert: true) { $0.snapshot() },
            Scenario(name: "read-only", factor: factor, convert: true) {
                $0.snapshot(dngs: [$0.dng("A.dng")], pending: ["X.ARW"], orphans: ["gone.dng_original"],
                            writable: false)
            },
            Scenario(name: "read-only remove", factor: .noStretch, convert: false, remove: true) {
                $0.snapshot(dngs: [$0.dng("A.dng", at: 2)], pending: ["X.ARW"], writable: false)
            },
        ]
    }

    func testThePlanSummaryIsTheSummaryOfARunWhereEveryStepPasses() {
        for scenario in scenarios {
            let planned = JobHarness()
            let plan = scenario.job(planned)
                .plan(scenario.build(planned), factor: scenario.factor, convert: scenario.convert,
                      trashOriginals: scenario.trashOriginals, remove: scenario.remove)
            let real = JobHarness()
            let summary = scenario.job(real)
                .run(scenario.build(real), factor: scenario.factor, convert: scenario.convert,
                     trashOriginals: scenario.trashOriginals, remove: scenario.remove)

            XCTAssertEqual(plan.summary, summary, scenario.name)
            XCTAssertEqual(planned.log.entries.filter { !$0.hasPrefix("facts ") }, [], scenario.name)
        }
    }

    // Each planned step is what the run does: one conversion, one write, or
    // no call at all.
    func testThePlanStepsAreTheCallsOfTheRunInOrder() {
        for scenario in scenarios {
            let planned = JobHarness()
            let plan = scenario.job(planned)
                .plan(scenario.build(planned), factor: scenario.factor, convert: scenario.convert,
                      trashOriginals: scenario.trashOriginals, remove: scenario.remove)
            let real = JobHarness()
            _ = scenario.job(real)
                .run(scenario.build(real), factor: scenario.factor, convert: scenario.convert,
                     trashOriginals: scenario.trashOriginals, remove: scenario.remove)

            // Remove writes 1 1, whatever factor it was given.
            let written = scenario.remove ? SqueezeFactor.noStretch : scenario.factor
            let expected = plan.steps.compactMap { step -> String? in
                switch step.action {
                // The fake for Adobe DNG Converter says "convert", and the
                // fake for dnglab "dnglab".
                case .convert: return "\(step.converter == .dnglab ? "dnglab" : "convert") \(step.name)"
                case .write: return "write \(written.tagValue) \(step.name)"
                case .skip, .blocked: return nil
                // The move of an original is one call of the Trash.
                case .trashOriginal: return "trashFile \(step.name)"
                }
            }
            // The Trash also gets the partial output of a failed conversion.
            // No scenario has one, so each `trashFile` is an original.
            let calls = real.log.entries.filter {
                $0.hasPrefix("convert ") || $0.hasPrefix("dnglab ") || $0.hasPrefix("write ")
                    || $0.hasPrefix("trashFile ")
            }
            XCTAssertEqual(calls, expected, scenario.name)
            // The plan made the read of the facts that the run makes, and no other call.
            XCTAssertEqual(planned.log.entries, real.log.entries.filter { $0.hasPrefix("facts ") }, scenario.name)
        }
    }

    // The scenarios must reach both converters and the note, or the tests
    // above prove less than they say.
    func testTheScenariosReachBothConvertersAndTheNoteOfADNGWithNoFullMatch() {
        var converters = Set<ConverterKind>()
        var kinds = Set<FileNote.Kind>()
        for scenario in scenarios {
            let h = JobHarness()
            let plan = scenario.job(h).plan(scenario.build(h), factor: scenario.factor, convert: scenario.convert,
                                            trashOriginals: scenario.trashOriginals, remove: scenario.remove)
            converters.formUnion(plan.steps.compactMap(\.converter))
            kinds.formUnion(plan.summary.notes.map(\.kind))
        }
        XCTAssertEqual(converters, [.dnglab, .adobe])
        XCTAssertTrue(kinds.contains(.convertedUnmatched))
        XCTAssertTrue(kinds.contains(.originalKept), "an original that stays, for the two tests above")
    }

    // The scenarios must reach every action, or the two tests above prove less
    // than they say.
    func testTheScenariosReachEveryAction() {
        var seen = Set<RunPlan.Action>()
        for scenario in scenarios {
            let h = JobHarness()
            let plan = scenario.job(h)
                .plan(scenario.build(h), factor: scenario.factor, convert: scenario.convert,
                      trashOriginals: scenario.trashOriginals, remove: scenario.remove)
            seen.formUnion(plan.steps.map(\.action))
        }
        XCTAssertEqual(seen, Set(RunPlan.Action.allCases))
    }

    // MARK: A plan from a folder

    func testAPlanFromAFolderScansFreshAndCallsNoToolThatWrites() throws {
        let shoot = try makeTemporaryFolder()
        defer { removeTemporaryFolder(shoot) }
        for name in ["A.dng", "B.dng", "X.ARW", "gone.dng_original"] {
            try Data(name.utf8).write(to: shoot.appendingPathComponent(name))
        }
        h.tag.rows = [
            TagRow(fileName: "A.dng", scale: .noStretch, originalRawFileName: nil),
            TagRow(fileName: "B.dng", scale: Scale(horizontal: 1.5, vertical: 1), originalRawFileName: nil),
        ]

        let plan = try h.job().plan(folder: shoot, factor: factor, convert: true, trashOriginals: false)

        XCTAssertEqual(plan.steps, [step("X.ARW", .convert), step("A.dng", .write), step("B.dng", .skip),
                                    step("X.dng", .write)])
        XCTAssertEqual(plan.summary.notes.map(\.name), ["gone.dng_original"])
        XCTAssertEqual(h.log.entries, ["readFolder"], "the scan's one read, and nothing else")
        for name in ["A.dng", "B.dng", "X.ARW", "gone.dng_original"] {
            XCTAssertEqual(try Data(contentsOf: shoot.appendingPathComponent(name)), Data(name.utf8))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shoot.path).sorted(),
                       ["A.dng", "B.dng", "X.ARW", "gone.dng_original"])

        // The folder changes. The next plan must see it.
        h.tag.rows[0] = TagRow(fileName: "A.dng", scale: Scale(horizontal: 1.5, vertical: 1), originalRawFileName: nil)
        let second = try h.job().plan(folder: shoot, factor: factor, convert: true, trashOriginals: false)
        XCTAssertEqual(second.steps.first(where: { $0.name == "A.dng" })?.action, .skip)
        XCTAssertEqual(h.log.entries, ["readFolder", "readFolder"])
    }

    // With dnglab the plan makes a second read, of the ARW facts. It is a
    // read: no file changes, and no converter starts.
    func testAPlanFromAFolderWithDnglabReadsTheFactsAndChangesNoFile() throws {
        let shoot = try makeTemporaryFolder()
        defer { removeTemporaryFolder(shoot) }
        for name in ["A.dng", "X.ARW", "Y.ARW"] { try Data(name.utf8).write(to: shoot.appendingPathComponent(name)) }
        h.tag.rows = [TagRow(fileName: "A.dng", scale: .noStretch, originalRawFileName: nil)]
        h.facts.facts = ["X.ARW": .adapted, "Y.ARW": .lens]

        let plan = try h.job(withDnglab: true).plan(folder: shoot, factor: factor, convert: true, trashOriginals: false)

        XCTAssertEqual(plan.steps, [step("X.ARW", .convert, by: .dnglab), step("Y.ARW", .convert, by: .adobe),
                                    step("A.dng", .write), step("X.dng", .write), step("Y.dng", .write)])
        XCTAssertEqual(h.log.entries, ["readFolder", "facts X.ARW Y.ARW"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shoot.path).sorted(),
                       ["A.dng", "X.ARW", "Y.ARW"])
        for name in ["A.dng", "X.ARW", "Y.ARW"] {
            XCTAssertEqual(try Data(contentsOf: shoot.appendingPathComponent(name)), Data(name.utf8))
        }
    }

    func testAPlanFromAFolderThrowsWhenTheScanFails() throws {
        let shoot = try makeTemporaryFolder()
        defer { removeTemporaryFolder(shoot) }
        XCTAssertThrowsError(try h.job().plan(folder: shoot.appendingPathComponent("No such folder"),
                                              factor: factor, convert: true, trashOriginals: false))
        try Data("x".utf8).write(to: shoot.appendingPathComponent("A.dng"))
        h.tag.readFolderError = TagError.toolFailed("Error: exiftool did not start")
        XCTAssertThrowsError(try h.job().plan(folder: shoot, factor: factor, convert: true, trashOriginals: false)) {
            XCTAssertEqual($0 as? TagError, .toolFailed("Error: exiftool did not start"))
        }
    }
}
