import DesqueezeCore
import XCTest
@testable import DesqueezeCLI

/// `--trash-originals` (design 14.5), with fake tools: the parser, the two
/// usage errors, the run, the dry run, and the text. The trash of the
/// harness is a list of names, so nothing reaches the Trash.
final class OriginalsToolTests: XCTestCase {
    var h: ToolHarness!

    override func setUpWithError() throws { h = try ToolHarness() }
    override func tearDown() { h.cleanUp() }

    func usageError(_ line: String..., file: StaticString = #filePath, line number: UInt = #line) -> String {
        do {
            let invocation = try Arguments.parse(line)
            XCTFail("No usage error. Parsed as \(invocation).", file: file, line: number)
            return ""
        } catch {
            return (error as? UsageError)?.message ?? "Not a usage error: \(error)"
        }
    }

    // MARK: The parser

    func testTheFlagTurnsTheOptionOnAndNothingElseDoes() throws {
        let factor = SqueezeFactor(1.5)!
        XCTAssertEqual(try Arguments.parse(["run", "Shoot", "--factor", "1.5", "--trash-originals"]).command,
                       .run(folder: "Shoot", factor: factor, convert: true, trashOriginals: true, dryRun: false))
        XCTAssertEqual(try Arguments.parse(["--trash-originals", "run", "--dry-run", "Shoot", "--factor=1.5"]).command,
                       .run(folder: "Shoot", factor: factor, convert: true, trashOriginals: true, dryRun: true))
        // Off unless given.
        for line in [["run", "Shoot", "--factor", "1.5"], ["run", "Shoot", "--factor", "1.5", "--dry-run", "--json"],
                     ["run", "Shoot", "--factor", "1.5", "--verbose"]] {
            XCTAssertEqual(try Arguments.parse(line).command,
                           .run(folder: "Shoot", factor: factor, convert: true, trashOriginals: false,
                                dryRun: line.contains("--dry-run")))
        }
    }

    // The pair can do nothing: only an ARW that the run converts can go.
    func testTheFlagWithNoConvertIsAUsageError() {
        let message = "--trash-originals does not go with --no-convert. "
            + "A run that converts nothing has no original to move."
        XCTAssertEqual(usageError("run", "Shoot", "--factor", "1.5", "--trash-originals", "--no-convert"), message)
        XCTAssertEqual(usageError("run", "Shoot", "--no-convert", "--factor", "1.5", "--trash-originals",
                                  "--dry-run"), message)
    }

    func testTheFlagOnScanOrRemoveIsAUsageError() {
        XCTAssertEqual(usageError("scan", "Shoot", "--trash-originals"), "--trash-originals does not go with scan.")
        XCTAssertEqual(usageError("remove", "Shoot", "--trash-originals"),
                       "--trash-originals does not go with remove. Remove never moves an original.")
        XCTAssertEqual(usageError("remove", "Shoot", "--trash-originals", "--dry-run"),
                       "--trash-originals does not go with remove. Remove never moves an original.")
    }

    func testASpellingThatIsNotTheFlagIsAnUnknownOption() {
        XCTAssertEqual(usageError("run", "Shoot", "--factor", "1.5", "--trash-original"),
                       "Unknown option: --trash-original")
        XCTAssertEqual(usageError("run", "Shoot", "--factor", "1.5", "--trash-originals=yes"),
                       "Unknown option: --trash-originals=yes")
    }

    // MARK: A usage error runs nothing

    func testEachUsageErrorGivesTwoPrintsNothingOnStandardOutputAndStartsNoTool() throws {
        try h.touch("A.dng", "X.ARW")
        for line in [["run", "Shoot 1", "--factor", "1.5", "--trash-originals", "--no-convert"],
                     ["scan", "Shoot 1", "--trash-originals"], ["remove", "Shoot 1", "--trash-originals"],
                     ["remove", "Shoot 1", "--trash-originals", "--json"]] {
            XCTAssertEqual(h.run(line), 2, "\(line)")
            XCTAssertEqual(h.out.writes, [], "\(line)")
            XCTAssertEqual(h.err.lines.count, 2, "\(line)")
            XCTAssertEqual(h.err.lines.last, "See desqueeze --help.")
        }
        XCTAssertEqual(h.err.lines.first,
                       "desqueeze: --trash-originals does not go with remove. Remove never moves an original.")
        XCTAssertEqual(h.tools.commands, [])
        XCTAssertEqual(h.discarded.writes, [])
    }

    // MARK: The run

    /// A folder with one DNG, one ARW with a full match, and one from a lens.
    func makeShoot() throws {
        try h.touch("A.dng", "X.ARW", "Y.ARW")
        h.tools.scales = ["A.dng": "1 1"]
        h.tools.facts = ["X.ARW": FakeTools.adapted, "Y.ARW": FakeTools.lens]
    }

    // The first break to try: the option is treated as on when it is off.
    func testWithoutTheFlagNoARWReachesTheTrashAndTheTextHasNoLineAboutOriginals() throws {
        try makeShoot()
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5"), 0)
        XCTAssertEqual(h.discarded.writes.filter { $0.hasSuffix(".ARW") }, [])
        XCTAssertEqual(h.out.lines, [
            "2 converted · 3 set · 0 skipped · 0 failed",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])
        XCTAssertEqual(h.err.lines, ["1/5 X.ARW", "2/5 Y.ARW", "3/5 A.dng", "4/5 X.dng", "5/5 Y.dng"])
        XCTAssertFalse(h.tools.commands.contains { $0.contains("-IFD0:OriginalRawFileName -SubIFD:DefaultScale") },
                       "no check of a DNG")
    }

    func testWithTheFlagEachConvertedARWGoesToTheTrashAfterItsCheckAndTheTextSaysHowMany() throws {
        try makeShoot()
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--trash-originals"), 0)
        XCTAssertEqual(h.discarded.writes, ["A.dng_original", "X.dng_original", "Y.dng_original", "X.ARW", "Y.ARW"],
                       "the two originals go last, after every tag step")
        XCTAssertEqual(h.out.lines, [
            "2 converted · 3 set · 0 skipped · 0 failed",
            "Originals moved to the Trash: 2 of 2.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])
        XCTAssertEqual(h.err.lines, ["1/7 X.ARW", "2/7 Y.ARW", "3/7 A.dng", "4/7 X.dng", "5/7 Y.dng", "6/7 X.ARW",
                                     "7/7 Y.ARW"])
        // The read of the design, once for each converted ARW.
        XCTAssertEqual(h.tools.commands.filter { $0.contains("-IFD0:OriginalRawFileName -SubIFD:DefaultScale") }, [
            "exiftool -m -n -T -IFD0:OriginalRawFileName -SubIFD:DefaultScale X.dng",
            "exiftool -m -n -T -IFD0:OriginalRawFileName -SubIFD:DefaultScale Y.dng",
        ])
    }

    func testTheJSONHasTheTwoKeysWithTheFlagAndWithoutIt() throws {
        try makeShoot()
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--dry-run", "--json"), 0)
        var json = try h.json()
        XCTAssertEqual(json["trashOriginals"] as? Bool, false)
        XCTAssertEqual(json["originalsInTrash"] as? Int, 0)

        XCTAssertEqual(h.run("remove", "Shoot 1", "--dry-run", "--json"), 0)
        json = try h.json()
        XCTAssertEqual(json["trashOriginals"] as? Bool, false)
        XCTAssertEqual(json["originalsInTrash"] as? Int, 0)

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--trash-originals", "--json"), 0)
        json = try h.json()
        XCTAssertEqual(json["trashOriginals"] as? Bool, true)
        XCTAssertEqual(json["originalsInTrash"] as? Int, 2)
        XCTAssertEqual(json["notes"] as? [NSDictionary], [])
        XCTAssertNil(json["steps"])
    }

    // An original that stays has a note of the kind `originalKept`, and the
    // exit code does not change.
    func testAnOriginalThatStaysHasItsNoteAndTheExitCodeIsZero() throws {
        try makeShoot()
        h.tools.originalNames = ["Y.dng": "other.ARW"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--trash-originals"), 0)
        XCTAssertEqual(h.discarded.writes.filter { $0.hasSuffix(".ARW") }, ["X.ARW"])
        XCTAssertEqual(h.out.lines, [
            "2 converted · 3 set · 0 skipped · 0 failed",
            "Originals moved to the Trash: 1 of 2.",
            "Y.ARW: The original stays, because its DNG could not be checked.",
            "    The OriginalRawFileName of Y.dng is other.ARW, not Y.ARW.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])

        h.tools.scales = ["A.dng": "1.5 1"]
        try h.touch("Z.ARW")
        h.tools.originalNames = ["Z.dng": "other.ARW"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--trash-originals", "--json"), 0)
        let note = try XCTUnwrap((try h.json()["notes"] as? [NSDictionary])?.first)
        XCTAssertEqual(note["kind"] as? String, "originalKept")
        XCTAssertEqual(note["name"] as? String, "Z.ARW")
    }

    // With dnglab alone, a lens frame converts with no full match: its
    // original stays, and the next run cannot move it either.
    func testWithDnglabAloneTheOriginalOfADNGWithNoFullMatchStays() throws {
        try makeShoot()
        h.hasConverter = false
        h.hasDnglab = true
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--trash-originals", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual(h.discarded.writes.filter { $0.hasSuffix(".ARW") }, ["X.ARW"])
        XCTAssertEqual(json["originalsInTrash"] as? Int, 1)
        XCTAssertEqual((json["notes"] as? [NSDictionary])?.map { $0["kind"] as? String },
                       ["convertedUnmatched", "originalKept"])
    }

    // MARK: The dry run

    func testTheDryRunInTextShowsOneTrashStepForEachOriginalAndMovesNothing() throws {
        try makeShoot()
        h.hasDnglab = true
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--trash-originals", "--dry-run"), 0)
        XCTAssertEqual(h.out.lines, [
            "Dry run. No file was changed.",
            "  convert  X.ARW  with dnglab",
            "  convert  Y.ARW  with Adobe DNG Converter",
            "  write    A.dng",
            "  write    X.dng",
            "  write    Y.dng",
            "  trash    X.ARW",
            "  trash    Y.ARW",
            "A run would give: 2 converted · 3 set · 0 skipped · 0 failed",
        ])
        XCTAssertEqual(h.discarded.writes, [])
        XCTAssertEqual(h.err.lines, [], "nothing runs, so there is no progress")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.shoot.path).sorted(),
                       ["A.dng", "X.ARW", "Y.ARW"])
    }

    func testTheDryRunInJSONHasTheStepsAndTheCountThatARunWouldGive() throws {
        try makeShoot()
        h.hasConverter = false
        h.hasDnglab = true
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--trash-originals", "--dry-run", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual(json["steps"] as? [NSDictionary], [
            ["name": "X.ARW", "action": "convert", "converter": "dnglab"],
            ["name": "Y.ARW", "action": "convert", "converter": "dnglab"],
            ["name": "A.dng", "action": "write"],
            ["name": "X.dng", "action": "write"],
            ["name": "Y.dng", "action": "write"],
            // The lens frame gets the `convertedUnmatched` note, so its
            // original has no step.
            ["name": "X.ARW", "action": "trashOriginal"],
        ])
        XCTAssertEqual(json["trashOriginals"] as? Bool, true)
        XCTAssertEqual(json["originalsInTrash"] as? Int, 1)
        XCTAssertEqual(json["dryRun"] as? Bool, true)
        XCTAssertEqual((json["notes"] as? [NSDictionary])?.map { $0["kind"] as? String },
                       ["convertedUnmatched", "originalKept"])
        XCTAssertEqual(h.discarded.writes, [])
    }

    // MARK: The text

    func testTheWordOfEachStepInTheTextOfADryRun() {
        XCTAssertEqual(RunPlan.Action.allCases.map(TextOutput.word(for:)),
                       ["convert", "write", "skip", "blocked", "trash"])
    }

    // The line about the originals is the core's, after the counts and the
    // line about the two converters, and before the notes.
    func testTheLineAboutTheOriginalsIsTheCoresAndStandsAfterTheCounts() {
        var summary = RunSummary()
        summary.convertedByDnglab = 2
        summary.convertedByAdobe = 1
        summary.set = 3
        summary.trashOriginals = true
        summary.originalsInTrash = 2
        summary.notes = [FileNote(name: "Y.ARW", kind: .originalKept,
                                  message: "The original changed during the run, so it stays.", detail: nil)]
        let report = RunReport(folder: URL(fileURLWithPath: "/tmp/Shoot 1"), factor: SqueezeFactor(1.5)!,
                               summary: summary)
        XCTAssertEqual(TextOutput.run(report, converterInstalled: true), [
            "3 converted · 3 set · 0 skipped · 0 failed",
            "Converted with dnglab: 2. With Adobe DNG Converter: 1.",
            "Originals moved to the Trash: 2 of 3.",
            "Y.ARW: The original changed during the run, so it stays.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])
        XCTAssertEqual(report.originalsLine, summary.originalsLine)
    }

    // MARK: The help

    func testHelpSaysWhatTheFlagDoesAndThatItIsOffUnlessGiven() {
        h.run("--help")
        let text = h.out.lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        XCTAssertTrue(text.contains("--trash-originals  For run: moves each original ARW to the Trash after its DNG "
            + "passes the check. Off unless given. Does not go with --no-convert."), text)
        XCTAssertTrue(text.contains("An ARW stays where it is, unless run has --trash-originals. An ARW in the Trash "
            + "can be put back until the Trash is emptied."), text)
        XCTAssertEqual(h.out.lines.filter { $0.count >= 80 }, [], "every line is under 80 columns")
        XCTAssertFalse(h.out.text.contains("!"))
    }
}
