import DesqueezeCore
import XCTest
@testable import DesqueezeCLI

/// The tool from its arguments to its exit code, with fake tools.
final class CommandsTests: XCTestCase {
    var h: ToolHarness!

    override func setUpWithError() throws { h = try ToolHarness() }
    override func tearDown() { h.cleanUp() }

    // MARK: Version, help, and usage errors

    func testVersionPrintsTheNameAndTheNumber() {
        XCTAssertEqual(h.run("--version"), 0)
        XCTAssertEqual(h.out.lines, ["desqueeze 0.1.0"])
        XCTAssertEqual(h.out.lines, ["desqueeze \(DesqueezeVersion.current)"], "the number is in one place")
        XCTAssertEqual(h.err.lines, [])
    }

    func testHelpNamesTheFiveCommandLinesOfTheDesign() {
        XCTAssertEqual(h.run("--help"), 0)
        XCTAssertEqual(h.err.lines, [])
        for line in [
            "desqueeze scan <folder> [--json]",
            "desqueeze run <folder> --factor <number> [--no-convert] [--dry-run] [--json]",
            "desqueeze remove <folder> [--dry-run] [--json]",
            "desqueeze --version",
            "desqueeze --help",
        ] {
            XCTAssertTrue(h.out.text.contains("  \(line)\n"), line)
        }
        for word in ["--verbose", "--factor <number>", "--no-convert", "--dry-run", "--json", "standard error",
                     "There is no default"] {
            XCTAssertTrue(h.out.text.contains(word), word)
        }
        XCTAssertFalse(h.out.text.contains(FileBackups.testFolderVariable), "the test variable is in no help text")
    }

    // The rule is one sentence in the core. The help shows it on one line.
    func testHelpStatesTheFactorRuleOfTheCore() {
        h.run("--help")
        XCTAssertTrue(h.out.text.contains("  \(SqueezeFactor.ruleText).\n"), h.out.text)
    }

    func testHelpIsPlain() {
        h.run("--help")
        XCTAssertFalse(h.out.text.contains("!"))
        XCTAssertEqual(h.out.lines.filter { $0.count > 80 }, [], "no line is over 80 columns")
        // Sentence case: a heading has one capital, and the text starts with one.
        XCTAssertEqual(h.out.lines.filter { $0.hasSuffix(":") && !$0.hasPrefix(" ") },
                       ["Usage:", "Commands:", "Options:", "Exit codes:"])
        XCTAssertEqual(h.out.lines.first?.first?.isUppercase, true)
        XCTAssertEqual(h.out.writes.count, 1)
    }

    func testTheExitCodesInTheHelpAreTheOnesOfTheDesign() {
        h.run("--help")
        XCTAssertTrue(h.out.text.contains("  0  The command completed, no file failed, and no file was blocked."))
        XCTAssertTrue(h.out.text.contains("  1  A file failed or was blocked"))
        XCTAssertTrue(h.out.text.contains("  2  The command line was wrong."))
    }

    func testAUsageErrorPrintsTheReasonAndOneLineThatPointsToHelpAndRunsNothing() throws {
        try h.touch("A.dng")
        XCTAssertEqual(h.run("run", "Shoot 1"), 2)
        XCTAssertEqual(h.err.lines, ["desqueeze: run needs --factor <number>. There is no default.",
                                     "See desqueeze --help."])
        XCTAssertEqual(h.out.lines, [])
        XCTAssertEqual(h.tools.commands, [], "a usage error starts no tool")

        XCTAssertEqual(h.run("scan", "Shoot 1", "--frob", "--json"), 2)
        XCTAssertEqual(h.err.lines, ["desqueeze: Unknown option: --frob", "See desqueeze --help."])
        XCTAssertEqual(h.out.lines, [], "a usage error prints no JSON")
        XCTAssertEqual(h.tools.commands, [])
    }

    // MARK: The folder

    func testARelativeFolderIsResolvedAgainstTheWorkingFolder() throws {
        try h.touch("A.dng")
        for path in ["Shoot 1", "./Shoot 1", "Shoot 1/../Shoot 1/"] {
            XCTAssertEqual(h.run("scan", path, "--json"), 0, path)
            XCTAssertEqual(try h.json()["folder"] as? String, h.shoot.path, path)
        }
        XCTAssertEqual(h.run("scan", h.shoot.path, "--json"), 0)
        XCTAssertEqual(try h.json()["folder"] as? String, h.shoot.path)
    }

    // `resolve` makes the path absolute, and nothing else: only `.` and `..`
    // are taken out. `/private/tmp` does not turn into `/tmp` here. What the
    // path names is `FolderChoice`'s to decide, next, as it is for the window.
    func testAFolderPathIsMadeAbsoluteAndNothingElse() {
        let working = URL(fileURLWithPath: "/private/tmp/Work Folder")
        func resolved(_ folder: String) -> String { DesqueezeTool.resolve(folder, against: working).path }
        XCTAssertEqual(resolved("Shoot 1"), "/private/tmp/Work Folder/Shoot 1")
        XCTAssertEqual(resolved("./Shoot 1/"), "/private/tmp/Work Folder/Shoot 1")
        XCTAssertEqual(resolved("../Other/./Shoot 1"), "/private/tmp/Other/Shoot 1")
        XCTAssertEqual(resolved("."), "/private/tmp/Work Folder")
        XCTAssertEqual(resolved("/private/tmp/Shoot 1"), "/private/tmp/Shoot 1")
        XCTAssertEqual(resolved("/Volumes/Card//DCIM/../Shoot 1/"), "/Volumes/Card/Shoot 1")
        XCTAssertEqual(resolved("/../.."), "/")
        XCTAssertEqual(resolved("~/Shoot"), "/private/tmp/Work Folder/~/Shoot", "the shell expands a tilde, not the tool")
    }

    func testAFolderThatDoesNotExistGivesOneAndChangesNothing() throws {
        let missing = h.base.appendingPathComponent("No such folder").path
        XCTAssertEqual(h.run("scan", "No such folder"), 1)
        XCTAssertEqual(h.out.lines, [])
        XCTAssertEqual(h.err.lines.first, "desqueeze: This folder could not be read: \(missing)")
        XCTAssertEqual(h.err.lines.count, 2, "the reason, and the system's own words below it")

        XCTAssertEqual(h.run("run", "No such folder", "--factor", "1.5", "--json"), 1)
        let json = try h.json()
        XCTAssertEqual(json["error"] as? String, "This folder could not be read: \(missing)")
        XCTAssertNotNil(json["detail"] as? String)
        XCTAssertEqual(h.tools.commands, [])
    }

    // The window takes a link to a folder as that folder (`FolderChoice`), and
    // the tool follows it: the report names the folder, not the link.
    func testALinkToAFolderIsThatFolder() throws {
        try h.touch("A.dng")
        h.tools.scales = ["A.dng": "1 1"]
        let link = h.base.appendingPathComponent("Link to shoot")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: h.shoot)
        let target = h.shoot.resolvingSymlinksInPath().path

        for path in ["Link to shoot", link.path] {
            XCTAssertEqual(h.run("scan", path, "--json"), 0, path)
            let folder = try XCTUnwrap(try h.json()["folder"] as? String)
            XCTAssertEqual(folder, target, path)
            XCTAssertEqual(URL(fileURLWithPath: folder).lastPathComponent, "Shoot 1")
        }
        XCTAssertEqual(h.run("run", "Link to shoot", "--factor", "1.5", "--json"), 0)
        XCTAssertEqual(try h.json()["set"] as? Int, 1)
        XCTAssertEqual(h.tools.scales, ["A.dng": "1.5 1"])
        XCTAssertEqual(h.run("remove", "Link to shoot", "--dry-run"), 0)
    }

    // A file, a package, and a link to either are not folders to the window.
    // The tool gives its "could not be read" error and exit 1, and starts no tool.
    func testAPathThatIsNotAFolderTheWindowTakesGivesTheCouldNotBeReadError() throws {
        try h.touch("A.dng")
        let app = h.base.appendingPathComponent("Thing.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: h.base.appendingPathComponent("Link to file"),
                                                   withDestinationURL: h.shoot.appendingPathComponent("A.dng"))
        try FileManager.default.createSymbolicLink(at: h.base.appendingPathComponent("Link to app"),
                                                   withDestinationURL: app)
        try FileManager.default.createSymbolicLink(at: h.base.appendingPathComponent("Dangling"),
                                                   withDestinationURL: h.base.appendingPathComponent("gone"))

        for name in ["Shoot 1/A.dng", "Thing.app", "Link to file", "Link to app", "Dangling"] {
            for arguments in [["scan", name], ["run", name, "--factor", "1.5"], ["remove", name, "--dry-run"]] {
                XCTAssertEqual(DesqueezeTool.run(arguments, in: h.environment), 1, "\(arguments)")
            }
            XCTAssertEqual(h.run("scan", name, "--json"), 1, name)
            let json = try h.json()
            XCTAssertEqual(json["error"] as? String,
                           "This folder could not be read: \(h.base.path)/\(name)", name)
            XCTAssertNotNil(json["detail"] as? String)
            XCTAssertEqual(h.err.lines.count, 2, name)
        }
        XCTAssertEqual(h.tools.commands, [], "no tool ran")
        XCTAssertEqual(h.discarded.lines, [])
    }

    // MARK: The tools

    func testWithNoExiftoolEveryCommandGivesOneAndTheInstallCommand() throws {
        try h.touch("A.dng")
        h.hasExiftool = false
        let message = "Desqueeze needs exiftool, and it is not installed. Install it with: brew install exiftool"
        for arguments in [["scan", "Shoot 1"], ["run", "Shoot 1", "--factor", "1.5"], ["remove", "Shoot 1"],
                          ["run", "Shoot 1", "--factor", "1.5", "--dry-run"]] {
            XCTAssertEqual(DesqueezeTool.run(arguments, in: h.environment), 1, "\(arguments)")
        }
        XCTAssertEqual(h.run("remove", "Shoot 1"), 1)
        XCTAssertEqual(h.err.lines, ["desqueeze: \(message)"])
        XCTAssertEqual(h.out.lines, [])
        XCTAssertEqual(h.run("scan", "Shoot 1", "--json"), 1)
        XCTAssertEqual(try h.json()["error"] as? String, message)
        XCTAssertEqual(h.tools.commands, [])
        // Help and the version need no tool.
        XCTAssertEqual(h.run("--help"), 0)
        XCTAssertEqual(h.run("--version"), 0)
    }

    func testWithNoConverterRunTagsTheDNGFilesSaysHowManyARWFilesItLeftAndGivesZero() throws {
        try h.touch("A.dng", "X.ARW", "Y.ARW")
        h.tools.scales = ["A.dng": "1 1"]
        h.hasConverter = false

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual(json["unconvertedARWs"] as? Int, 2)
        XCTAssertEqual(json["set"] as? Int, 1)
        XCTAssertEqual(json["converted"] as? Int, 0)
        XCTAssertEqual(json["failed"] as? Int, 0)
        XCTAssertFalse(h.tools.commands.contains { $0.hasPrefix("Adobe") })

        h.tools.scales = ["A.dng": "1 1"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5"), 0)
        XCTAssertEqual(h.out.lines, [
            "1 set · 0 skipped · 0 failed",
            "2 ARW files were not converted. Adobe DNG Converter is not installed.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])
    }

    // MARK: JSON, text, and standard error

    func testJSONModePrintsOneObjectOnStandardOutputAndProgressOnStandardError() throws {
        try h.touch("A.dng", "X.ARW")
        h.tools.scales = ["A.dng": "1 1"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--json"), 0)

        let json = try h.json()
        XCTAssertEqual(json["dryRun"] as? Bool, false)
        XCTAssertEqual(json["factor"] as? String, "1.5")
        XCTAssertEqual([json["converted"], json["set"], json["skipped"], json["blocked"], json["failed"]] as? [Int],
                       [1, 2, 0, 0, 0])
        XCTAssertNil(json["steps"])
        XCTAssertEqual(h.err.lines, ["1/3 X.ARW", "2/3 A.dng", "3/3 X.dng"])
        XCTAssertEqual(h.discarded.lines, ["A.dng_original", "X.dng_original"])
    }

    func testTextModePrintsTheResultOnStandardOutputAndTheSameProgressOnStandardError() throws {
        try h.touch("A.dng", "B.dng")
        h.tools.scales = ["A.dng": "1 1", "B.dng": "1.5 1"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5"), 0)
        XCTAssertEqual(h.out.lines, ["1 set · 1 skipped · 0 failed",
                                     "Photos already in Lightroom: Metadata › Read Metadata from File."])
        XCTAssertEqual(h.err.lines, ["1/2 A.dng", "2/2 B.dng"])
    }

    func testVerbosePrintsEachCommandOnStandardErrorAndLeavesStandardOutputAsItWas() throws {
        try h.touch("A.dng")
        h.tools.scales = ["A.dng": "1 1"]
        XCTAssertEqual(h.run("scan", "Shoot 1", "--json"), 0)
        let quiet = h.out.lines
        XCTAssertEqual(h.err.lines, [])

        XCTAssertEqual(h.run("scan", "Shoot 1", "--json", "--verbose"), 0)
        XCTAssertEqual(h.out.lines, quiet)
        XCTAssertEqual(h.err.lines, [
            "$ /fake/bin/exiftool -m -T -filename -SubIFD:DefaultScale -OriginalRawFileName -ext dng '\(h.shoot.path)'",
            "  exit 0",
            "  stdout: A.dng\t1 1\t-",
        ])

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--verbose"), 0)
        XCTAssertTrue(h.err.lines.contains { $0.hasPrefix("$ /fake/bin/exiftool -m '-SubIFD:DefaultScale=1.5 1' ") })
        XCTAssertTrue(h.err.lines.contains("  stdout:     1 image files updated"))
        XCTAssertTrue(h.err.lines.contains("1/1 A.dng"), "progress is still there")
    }

    func testADryRunStartsNoToolThatWritesAndPrintsNoProgress() throws {
        try h.touch("A.dng", "X.ARW")
        h.tools.scales = ["A.dng": "1 1"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--dry-run", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual(json["dryRun"] as? Bool, true)
        XCTAssertEqual((json["steps"] as? [NSDictionary])?.map { "\($0["action"] ?? "") \($0["name"] ?? "")" },
                       ["convert X.ARW", "write A.dng", "write X.dng"])
        XCTAssertEqual(h.tools.commands.count, 1, "the scan's one read")
        XCTAssertTrue(h.tools.commands[0].contains(" -T "))
        XCTAssertEqual(h.err.lines, [])
        XCTAssertEqual(h.discarded.lines, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.shoot.path).sorted(), ["A.dng", "X.ARW"])

        XCTAssertEqual(h.run("remove", "Shoot 1", "--dry-run", "--json"), 0)
        XCTAssertEqual(try h.json()["factor"] as? String, "1")
        XCTAssertEqual(h.tools.commands.count, 2)
    }

    func testRemoveWritesNoStretchAndConvertsNothing() throws {
        try h.touch("A.dng", "X.ARW")
        h.tools.scales = ["A.dng": "1.5 1"]
        XCTAssertEqual(h.run("remove", "Shoot 1", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual(json["factor"] as? String, "1")
        XCTAssertEqual(json["set"] as? Int, 1)
        XCTAssertEqual(json["unconvertedARWs"] as? Int, 0)
        XCTAssertEqual(h.tools.scales, ["A.dng": "1 1"])
        XCTAssertFalse(h.tools.commands.contains { $0.hasPrefix("Adobe") })
    }

    func testNoConvertLeavesTheARWFilesAlone() throws {
        try h.touch("A.dng", "X.ARW")
        h.tools.scales = ["A.dng": "1 1"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "2", "--no-convert", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual(json["converted"] as? Int, 0)
        XCTAssertEqual(json["unconvertedARWs"] as? Int, 1)
        XCTAssertFalse(h.tools.commands.contains { $0.hasPrefix("Adobe") })
        XCTAssertEqual(h.tools.scales, ["A.dng": "2 1"])
    }

    // Remove is an intent. `run --factor 1 --no-convert` does the same work as
    // `remove`, and still reports the ARW files it left (design 12.1).
    func testRunAtFactorOneWithNoConvertIsNotRemove() throws {
        try h.touch("A.dng", "X.ARW")
        h.tools.scales = ["A.dng": "1.5 1"]
        for extra in [[], ["--dry-run"]] {
            h.tools.scales = ["A.dng": "1.5 1"]
            XCTAssertEqual(h.run(["run", "Shoot 1", "--factor", "1", "--no-convert", "--json"] + extra), 0)
            XCTAssertEqual(try h.json()["unconvertedARWs"] as? Int, 1, "\(extra)")
            XCTAssertEqual(h.run(["remove", "Shoot 1", "--json"] + extra), 0)
            XCTAssertEqual(try h.json()["unconvertedARWs"] as? Int, 0, "\(extra)")
        }
        h.tools.scales = ["A.dng": "1.5 1"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1", "--no-convert"), 0)
        XCTAssertTrue(h.out.lines.contains("1 ARW file was not converted."), h.out.text)
        h.tools.scales = ["A.dng": "1.5 1"]
        XCTAssertEqual(h.run("remove", "Shoot 1"), 0)
        XCTAssertFalse(h.out.text.contains("ARW"))
    }
}
