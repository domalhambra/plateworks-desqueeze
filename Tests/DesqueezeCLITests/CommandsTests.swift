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
        XCTAssertEqual(h.out.lines, ["desqueeze 0.1.2"])
        XCTAssertEqual(h.out.lines, ["desqueeze \(DesqueezeVersion.current)"], "the number is in one place")
        XCTAssertEqual(h.err.lines, [])
    }

    func testHelpNamesTheFiveCommandLinesOfTheDesign() {
        XCTAssertEqual(h.run("--help"), 0)
        XCTAssertEqual(h.err.lines, [])
        for line in [
            "desqueeze scan <folder> [--json]",
            "desqueeze run <folder> --factor <number> [--no-convert] [--trash-originals]\n"
                + "                [--dry-run] [--json]",
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

    // The help says who converts the long way, from the core's sentence
    // (design 13.5): "dnglab converts first" is not the rule. It names three
    // tools, not two. The paragraph wraps, so the text is read on one line.
    func testHelpSaysWhoConvertsTheLongWayAndNotThatDnglabConvertsFirst() {
        h.run("--help")
        let text = h.out.lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        for words in [
            "where exiftool, dnglab and Adobe DNG Converter are",
            "dnglab converts each photo that it can match. "
                + "Adobe DNG Converter, when it is installed, converts the others.",
            "Each DNG that dnglab makes gets the values that Adobe DNG Converter writes, "
                + "so Lightroom shows the same photo.",
            "With no converter, run still sets the stretch on the DNG files.",
            "Install dnglab with: brew install dnglab",
        ] {
            XCTAssertTrue(text.contains(words), words)
        }
        XCTAssertTrue(text.contains(ConverterText.whoConverts), "the core's sentence")
        XCTAssertTrue(text.contains(ConverterText.matchedValues), "the core's sentence")
        XCTAssertFalse(text.contains("converts first"), text)
        XCTAssertFalse(text.contains("converts the ARW files"), text)
        XCTAssertFalse(text.contains("the two tools"), text)
    }

    // `--verbose` prints more than the commands: one line for each leftover
    // work file that a converter removed (`ConverterRules.removedLeftover`),
    // and one line with the error number when the volume gave no folder
    // lock (`FolderLock.noLockLine`, design 13.9). The help says so, where
    // it says what `--verbose` prints.
    func testHelpSaysWhatVerboseSaysBesideTheCommands() {
        h.run("--help")
        let text = h.out.lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        XCTAssertTrue(text.contains("Prints each exiftool and converter command, its exit code, and its output on "
            + "standard error. Also says when it removed a leftover work file, and the error number when the "
            + "volume gave no folder lock."), text)
    }

    // Control-C, and the Terminal window that closes (the tool takes the
    // hangup signal). The result so far is still printed.
    func testHelpSaysThatAClosedTerminalWindowStopsARunLikeControlC() {
        h.run("--help")
        let text = h.out.lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        XCTAssertTrue(text.contains("Control-C, or a closed Terminal window, stops a run after the current file, "
            + "and the result so far is still printed."), text)
    }

    // One run in a folder at a time (design 13.9). A scan and a dry run take
    // no lock, so the help says what they can show. One line, and the exit
    // code of a run that did not start.
    func testHelpSaysWhatAScanShowsWhileARunWorksAndThatASecondRunGivesOne() {
        h.run("--help")
        XCTAssertTrue(h.out.lines.contains("While a run works, a scan or a dry run can show a folder in change."),
                      h.out.text)
        let text = h.out.lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        XCTAssertTrue(text.contains("a run or a dry run met a read-only folder, another run works in the folder, "
            + "or exiftool is missing."), text)
    }

    // The core makes the sentences, and the help only wraps them. A word is
    // never cut, and no line is wider than the rule.
    func testWrappedBreaksAtSpacesAndNeverCutsAWord() {
        let text = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen " +
            "sixteen seventeen eighteen nineteen twenty"
        let lines = Usage.wrapped(text).split(separator: "\n").map(String.init)
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertEqual(lines.joined(separator: " "), text)
        XCTAssertTrue(lines.allSatisfy { $0.count <= Usage.helpWidth })
        XCTAssertEqual(Usage.wrapped("short"), "short")
        let longWord = String(repeating: "x", count: 100)
        XCTAssertEqual(Usage.wrapped("a \(longWord) b"), "a\n\(longWord)\nb")
    }

    // The rule is one sentence in the core. The help shows it on one line.
    func testHelpStatesTheFactorRuleOfTheCore() {
        h.run("--help")
        XCTAssertTrue(h.out.text.contains("  \(SqueezeFactor.ruleText).\n"), h.out.text)
    }

    func testHelpIsPlain() {
        h.run("--help")
        XCTAssertFalse(h.out.text.contains("!"))
        XCTAssertEqual(h.out.lines.filter { $0.count >= 80 }, [], "every line is under 80 columns")
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

    // MARK: One run in a folder at a time (design 13.9)

    // The test holds the lock that a run takes, as another run in this
    // process would. The lock is the system's own, on a temporary folder.
    func testARunWhileAnotherRunWorksInTheFolderGivesOneWithTheSentenceAndStartsNoProgram() throws {
        let sentence = "Another Desqueeze run is working in this folder. Wait for it to end, then run again."
        try h.touch("A.dng", "X.ARW")
        h.tools.scales = ["A.dng": "1 1"]
        guard case .held(let other) = FolderLock.system.take(h.shoot) else { return XCTFail("the lock of the test") }
        defer { other.release() }

        for arguments in [["run", "Shoot 1", "--factor", "1.5"], ["remove", "Shoot 1"]] {
            XCTAssertEqual(h.run(arguments), 1, "\(arguments)")
            XCTAssertEqual(h.err.lines, ["desqueeze: \(sentence)"], "\(arguments)")
            XCTAssertEqual(h.out.lines, [], "\(arguments)")
        }
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--json"), 1)
        let json = try h.json()
        XCTAssertEqual(json["error"] as? String, sentence)
        XCTAssertTrue(json["detail"] is NSNull, "the error object has both keys")
        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(h.tools.commands, [], "no call to exiftool and none to a converter")
        XCTAssertEqual(h.discarded.writes, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.shoot.path).sorted(), ["A.dng", "X.ARW"])

        // A scan and a dry run change no file, so they take no lock.
        XCTAssertEqual(h.run("scan", "Shoot 1"), 0)
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--dry-run"), 0)
        XCTAssertEqual(h.run("remove", "Shoot 1", "--dry-run"), 0)
        XCTAssertEqual(h.tools.scales, ["A.dng": "1 1"])

        // The other run ended.
        other.release()
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5"), 0)
        XCTAssertEqual(h.out.lines.first, "1 converted · 2 set · 0 skipped · 0 failed")
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
            "2 ARW files were not converted. No converter is installed.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])
    }

    // MARK: dnglab first (design 13)

    func testWithBothConvertersAFullMatchIsConvertedByDnglabAndAdobeIsNotStarted() throws {
        try h.touch("A.dng", "X.ARW")
        h.tools.scales = ["A.dng": "1 1"]
        h.tools.facts = ["X.ARW": FakeTools.adapted]
        h.hasDnglab = true

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual([json["converted"], json["convertedByDnglab"], json["convertedByAdobe"]] as? [Int], [1, 1, 0])
        XCTAssertEqual([json["set"], json["failed"], json["unconvertedARWs"]] as? [Int], [2, 0, 0])
        XCTAssertEqual(json["notes"] as? [NSDictionary], [])
        // dnglab writes a hidden work file, and the DNG gets its name last.
        XCTAssertTrue(h.tools.commands.contains("dnglab convert --embed-raw false X.ARW .X.desqueeze-work.dng"),
                      "\(h.tools.commands)")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.shoot.path).sorted(),
                       ["A.dng", "X.ARW", "X.dng"], "no work file stays")
        XCTAssertFalse(h.tools.commands.contains { $0.hasPrefix("Adobe") }, "\(h.tools.commands)")
        XCTAssertEqual(h.err.lines, ["1/3 X.ARW", "2/3 A.dng", "3/3 X.dng"], "one step for the conversion")
        XCTAssertEqual(try Data(contentsOf: h.shoot.appendingPathComponent("X.dng")), Data("converted by dnglab".utf8))
    }

    // A lens frame has no full match. With both installed it goes to Adobe.
    func testWithBothConvertersAnARWWithNoFullMatchIsConvertedByAdobe() throws {
        try h.touch("X.ARW", "Y.ARW")
        h.tools.facts = ["X.ARW": FakeTools.lens]
        h.hasDnglab = true

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual([json["converted"], json["convertedByDnglab"], json["convertedByAdobe"]] as? [Int], [2, 0, 2])
        XCTAssertFalse(h.tools.commands.contains { $0.hasPrefix("dnglab") }, "\(h.tools.commands)")
        XCTAssertEqual(json["notes"] as? [NSDictionary], [])
        // Adobe DNG Converter writes the same hidden work file that dnglab
        // writes, and the DNG gets its name last (design 13.3).
        XCTAssertEqual(h.tools.commands.filter { $0.hasPrefix("Adobe") }, [
            "Adobe DNG Converter -c -d Shoot 1 -o .X.desqueeze-work.dng X.ARW",
            "Adobe DNG Converter -c -d Shoot 1 -o .Y.desqueeze-work.dng Y.ARW",
        ])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.shoot.path).sorted(),
                       ["X.ARW", "X.dng", "Y.ARW", "Y.dng"], "no work file stays")
        XCTAssertEqual(try Data(contentsOf: h.shoot.appendingPathComponent("X.dng")), Data("converted".utf8))
    }

    // `--verbose` shows dnglab's command, and the exiftool commands of its
    // match: every program goes through the one logging runner.
    func testVerboseShowsTheDnglabCommandAndTheCommandsOfItsMatch() throws {
        try h.touch("X.ARW")
        h.tools.facts = ["X.ARW": FakeTools.adapted]
        h.hasDnglab = true

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1", "--json", "--verbose"), 0)

        XCTAssertEqual(try h.json()["convertedByDnglab"] as? Int, 1, "standard output is still one object")
        // The scan gives each file's path with its links resolved, so a
        // line is compared by how it starts and how it ends.
        let commands = h.err.lines.filter { $0.hasPrefix("$ ") }
        func isCommand(_ number: Int, _ start: String, _ end: String) -> Bool {
            commands.count > number && commands[number].hasPrefix(start) && commands[number].hasSuffix(end)
        }
        XCTAssertEqual(commands.count, 4, "the facts, dnglab, the match write, and its read-back: \(commands)")
        XCTAssertTrue(isCommand(0, "$ /fake/bin/exiftool -m -n -T -filename -IFD0:Model -ExifIFD:ISO "
            + "-SR2SubIFD:WB_RGBLevelsDaylight -SubIFD:DistortionCorrection -SubIFD:SonyRawFileType '/",
                                "/Shoot 1/X.ARW'"), "\(commands)")
        XCTAssertTrue(isCommand(1, "$ /fake/bin/dnglab convert --embed-raw false '/",
                                "/Shoot 1/.X.desqueeze-work.dng'"), "\(commands)")
        XCTAssertTrue(commands.count > 1 && commands[1].contains("/Shoot 1/X.ARW' '/"), "\(commands)")
        XCTAssertTrue(isCommand(2, "$ /fake/bin/exiftool -m -overwrite_original -SubIFD:WhiteLevel=16383 ",
                                "/Shoot 1/.X.desqueeze-work.dng'"), "\(commands)")
        XCTAssertTrue(commands.count > 2 && commands[2].contains(" -IFD0:OriginalRawFileName=X.ARW '/"), "\(commands)")
        XCTAssertTrue(isCommand(3, "$ /fake/bin/exiftool -m -n -T -SubIFD:WhiteLevel ",
                                "/Shoot 1/.X.desqueeze-work.dng'"), "\(commands)")
        XCTAssertTrue(h.err.lines.contains("  stdout: X.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\t2"))
        XCTAssertTrue(h.err.lines.contains("1/2 X.ARW"), "progress is still there")
    }

    // A run that ended hard left the hidden work file of X.ARW. The next run
    // removes it before the converter starts. `--verbose` says so on
    // standard error, where the commands are, before the converter's own
    // command. Without `--verbose` the run says nothing about it.
    func testVerboseSaysThatALeftoverWorkFileWasRemovedBeforeTheConverterStarts() throws {
        for withDnglab in [true, false] {
            try h.touch("X.ARW", ".X.desqueeze-work.dng")
            h.tools.facts = ["X.ARW": FakeTools.adapted]
            h.hasDnglab = withDnglab
            h.discarded.writes = []
            let line = "Removed a leftover work file: .X.desqueeze-work.dng"

            XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1", "--json", "--verbose"), 0)

            XCTAssertEqual(try h.json()["converted"] as? Int, 1, "standard output is still one object")
            XCTAssertEqual(h.discarded.writes, [".X.desqueeze-work.dng"], "the leftover went to the Trash")
            XCTAssertEqual(h.err.lines.filter { $0.hasPrefix("Removed") }, [line], "dnglab \(withDnglab)")
            let said = try XCTUnwrap(h.err.lines.firstIndex(of: line))
            let converter = try XCTUnwrap(h.err.lines.firstIndex {
                $0.hasPrefix(withDnglab ? "$ /fake/bin/dnglab convert" : "$ '/fake/Adobe DNG Converter' -c")
            }, "\(h.err.lines)")
            XCTAssertLessThan(said, converter, "the line stands before the command of the converter")

            // The same folder state, without `--verbose`.
            try FileManager.default.removeItem(at: h.shoot.appendingPathComponent("X.dng"))
            try h.touch(".X.desqueeze-work.dng")
            XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1", "--json"), 0)
            XCTAssertEqual(h.err.lines.filter { $0.contains("leftover") }, [], "dnglab \(withDnglab)")
            try FileManager.default.removeItem(at: h.shoot.appendingPathComponent("X.dng"))
        }
    }

    // dnglab alone, and a frame with no full match: converted, with a note.
    // The file is not failed and not blocked, so the exit code stays 0.
    func testWithDnglabAloneAnARWWithNoFullMatchIsConvertedWithANoteAndTheExitCodeIsZero() throws {
        try h.touch("X.ARW")
        h.tools.facts = ["X.ARW": FakeTools.lens]
        h.hasDnglab = true
        h.hasConverter = false

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual([json["converted"], json["convertedByDnglab"], json["convertedByAdobe"]] as? [Int], [1, 1, 0])
        XCTAssertEqual([json["set"], json["failed"], json["blocked"], json["unconvertedARWs"]] as? [Int], [1, 0, 0, 0])
        XCTAssertEqual(json["notes"] as? [NSDictionary], [[
            "name": "X.dng", "kind": "convertedUnmatched",
            "message": "Converted. The DNG has no built-in lens correction. "
                + "Install Adobe DNG Converter for the same file that Lightroom makes.",
            "detail": "The ARW holds lens-correction data, and dnglab does not write it into the DNG.",
        ]])

        // The same as a dry run: the same note, the same code.
        try FileManager.default.removeItem(at: h.shoot.appendingPathComponent("X.dng"))
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--dry-run", "--json"), 0)
        let dry = try h.json()
        XCTAssertEqual(dry["notes"] as? [NSDictionary], json["notes"] as? [NSDictionary])
        XCTAssertEqual(dry["steps"] as? [NSDictionary], [
            ["name": "X.ARW", "action": "convert", "converter": "dnglab"], ["name": "X.dng", "action": "write"],
        ])
    }

    // "Adobe DNG Converter is not installed" is the reason for the ARW files
    // that a run left only when neither converter is there.
    func testWithDnglabAloneTheARWLineDoesNotSayThatAdobeIsNotInstalled() throws {
        try h.touch("A.dng", "X.ARW")
        h.tools.scales = ["A.dng": "1 1"]
        h.hasDnglab = true
        h.hasConverter = false

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--no-convert"), 0)
        XCTAssertEqual(h.out.lines, [
            "1 set · 0 skipped · 0 failed",
            "1 ARW file was not converted.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])

        XCTAssertEqual(h.run("scan", "Shoot 1"), 0)
        XCTAssertEqual(Array(h.out.lines.suffix(4)), [
            "exiftool: /fake/bin/exiftool",
            "dnglab: /fake/bin/dnglab",
            "Adobe DNG Converter: not installed",
            "Adobe DNG Converter is not installed. It is an optional backup for photos that dnglab cannot match.",
        ])
        XCTAssertFalse(h.out.text.contains("cannot be converted"), h.out.text)
    }

    // The scan text of the tool in the other three states of design 13.5.
    func testTheScanTextNamesTheThreeToolsAndGivesTheAdviceOfEachState() throws {
        try h.touch("A.dng", "X.ARW")
        h.tools.scales = ["A.dng": "1 1"]

        h.hasDnglab = true
        XCTAssertEqual(h.run("scan", "Shoot 1"), 0)
        XCTAssertEqual(Array(h.out.lines.suffix(4)), [
            "",
            "exiftool: /fake/bin/exiftool",
            "dnglab: /fake/bin/dnglab",
            "Adobe DNG Converter: /fake/Adobe DNG Converter",
        ], "both converters: no advice")

        h.hasDnglab = false
        XCTAssertEqual(h.run("scan", "Shoot 1"), 0)
        XCTAssertEqual(Array(h.out.lines.suffix(4)), [
            "exiftool: /fake/bin/exiftool",
            "dnglab: not installed",
            "Adobe DNG Converter: /fake/Adobe DNG Converter",
            "dnglab is faster and opens no window. Install it with: brew install dnglab",
        ])

        h.hasConverter = false
        XCTAssertEqual(h.run("scan", "Shoot 1"), 0, "a scan that completed gives 0, also with no converter")
        XCTAssertEqual(Array(h.out.lines.suffix(5)), [
            "exiftool: /fake/bin/exiftool",
            "dnglab: not installed",
            "Adobe DNG Converter: not installed",
            "1 ARW cannot be converted: no converter is installed",
            "Install dnglab with: brew install dnglab",
        ])
    }

    // The text of a dry run and of a run with both converters at work: a
    // full match goes to dnglab, and a lens frame to Adobe DNG Converter.
    func testTheTextOfADryRunNamesEachConverterAndTheRunSaysHowManyEachConverted() throws {
        try h.touch("X.ARW", "Y.ARW")
        h.tools.facts = ["X.ARW": FakeTools.adapted, "Y.ARW": FakeTools.lens]
        h.hasDnglab = true

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--dry-run"), 0)
        XCTAssertEqual(h.out.lines, [
            "Dry run. No file was changed.",
            "  convert  X.ARW  with dnglab",
            "  convert  Y.ARW  with Adobe DNG Converter",
            "  write    X.dng",
            "  write    Y.dng",
            "A run would give: 2 converted · 2 set · 0 skipped · 0 failed",
        ])

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5"), 0)
        XCTAssertEqual(h.out.lines, [
            "2 converted · 2 set · 0 skipped · 0 failed",
            "Converted with dnglab: 1. With Adobe DNG Converter: 1.",
            "Photos already in Lightroom: Metadata › Read Metadata from File.",
        ])
    }

    func testScanJSONSaysWhereEachConverterIs() throws {
        try h.touch("A.dng")
        h.tools.scales = ["A.dng": "1 1"]
        XCTAssertEqual(h.run("scan", "Shoot 1", "--json"), 0)
        var json = try h.json()
        XCTAssertTrue(json["dnglab"] is NSNull)
        XCTAssertEqual(json["dngConverter"] as? String, "/fake/Adobe DNG Converter")

        h.hasDnglab = true
        h.hasConverter = false
        XCTAssertEqual(h.run("scan", "Shoot 1", "--json"), 0)
        json = try h.json()
        XCTAssertEqual(json["dnglab"] as? String, "/fake/bin/dnglab")
        XCTAssertTrue(json["dngConverter"] is NSNull)
    }

    // The dry run reads the facts to name the converter. It starts no
    // converter and changes no file.
    func testADryRunWithDnglabReadsTheFactsNamesTheConverterAndChangesNoFile() throws {
        try h.touch("A.dng", "X.ARW", "Y.ARW")
        h.tools.scales = ["A.dng": "1 1"]
        h.tools.facts = ["X.ARW": FakeTools.adapted, "Y.ARW": FakeTools.lens]
        h.hasDnglab = true

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--dry-run", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual(json["steps"] as? [NSDictionary], [
            ["name": "X.ARW", "action": "convert", "converter": "dnglab"],
            ["name": "Y.ARW", "action": "convert", "converter": "adobe"],
            ["name": "A.dng", "action": "write"], ["name": "X.dng", "action": "write"],
            ["name": "Y.dng", "action": "write"],
        ])
        XCTAssertEqual([json["converted"], json["convertedByDnglab"], json["convertedByAdobe"]] as? [Int], [2, 1, 1])
        XCTAssertEqual(h.tools.commands.count, 2, "the scan's read, and the read of the facts: \(h.tools.commands)")
        XCTAssertTrue(h.tools.commands.allSatisfy { $0.hasPrefix("exiftool ") })
        XCTAssertEqual(h.err.lines, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.shoot.path).sorted(),
                       ["A.dng", "X.ARW", "Y.ARW"])
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
