import DesqueezeCore
import XCTest

/// The built tool with the real exiftool and the real converters. Each test
/// asserts on standard output, standard error, and the exit code. Skips when
/// a fixture, exiftool or Adobe DNG Converter is absent.
///
/// The fixture ARW can be any Sony ARW, so no test here holds a number of
/// one frame. Which converter gets the ARW comes from the frame itself
/// (design 13.4): dnglab, when it is installed and the frame has a full
/// match. Adobe DNG Converter for every other frame, and with no dnglab.
/// These tests skip without Adobe DNG Converter, so one of the two converts.
final class EndToEndTests: BuiltToolTestCase {
    /// The facts of the fixture ARW, as the product's own reader gives them.
    /// The read changes no file.
    var fixtureFacts: ARWFacts {
        let arw = Self.fixtures.appendingPathComponent("sample.ARW")
        return ToolLocator().exiftool().flatMap { ARWFactsReader(exiftool: $0).read([arw])["sample.ARW"] } ?? .none
    }

    /// True when dnglab gets the fixture ARW on this Mac.
    ///
    /// This expectation is taken from the product: `AdobeMatch` says whether
    /// the frame is a full match. So a test that uses it pins the choice
    /// and the wiring: the built tool gives the ARW to the converter that
    /// the core's rule names, and its report and its commands say so. It
    /// does not pin the match itself. That is pinned in the core's tests:
    /// the table test, `AdobeMatchTests.testTheTableIsTheDataFile`, and the
    /// drift check, `AdobeDriftTests`.
    var dnglabConverts: Bool { ToolLocator().dnglab() != nil && AdobeMatch.match(fixtureFacts).isFull }

    /// The converter that gets the fixture ARW on this Mac.
    var firstConverter: String { dnglabConverts ? "dnglab" : "adobe" }

    /// The two counts of design 13.6, for one ARW converted on this Mac.
    var oneConversion: [Int] { dnglabConverts ? [1, 0] : [0, 1] }

    // MARK: scan

    func testScanJSON() throws {
        try makeShoot()
        let before = try folderState()

        let result = try desqueeze("scan", folder.path, "--json")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.messages, [], "a scan has no progress")
        let json = try result.json()
        XCTAssertEqual(Set(json.allKeys.compactMap { $0 as? String }),
                       ["folder", "writable", "exiftool", "dnglab", "dngConverter", "dngs", "pendingARWs",
                        "orphanBackups"])
        XCTAssertEqual(json["folder"] as? String, folder.path)
        XCTAssertEqual(json["writable"] as? Bool, true)
        XCTAssertEqual(json["exiftool"] as? String, ToolLocator().exiftool()?.path)
        XCTAssertEqual(json["dnglab"] as? String, ToolLocator().dnglab()?.path, "the path, or null")
        XCTAssertEqual(json["dngConverter"] as? String, ToolLocator().dngConverter()?.path)
        XCTAssertEqual(json["dngs"] as? [NSDictionary], [[
            "name": "already here.dng", "scale": "1 1", "originalRawFileName": "sample.ARW", "hasBackup": false,
        ]])
        XCTAssertEqual(json["pendingARWs"] as? [String], ["frame.ARW"])
        XCTAssertEqual(json["orphanBackups"] as? [String], [])
        XCTAssertEqual(try folderState(), before)
    }

    func testScanTextIsATableThenTheARWFilesThenTheTools() throws {
        try makeShoot()
        try Data("a lost photo".utf8).write(to: folder.appendingPathComponent("lost.dng_original"))

        let result = try desqueeze("scan", folder.path)

        // On a Mac with no dnglab, the line of advice follows the tools.
        let dnglab = ToolLocator().dnglab()
        let advice = dnglab == nil
            ? "dnglab is faster and opens no window. Install it with: brew install dnglab\n" : ""
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, """
            \(folder.path)

            DNG files: 1
              Name              Scale
              already here.dng  1 1

            ARW files with no DNG: 1
              frame.ARW

            lost.dng_original: A backup with no DNG beside it. Rename it to lost.dng to get the photo back.

            exiftool: \(try XCTUnwrap(ToolLocator().exiftool()).path)
            dnglab: \(dnglab?.path ?? "not installed")
            Adobe DNG Converter: \(try XCTUnwrap(ToolLocator().dngConverter()).path)
            \(advice)
            """)
    }

    // A relative folder is resolved against the working folder. The system
    // gives the working folder with its links resolved, so the two paths are
    // compared that way.
    func testARelativeFolderIsResolvedAgainstTheWorkingFolder() throws {
        try makeShoot()
        func reported(_ path: String, in workingFolder: URL) throws -> String {
            let result = try desqueeze("scan", path, "--json", workingFolder: workingFolder)
            XCTAssertEqual(result.exitCode, 0, path)
            let folder = try XCTUnwrap(try result.json()["folder"] as? String)
            XCTAssertTrue(folder.hasPrefix("/"), folder)
            XCTAssertFalse(folder.contains("/./") || folder.hasSuffix("/"), folder)
            return URL(fileURLWithPath: folder).resolvingSymlinksInPath().path
        }
        let expected = folder.resolvingSymlinksInPath().path
        XCTAssertEqual(try reported("Shoot with spaces", in: base), expected)
        XCTAssertEqual(try reported("./Shoot with spaces/", in: base), expected)
        XCTAssertEqual(try reported(".", in: folder), expected)
        XCTAssertEqual(try reported("../Shoot with spaces", in: discard), expected)
    }

    // A symbolic link to a folder is that folder, as in the window. The report
    // names the folder, not the link, and the run changes the files inside it.
    func testALinkToAFolderIsThatFolderForEveryCommand() throws {
        try makeShoot()
        let link = base.appendingPathComponent("Link to shoot")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)

        let scan = try desqueeze("scan", link.path, "--json")
        XCTAssertEqual(scan.exitCode, 0, scan.stderr)
        XCTAssertEqual(try scan.json()["folder"] as? String, folder.path, "the folder, not the link")
        XCTAssertEqual(try scan.json()["pendingARWs"] as? [String], ["frame.ARW"])

        let run = try desqueeze("run", link.path, "--factor", "1.5", "--json")
        XCTAssertEqual(run.exitCode, 0, run.stderr)
        XCTAssertEqual(try run.json()["folder"] as? String, folder.path)
        XCTAssertEqual(counts(try run.json()), [1, 2, 0, 0, 0, 0])
        XCTAssertEqual(try scales(), ["already here.dng": "1.5 1", "frame.dng": "1.5 1"])
        XCTAssertEqual(try names(in: folder), ["already here.dng", "frame.ARW", "frame.dng"])
        XCTAssertEqual(try names(in: discard), ["already here.dng_original", "frame.dng_original"])

        let remove = try desqueeze("remove", link.path, "--json")
        XCTAssertEqual(remove.exitCode, 0, remove.stderr)
        XCTAssertEqual(try scales(), ["already here.dng": "1 1", "frame.dng": "1 1"])
    }

    // The window refuses a file, and a package such as an app. So does the tool.
    func testAFileAndAPackageAreNotFolders() throws {
        try makeShoot()
        let package = base.appendingPathComponent("Thing.app")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let fileLink = base.appendingPathComponent("Link to file")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: folder.appendingPathComponent("frame.ARW"))
        let before = try folderState()

        for path in [folder.appendingPathComponent("already here.dng").path, package.path, fileLink.path] {
            for arguments in [["scan", path], ["run", path, "--factor", "1.5"], ["remove", path]] {
                let result = try finish(process(arguments), started: { _ in })
                XCTAssertEqual(result.exitCode, 1, "\(arguments)")
                XCTAssertEqual(result.stdout, "")
                XCTAssertEqual(result.messages.first, "desqueeze: This folder could not be read: \(path)")
                XCTAssertEqual(result.messages.count, 2, "the reason, and one line below it")
            }
        }
        XCTAssertEqual(try folderState(), before)
        XCTAssertEqual(try names(in: discard), [])
    }

    // MARK: run --dry-run

    func testDryRunJSONChangesNoFile() throws {
        try makeShoot()
        let before = try folderState()

        let result = try desqueeze("run", folder.path, "--factor", "1.5", "--dry-run", "--json")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.messages, [], "nothing runs, so there is no progress")
        let json = try result.json()
        XCTAssertEqual(json["dryRun"] as? Bool, true)
        XCTAssertEqual(json["factor"] as? String, "1.5")
        XCTAssertEqual(json["steps"] as? [NSDictionary], [
            ["name": "frame.ARW", "action": "convert", "converter": firstConverter],
            ["name": "already here.dng", "action": "write"],
            ["name": "frame.dng", "action": "write"],
        ])
        XCTAssertEqual(counts(json), [1, 2, 0, 0, 0, 0])
        XCTAssertEqual([json["convertedByDnglab"], json["convertedByAdobe"]] as? [Int], oneConversion)
        XCTAssertEqual(json["notes"] as? [NSDictionary], [])
        XCTAssertEqual(try folderState(), before, "no byte, no date, and no name may change")
        XCTAssertEqual(try names(in: discard), [])
    }

    // MARK: run, a second run, remove

    func testRunThenASecondRunThenRemove() throws {
        try makeShoot()
        let arwBefore = try Data(contentsOf: folder.appendingPathComponent("frame.ARW"))

        let first = try desqueeze("run", folder.path, "--factor", "1.5", "--json")
        XCTAssertEqual(first.exitCode, 0)
        var json = try first.json()
        XCTAssertEqual(Set(json.allKeys.compactMap { $0 as? String }),
                       ["folder", "factor", "dryRun", "converted", "convertedByDnglab", "convertedByAdobe", "set",
                        "skipped", "blocked", "failed", "stopped", "unconvertedARWs", "trashOriginals",
                        "originalsInTrash", "notes"])
        // The option is off unless the flag is given (design 14.5).
        XCTAssertEqual(json["trashOriginals"] as? Bool, false)
        XCTAssertEqual(json["originalsInTrash"] as? Int, 0)
        XCTAssertEqual([json["convertedByDnglab"], json["convertedByAdobe"]] as? [Int], oneConversion)
        XCTAssertEqual(json["folder"] as? String, folder.path)
        XCTAssertEqual(json["factor"] as? String, "1.5")
        XCTAssertEqual(json["dryRun"] as? Bool, false)
        XCTAssertEqual(json["stopped"] as? Bool, false)
        XCTAssertEqual(counts(json), [1, 2, 0, 0, 0, 0])
        XCTAssertEqual(json["notes"] as? [NSDictionary], [])
        XCTAssertEqual(first.messages, ["1/3 frame.ARW", "2/3 already here.dng", "3/3 frame.dng"],
                       "progress is on standard error, one line for each step")
        XCTAssertEqual(try names(in: folder), ["already here.dng", "frame.ARW", "frame.dng"],
                       "no backup stays, and no _1.dng duplicate")
        XCTAssertEqual(try names(in: discard), ["already here.dng_original", "frame.dng_original"],
                       "each backup was moved, not removed")
        XCTAssertEqual(try scales(), ["already here.dng": "1.5 1", "frame.dng": "1.5 1"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("frame.ARW")), arwBefore)

        let second = try desqueeze("run", folder.path, "--factor", "1.5", "--json")
        XCTAssertEqual(second.exitCode, 0)
        XCTAssertEqual(counts(try second.json()), [0, 0, 2, 0, 0, 0], "every file is skipped")
        XCTAssertEqual(second.messages, ["1/2 already here.dng", "2/2 frame.dng"])

        let removed = try desqueeze("remove", folder.path, "--json")
        XCTAssertEqual(removed.exitCode, 0)
        json = try removed.json()
        XCTAssertEqual(json["factor"] as? String, "1")
        XCTAssertEqual(counts(json), [0, 2, 0, 0, 0, 0])
        XCTAssertEqual(try scales(), ["already here.dng": "1 1", "frame.dng": "1 1"])
        XCTAssertEqual(try names(in: folder), ["already here.dng", "frame.ARW", "frame.dng"])
    }

    func testRunTextMirrorsTheLineOfTheWindow() throws {
        try makeShoot()
        let result = try desqueeze("run", folder.path, "--factor", "2")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, """
            1 converted · 2 set · 0 skipped · 0 failed
            Photos already in Lightroom: Metadata › Read Metadata from File.

            """)
        XCTAssertEqual(result.messages, ["1/3 frame.ARW", "2/3 already here.dng", "3/3 frame.dng"])
    }

    func testNoConvertLeavesTheARWAndSaysSo() throws {
        try makeShoot()
        let result = try desqueeze("run", folder.path, "--factor", "1.5", "--no-convert", "--json")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(counts(try result.json()), [0, 1, 0, 0, 0, 1])
        XCTAssertEqual(try names(in: folder), ["already here.dng", "frame.ARW"])
    }

    // MARK: Usage errors

    func testRunWithNoFactorGivesTwoAndChangesNoFile() throws {
        try makeShoot()
        let before = try folderState()

        let result = try desqueeze("run", folder.path, "--json")

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, """
            desqueeze: run needs --factor <number>. There is no default.
            See desqueeze --help.

            """)
        XCTAssertEqual(try folderState(), before)
        XCTAssertEqual(try names(in: discard), [])
    }

    func testAnUnknownFlagGivesTwoAndChangesNoFile() throws {
        try makeShoot()
        let before = try folderState()

        let result = try desqueeze("run", folder.path, "--factor", "1.5", "--force")

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "desqueeze: Unknown option: --force\nSee desqueeze --help.\n")
        XCTAssertEqual(try folderState(), before)
    }

    // MARK: --verbose, --version, --help

    func testVerbosePrintsEachCommandItsExitCodeAndItsOutputOnStandardError() throws {
        try makeShoot()
        let quiet = try desqueeze("run", folder.path, "--factor", "1.5", "--dry-run", "--json")
        let result = try desqueeze("run", folder.path, "--factor", "1.5", "--json", "--verbose")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(counts(try result.json()), counts(try quiet.json()), "standard output is still one object")
        let exiftool = try XCTUnwrap(ToolLocator().exiftool()).path
        let converter = try XCTUnwrap(ToolLocator().dngConverter()).path
        // The scan gives each file's path with its links resolved, so a
        // line is found by how it starts and how it ends.
        func hasLine(_ start: String, _ end: String) -> Bool {
            result.messages.contains { $0.hasPrefix(start) && $0.hasSuffix(end) }
        }
        XCTAssertTrue(result.messages.contains(
            "$ \(exiftool) -m -T -filename -SubIFD:DefaultScale -OriginalRawFileName -ext dng '\(folder.path)'"),
            result.stderr)
        let dnglab = ToolLocator().dnglab()?.path
        let facts = fixtureFacts
        if dnglab != nil {
            // With dnglab installed, the facts of the ARW are read first,
            // whatever the frame is. The row is exiftool's own: the five
            // facts of the fixture, with `-` for one that it does not have.
            XCTAssertTrue(hasLine("$ \(exiftool) -m -n -T -filename -IFD0:Model -ExifIFD:ISO "
                + "-SR2SubIFD:WB_RGBLevelsDaylight -SubIFD:DistortionCorrection -SubIFD:SonyRawFileType '/",
                                  "/Shoot with spaces/frame.ARW'"), result.stderr)
            let row = [facts.model, facts.iso.map(String.init),
                       facts.daylightLevels.map { "\($0.red) \($0.green) \($0.blue)" },
                       facts.distortionCorrection.map(String.init), facts.rawFileType.map(String.init)]
                .map { $0 ?? "-" }.joined(separator: "\t")
            XCTAssertNotNil(facts.model, "exiftool reads the fixture")
            XCTAssertTrue(result.messages.contains { $0.hasSuffix("frame.ARW\t" + row) }, result.stderr)
        }
        if let dnglab, dnglabConverts {
            // A full match: dnglab's command, then the match write and its
            // read-back. The values are Adobe's for this frame, as the table
            // gives them for its facts.
            XCTAssertTrue(result.messages.contains {
                $0.hasPrefix("$ \(dnglab) convert --embed-raw false '/")
                    && $0.contains("/Shoot with spaces/frame.ARW' '/")
                    && $0.hasSuffix("/Shoot with spaces/.frame.desqueeze-work.dng'")
            }, result.stderr)
            // The values are taken from the product (`AdobeMatch`). This
            // pins the wiring: the tool writes the tags that the core's
            // match gives for this frame. That those values are Adobe's is
            // pinned by the core's table test and by the drift check.
            let match = AdobeMatch.match(facts).tags
            XCTAssertEqual(match.prefix(3).map(\.name),
                           ["SubIFD:WhiteLevel", "IFD0:BaselineExposure", "IFD0:CameraCalibration1"])
            let values = match.map(\.value)
            XCTAssertTrue(result.messages.contains {
                $0.hasPrefix("$ \(exiftool) -m -overwrite_original -SubIFD:WhiteLevel=\(values[0]) "
                    + "-IFD0:BaselineExposure=\(values[1]) '-IFD0:CameraCalibration1=\(values[2])' ")
                    && $0.contains(" -IFD0:OriginalRawFileName=frame.ARW '/")
                    && $0.hasSuffix("/Shoot with spaces/.frame.desqueeze-work.dng'")
            }, result.stderr)
            XCTAssertTrue(hasLine("$ \(exiftool) -m -n -T -SubIFD:WhiteLevel ",
                                  "/Shoot with spaces/.frame.desqueeze-work.dng'"), result.stderr)
            XCTAssertFalse(result.messages.contains { $0.contains(converter) },
                           "a full match does not start Adobe DNG Converter")
        } else {
            // No dnglab, or a frame with no full match: Adobe DNG Converter
            // gets the name of the work file, and dnglab does not start.
            XCTAssertTrue(result.messages.contains {
                $0.hasPrefix("$ '\(converter)' -c -d '/")
                    && $0.contains("/Shoot with spaces' -o .frame.desqueeze-work.dng '/")
                    && $0.hasSuffix("/Shoot with spaces/frame.ARW'")
            }, result.stderr)
            XCTAssertFalse(result.messages.contains { $0.contains(" convert --embed-raw ") },
                           "dnglab does not start for a frame that it cannot match")
        }
        XCTAssertTrue(hasLine("$ \(exiftool) -m '-SubIFD:DefaultScale=1.5 1' '/", "/Shoot with spaces/already here.dng'"),
                      result.stderr)
        XCTAssertTrue(hasLine("$ \(exiftool) -s3 -SubIFD:DefaultScale '/", "/Shoot with spaces/frame.dng'"),
                      result.stderr)
        XCTAssertTrue(result.messages.contains("  exit 0"))
        XCTAssertTrue(result.messages.contains("  stdout:     1 image files updated"))
        XCTAssertTrue(result.messages.contains("  stdout: 1.5 1"), "the check reads the tag back")
        XCTAssertTrue(result.messages.contains("3/3 frame.dng"), "progress is still there")
    }

    func testVersionAndHelp() throws {
        let version = try desqueeze("--version")
        XCTAssertEqual(version.stdout, "desqueeze 0.1.1\n")
        XCTAssertEqual(version.stderr, "")
        XCTAssertEqual(version.exitCode, 0)

        let help = try desqueeze("--help")
        XCTAssertEqual(help.exitCode, 0)
        XCTAssertEqual(help.stderr, "")
        XCTAssertTrue(help.stdout.contains(
            "  desqueeze run <folder> --factor <number> [--no-convert] [--trash-originals]\n"
                + "                [--dry-run] [--json]\n"))
        XCTAssertFalse(help.stdout.contains("!"))
    }
}
