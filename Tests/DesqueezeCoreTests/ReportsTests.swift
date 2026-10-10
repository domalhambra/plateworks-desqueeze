import XCTest
@testable import DesqueezeCore

/// The JSON of design 12.1 and 13.6. Each key name is pinned here: the command line
/// tool and the MCP server print these types, and other programs read them.
final class ReportsTests: XCTestCase {
    let folder = URL(fileURLWithPath: "/Volumes/Card/Shoot 1")
    let factor = SqueezeFactor(1.5)!

    /// The report as a parsed JSON object.
    func object<Report: Encodable>(_ report: Report) throws -> NSDictionary {
        let data = Data(try ReportJSON.text(report).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    func parsed(_ json: String) throws -> NSDictionary {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
    }

    func keys(_ object: NSDictionary) -> Set<String> { Set(object.allKeys.compactMap { $0 as? String }) }

    // MARK: The scale as text

    func testAScaleIsWrittenTheWayExiftoolPrintsIt() {
        XCTAssertEqual(Scale(horizontal: 1.5, vertical: 1).text, "1.5 1")
        XCTAssertEqual(Scale.noStretch.text, "1 1")
        XCTAssertEqual(Scale(horizontal: 2, vertical: 1).text, "2 1")
        XCTAssertEqual(Scale(horizontal: 1.33, vertical: 1).text, "1.33 1")
        XCTAssertEqual(Scale(horizontal: 0.5, vertical: 2).text, "0.5 2")
    }

    // A value this app did not write is shown as it is, not rounded to a factor.
    func testAScaleIsNotRounded() {
        XCTAssertEqual(Scale(horizontal: 1.33333, vertical: 1).text, "1.33333 1")
        XCTAssertEqual(Scale(horizontal: 1.50004, vertical: 1.25).text, "1.50004 1.25")
    }

    func testTheScaleOfAFactorIsItsTagValue() {
        let factors = SqueezeFactor.presets + [1, 1.0001, 1.3333, 1.25, 3.9999, 4].compactMap { SqueezeFactor($0) }
        XCTAssertEqual(factors.count, 10)
        for factor in factors {
            XCTAssertEqual(Scale(horizontal: factor.value, vertical: 1).text, factor.tagValue)
        }
    }

    // MARK: The scan report

    func dng(_ name: String, scale: Scale?, original: String? = nil, backup: Bool = false) -> DNGFile {
        DNGFile(url: folder.appendingPathComponent(name), scale: scale, originalRawFileName: original,
                hasBackup: backup)
    }

    func scanReport(converter: Bool = true, dnglab: Bool = true) -> ScanReport {
        let snapshot = FolderSnapshot(
            folder: folder,
            dngs: [dng("a.dng", scale: Scale(horizontal: 1.5, vertical: 1), original: "a.ARW"),
                   dng("junk.dng", scale: nil, backup: true)],
            pendingARWs: [folder.appendingPathComponent("b.ARW")],
            orphanBackups: [folder.appendingPathComponent("lost.dng_original")],
            isWritable: false)
        return ScanReport(
            snapshot: snapshot, exiftool: URL(fileURLWithPath: "/opt/homebrew/bin/exiftool"),
            dnglab: dnglab ? URL(fileURLWithPath: "/opt/homebrew/bin/dnglab") : nil,
            dngConverter: converter ? URL(fileURLWithPath: "/Applications/Adobe DNG Converter.app/x") : nil)
    }

    func testTheScanReportHasExactlyTheKeysOfTheDesign() throws {
        let json = try object(scanReport())
        XCTAssertEqual(keys(json), ["folder", "writable", "exiftool", "dnglab", "dngConverter", "dngs",
                                    "pendingARWs", "orphanBackups"])
        let dngs = try XCTUnwrap(json["dngs"] as? [NSDictionary])
        XCTAssertEqual(dngs.count, 2)
        for dng in dngs {
            XCTAssertEqual(keys(dng), ["name", "scale", "originalRawFileName", "hasBackup"])
        }
    }

    func testTheScanReportCarriesTheSnapshot() throws {
        let json = try object(scanReport())
        XCTAssertEqual(json, try parsed("""
            { "folder": "/Volumes/Card/Shoot 1", "writable": false,
              "exiftool": "/opt/homebrew/bin/exiftool", "dnglab": "/opt/homebrew/bin/dnglab",
              "dngConverter": "/Applications/Adobe DNG Converter.app/x",
              "dngs": [
                { "name": "a.dng", "scale": "1.5 1", "originalRawFileName": "a.ARW", "hasBackup": false },
                { "name": "junk.dng", "scale": null, "originalRawFileName": null, "hasBackup": true } ],
              "pendingARWs": ["b.ARW"], "orphanBackups": ["lost.dng_original"] }
            """))
    }

    // An unknown scale is `null`. It is not left out, and it is not "1 1".
    func testAnUnknownScaleAndAMissingConverterAreNull() throws {
        let json = try object(scanReport(converter: false))
        XCTAssertTrue(json["dngConverter"] is NSNull)
        XCTAssertEqual(json["dnglab"] as? String, "/opt/homebrew/bin/dnglab")
        // Each converter has its own key. A missing one is `null`, not left out.
        let noDnglab = try object(scanReport(dnglab: false))
        XCTAssertTrue(noDnglab["dnglab"] is NSNull)
        XCTAssertEqual(noDnglab["dngConverter"] as? String, "/Applications/Adobe DNG Converter.app/x")
        let junk = try XCTUnwrap((json["dngs"] as? [NSDictionary])?.last)
        XCTAssertTrue(junk["scale"] is NSNull)
        XCTAssertTrue(junk["originalRawFileName"] is NSNull)
    }

    // The example in design 12.1, with the `dnglab` key of design 13.6.
    func testTheScanExampleOfTheDesign() throws {
        let report = ScanReport(
            folder: "/path", writable: true, exiftool: "/opt/homebrew/bin/exiftool",
            dnglab: "/opt/homebrew/bin/dnglab", dngConverter: "/Applications/…",
            dngs: [.init(name: "a.dng", scale: "1.5 1", originalRawFileName: "a.ARW", hasBackup: false)],
            pendingARWs: ["b.ARW"], orphanBackups: [])
        XCTAssertEqual(try object(report), try parsed("""
            { "folder": "/path", "writable": true,
              "exiftool": "/opt/homebrew/bin/exiftool", "dnglab": "/opt/homebrew/bin/dnglab",
              "dngConverter": "/Applications/…",
              "dngs": [ { "name": "a.dng", "scale": "1.5 1", "originalRawFileName": "a.ARW", "hasBackup": false } ],
              "pendingARWs": ["b.ARW"], "orphanBackups": [] }
            """))
    }

    func testAScanReportIsEmptyOnlyWithNoDNGNoARWAndNoOrphan() {
        func report(dngs: Int = 0, arws: [String] = [], orphans: [String] = []) -> ScanReport {
            ScanReport(folder: "/path", writable: true, exiftool: "/x", dnglab: nil, dngConverter: nil,
                       dngs: (0..<dngs).map { .init(name: "\($0).dng", scale: nil, originalRawFileName: nil,
                                                    hasBackup: false) },
                       pendingARWs: arws, orphanBackups: orphans)
        }
        XCTAssertTrue(report().isEmpty)
        XCTAssertFalse(report(dngs: 1).isEmpty)
        XCTAssertFalse(report(arws: ["a.ARW"]).isEmpty)
        XCTAssertFalse(report(orphans: ["a.dng_original"]).isEmpty, "an orphan backup must be reported")
    }

    // MARK: The run report

    func summary() -> RunSummary {
        var summary = RunSummary()
        summary.convertedByDnglab = 1
        summary.set = 2
        summary.skipped = 3
        summary.blocked = 4
        summary.failed = 5
        summary.unconvertedARWs = 6
        summary.notes = [
            FileNote(name: "x.dng", kind: .failed, message: "Not changed.", detail: "Error: no"),
            .blockedByBackup("held.dng"),
        ]
        return summary
    }

    func testTheRunReportHasExactlyTheKeysOfTheDesignAndNoSteps() throws {
        let json = try object(RunReport(folder: folder, factor: factor, summary: summary()))
        XCTAssertEqual(keys(json), ["folder", "factor", "dryRun", "converted", "convertedByDnglab",
                                    "convertedByAdobe", "set", "skipped", "blocked", "failed", "stopped",
                                    "unconvertedARWs", "trashOriginals", "originalsInTrash", "notes"])
        for note in try XCTUnwrap(json["notes"] as? [NSDictionary]) {
            XCTAssertEqual(keys(note), ["name", "kind", "message", "detail"])
        }
    }

    // An empty folder changes the text, not the JSON (design 12.1).
    func testTheJSONOfARunOnAnEmptyFolderHasTheSameKeys() throws {
        var empty = RunSummary()
        empty.folderIsEmpty = true
        let report = RunReport(folder: folder, factor: factor, summary: empty)
        XCTAssertTrue(report.folderIsEmpty)
        XCTAssertEqual(keys(try object(report)), keys(try object(RunReport(folder: folder, factor: factor,
                                                                           summary: summary()))))
        XCTAssertTrue(RunReport(folder: folder, factor: factor, plan: RunPlan(steps: [], summary: empty)).folderIsEmpty)
        XCTAssertFalse(RunReport(folder: folder, factor: factor, summary: RunSummary()).folderIsEmpty)
    }

    // `folderIsEmpty` is in `==` and not in the JSON, so a decoded report
    // always has false. It is for the text of a front end only.
    func testFolderIsEmptyIsNotInTheJSONAndADecodedReportHasFalse() throws {
        var empty = RunSummary()
        empty.folderIsEmpty = true
        let report = RunReport(folder: folder, factor: factor, summary: empty)
        XCTAssertTrue(report.folderIsEmpty)
        let text = try ReportJSON.text(report)
        XCTAssertFalse(text.contains("folderIsEmpty"), "the key is not in the JSON")

        let decoded = try JSONDecoder().decode(RunReport.self, from: Data(text.utf8))
        XCTAssertFalse(decoded.folderIsEmpty)
        XCTAssertNotEqual(decoded, report, "the flag is part of ==, so the decoded copy differs")
    }

    func testTheRunReportCarriesTheSummary() throws {
        let json = try object(RunReport(folder: folder, factor: factor, summary: summary()))
        XCTAssertEqual(json, try parsed("""
            { "folder": "/Volumes/Card/Shoot 1", "factor": "1.5", "dryRun": false,
              "converted": 1, "convertedByDnglab": 1, "convertedByAdobe": 0,
              "set": 2, "skipped": 3, "blocked": 4, "failed": 5,
              "stopped": false, "unconvertedARWs": 6,
              "trashOriginals": false, "originalsInTrash": 0,
              "notes": [
                { "name": "x.dng", "kind": "failed", "message": "Not changed.", "detail": "Error: no" },
                { "name": "held.dng", "kind": "blockedByBackup",
                  "message": "Blocked. An older backup, held.dng_original, is beside this file. Move it away, then run again.",
                  "detail": null } ] }
            """))
    }

    // The two counts of design 13.6. Their sum is `converted`.
    func testTheRunReportCountsEachConverterAndTheirSum() throws {
        var summary = RunSummary()
        summary.convertedByDnglab = 5
        summary.convertedByAdobe = 2
        XCTAssertEqual(summary.converted, 7)
        let report = RunReport(folder: folder, factor: factor, summary: summary)
        XCTAssertEqual([report.converted, report.convertedByDnglab, report.convertedByAdobe], [7, 5, 2])
        let json = try object(report)
        XCTAssertEqual(json["converted"] as? Int, 7)
        XCTAssertEqual(json["convertedByDnglab"] as? Int, 5)
        XCTAssertEqual(json["convertedByAdobe"] as? Int, 2)
        XCTAssertEqual(report.countsLine, "7 converted · 0 set · 0 skipped · 0 failed", "one count for a person")

        let dry = RunReport(folder: folder, factor: factor, plan: RunPlan(steps: [], summary: summary))
        XCTAssertEqual([dry.converted, dry.convertedByDnglab, dry.convertedByAdobe], [7, 5, 2])
    }

    // The example in design 12.1, with the two counts of design 13.6 and the
    // two keys of design 14.3.
    func testTheRunExampleOfTheDesign() throws {
        var summary = RunSummary()
        summary.convertedByAdobe = 1
        summary.set = 2
        summary.notes = [FileNote(name: "x.dng", kind: .failed, message: "…", detail: nil)]
        let report = RunReport(folder: URL(fileURLWithPath: "/path"), factor: factor, summary: summary)
        XCTAssertEqual(try object(report), try parsed("""
            { "folder": "/path", "factor": "1.5", "dryRun": false,
              "converted": 1, "convertedByDnglab": 0, "convertedByAdobe": 1,
              "set": 2, "skipped": 0, "blocked": 0, "failed": 0,
              "stopped": false, "unconvertedARWs": 0,
              "trashOriginals": false, "originalsInTrash": 0,
              "notes": [ { "name": "x.dng", "kind": "failed", "message": "…", "detail": null } ] }
            """))
    }

    func testANoteWithNoDetailWritesNull() throws {
        var summary = RunSummary()
        summary.notes = [.orphanBackup(named: "gone.dng_original")]
        let json = try object(RunReport(folder: folder, factor: factor, summary: summary))
        let note = try XCTUnwrap((json["notes"] as? [NSDictionary])?.first)
        XCTAssertTrue(note["detail"] is NSNull)
        XCTAssertEqual(note["kind"] as? String, "orphanBackup")
    }

    func testEachKindIsWrittenAsItsName() throws {
        var summary = RunSummary()
        summary.notes = FileNote.Kind.allCases.map { FileNote(name: "n", kind: $0, message: "m", detail: nil) }
        let json = try object(RunReport(folder: folder, factor: factor, summary: summary))
        XCTAssertEqual((json["notes"] as? [NSDictionary])?.map { $0["kind"] as? String }, [
            "orphanBackup", "notConverted", "failed", "blockedByBackup", "leftoverBackup", "backupKept",
            "folderReadOnly", "convertedUnmatched", "originalKept", "noFolderLock",
        ])
    }

    func testAStoppedRunSaysSoAndRemoveWritesTheFactorAsOne() throws {
        var summary = RunSummary()
        summary.cancelled = true
        let json = try object(RunReport(folder: folder, factor: .noStretch, summary: summary))
        XCTAssertEqual(json["stopped"] as? Bool, true)
        XCTAssertEqual(json["factor"] as? String, "1")
    }

    func testADryRunReportIsTheSameObjectWithDryRunTrueAndSteps() throws {
        let plan = RunPlan(
            steps: [RunPlan.Step(name: "b.ARW", action: .convert, converter: .dnglab),
                    RunPlan.Step(name: "e.ARW", action: .convert, converter: .adobe),
                    RunPlan.Step(name: "a.dng", action: .write),
                    RunPlan.Step(name: "c.dng", action: .skip), RunPlan.Step(name: "d.dng", action: .blocked)],
            summary: summary())
        let json = try object(RunReport(folder: folder, factor: factor, plan: plan))

        XCTAssertEqual(keys(json), ["folder", "factor", "dryRun", "converted", "convertedByDnglab",
                                    "convertedByAdobe", "set", "skipped", "blocked", "failed", "stopped",
                                    "unconvertedARWs", "trashOriginals", "originalsInTrash", "notes", "steps"])
        XCTAssertEqual(json["dryRun"] as? Bool, true)
        // A `convert` step names its converter. No other step has the key.
        XCTAssertEqual(json["steps"] as? NSArray, try parsed("""
            { "steps": [ { "name": "b.ARW", "action": "convert", "converter": "dnglab" },
                         { "name": "e.ARW", "action": "convert", "converter": "adobe" },
                         { "name": "a.dng", "action": "write" },
                         { "name": "c.dng", "action": "skip" }, { "name": "d.dng", "action": "blocked" } ] }
            """)["steps"] as? NSArray)

        // Everything but those two keys is the report of the run.
        let real = NSMutableDictionary(dictionary: try object(RunReport(folder: folder, factor: factor,
                                                                        summary: summary())))
        let dry = NSMutableDictionary(dictionary: json)
        dry.removeObject(forKey: "steps")
        dry["dryRun"] = false
        XCTAssertEqual(dry, real)
    }

    func testADryRunWithNoStepStillHasTheStepsKey() throws {
        let json = try object(RunReport(folder: folder, factor: factor, plan: RunPlan(steps: [], summary: RunSummary())))
        XCTAssertEqual(json["steps"] as? NSArray, [])
        XCTAssertEqual(json["dryRun"] as? Bool, true)
    }

    func testTheReportsReadBackFromTheirOwnJSON() throws {
        let scan = scanReport(converter: false)
        let run = RunReport(folder: folder, factor: factor, summary: summary())
        let dry = RunReport(folder: folder, factor: factor,
                            plan: RunPlan(steps: [RunPlan.Step(name: "b.ARW", action: .convert, converter: .dnglab),
                                                  RunPlan.Step(name: "a.dng", action: .write)], summary: summary()))
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(ScanReport.self, from: Data(try ReportJSON.text(scan).utf8)), scan)
        XCTAssertEqual(try decoder.decode(RunReport.self, from: Data(try ReportJSON.text(run).utf8)), run)
        XCTAssertEqual(try decoder.decode(RunReport.self, from: Data(try ReportJSON.text(dry).utf8)), dry)
    }

    // The keys of a run report, in the order that every front end prints.
    func testTheRunJSONHasItsKeysInAlphabeticalOrder() throws {
        var summary = RunSummary()
        summary.convertedByDnglab = 1
        let plan = RunPlan(steps: [RunPlan.Step(name: "b.ARW", action: .convert, converter: .dnglab)],
                           summary: summary)
        XCTAssertEqual(try ReportJSON.text(RunReport(folder: URL(fileURLWithPath: "/path"), factor: factor, plan: plan)),
                       """
            {
              "blocked" : 0,
              "converted" : 1,
              "convertedByAdobe" : 0,
              "convertedByDnglab" : 1,
              "dryRun" : true,
              "factor" : "1.5",
              "failed" : 0,
              "folder" : "/path",
              "notes" : [],
              "originalsInTrash" : 0,
              "set" : 0,
              "skipped" : 0,
              "steps" : [
                {
                  "action" : "convert",
                  "converter" : "dnglab",
                  "name" : "b.ARW"
                }
              ],
              "stopped" : false,
              "trashOriginals" : false,
              "unconvertedARWs" : 0
            }
            """)
    }

    func testTheRunReportHasTheCountsLineOfItsSummary() {
        var summary = summary()
        summary.cancelled = true
        XCTAssertEqual(RunReport(folder: folder, factor: factor, summary: summary).countsLine, summary.countsLine)
        XCTAssertEqual(summary.countsLine, "1 converted · 2 set · 3 skipped · 4 blocked · 5 failed · stopped")
    }

    // MARK: The error report, and the text

    func testTheErrorReportHasBothKeys() throws {
        let json = try object(ErrorReport(error: "This folder could not be read.", detail: nil))
        XCTAssertEqual(keys(json), ["error", "detail"])
        XCTAssertTrue(json["detail"] is NSNull)
    }

    // One form, so two front ends print the same bytes: keys in order, one
    // key on each line, and a path as it is.
    func testTheJSONTextIsTheSameEveryTime() throws {
        let text = try ReportJSON.text(ErrorReport(error: "No /folder.", detail: "é"))
        XCTAssertEqual(text, """
            {
              "detail" : "é",
              "error" : "No /folder."
            }
            """)
        XCTAssertEqual(try ReportJSON.text(scanReport()), try ReportJSON.text(scanReport()))
    }

    // Foundation prints an empty list over three lines. A brace or a bracket
    // inside a name must stay as it is.
    func testAnEmptyListIsWrittenAsTwoBrackets() throws {
        let report = ScanReport(folder: "/a [\n  ] b", writable: true, exiftool: "/x", dnglab: "/y",
                                dngConverter: nil, dngs: [], pendingARWs: [], orphanBackups: ["[ ].dng_original"])
        XCTAssertEqual(try ReportJSON.text(report), """
            {
              "dngConverter" : null,
              "dnglab" : "/y",
              "dngs" : [],
              "exiftool" : "/x",
              "folder" : "/a [\\n  ] b",
              "orphanBackups" : [
                "[ ].dng_original"
              ],
              "pendingARWs" : [],
              "writable" : true
            }
            """)
        XCTAssertEqual(try JSONDecoder().decode(ScanReport.self, from: Data(try ReportJSON.text(report).utf8)), report)
    }
}
