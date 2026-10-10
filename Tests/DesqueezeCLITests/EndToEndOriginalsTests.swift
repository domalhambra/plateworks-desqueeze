import DesqueezeCore
import XCTest

/// `--trash-originals` with the built tool and the real programs (design
/// 14.5 and 14.6). Every start has `DESQUEEZE_TEST_BACKUP_FOLDER`, so an
/// original goes to a folder of the test, and never to the Trash.
///
/// The two tests that convert skip unless dnglab gets the fixture frame, so
/// this file starts Adobe DNG Converter never.
final class EndToEndOriginalsTests: BuiltToolTestCase {
    /// True when dnglab gets the fixture ARW on this Mac: it is installed,
    /// and the frame is a full match (design 13.4). The read changes no file.
    var dnglabConverts: Bool {
        let arw = Self.fixtures.appendingPathComponent("sample.ARW")
        let facts = ToolLocator().exiftool().flatMap { ARWFactsReader(exiftool: $0).read([arw])["sample.ARW"] }
        return ToolLocator().dnglab() != nil && AdobeMatch.match(facts ?? .none).isFull
    }

    func skipUnlessDnglabConverts() throws {
        try XCTSkipUnless(dnglabConverts, "This test needs dnglab and a frame that the match table covers, "
            + "so that it does not start Adobe DNG Converter.")
    }

    // MARK: The run

    func testTheFlagMovesTheOriginalToTheTestFolderAndTheJSONSaysSo() throws {
        try skipUnlessDnglabConverts()
        try makeShoot()
        try Data("sidecar".utf8).write(to: folder.appendingPathComponent("frame.xmp"))

        let result = try desqueeze("run", folder.path, "--factor", "1.5", "--trash-originals", "--json")

        XCTAssertEqual(result.exitCode, 0)
        let json = try result.json()
        XCTAssertEqual(json["trashOriginals"] as? Bool, true)
        XCTAssertEqual(json["originalsInTrash"] as? Int, 1)
        XCTAssertEqual(counts(json), [1, 2, 0, 0, 0, 0])
        XCTAssertEqual(json["notes"] as? [NSDictionary], [])
        XCTAssertEqual(result.messages, ["1/4 frame.ARW", "2/4 already here.dng", "3/4 frame.dng", "4/4 frame.ARW"],
                       "one more step for the original")
        // `contentsOfDirectory(atPath:)` lists hidden files too.
        XCTAssertEqual(try names(in: folder), ["already here.dng", "frame.dng", "frame.xmp"],
                       "the DNG, and no ARW. The sidecar file is not the app's, and stays")
        XCTAssertEqual(try names(in: discard), ["already here.dng_original", "frame.ARW", "frame.dng_original"])
        XCTAssertEqual(try Data(contentsOf: discard.appendingPathComponent("frame.ARW")),
                       try Data(contentsOf: Self.fixtures.appendingPathComponent("sample.ARW")),
                       "the file that moved has the bytes of the source ARW")
        XCTAssertEqual(try scales(), ["already here.dng": "1.5 1", "frame.dng": "1.5 1"])
    }

    func testTheTextOfARunWithTheFlagHasTheLineOfTheCore() throws {
        try skipUnlessDnglabConverts()
        try copyFixture("sample.ARW", as: "frame.ARW")

        let result = try desqueeze("run", folder.path, "--factor", "1.5", "--trash-originals")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, """
            1 converted · 1 set · 0 skipped · 0 failed
            Originals moved to the Trash: 1 of 1.
            Photos already in Lightroom: Metadata › Read Metadata from File.

            """)
        XCTAssertEqual(try names(in: folder), ["frame.dng"])
        XCTAssertEqual(try names(in: discard), ["frame.ARW", "frame.dng_original"])
    }

    // MARK: The dry run

    func testTheDryRunWithTheFlagShowsTheStepAndChangesNoFile() throws {
        try makeShoot()
        let before = try folderState()

        let text = try desqueeze("run", folder.path, "--factor", "1.5", "--trash-originals", "--dry-run")
        XCTAssertEqual(text.exitCode, 0)
        let lines = text.stdout.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "Dry run. No file was changed.")
        XCTAssertEqual(Array(lines.dropFirst(2)), [
            "  write    already here.dng",
            "  write    frame.dng",
            "  trash    frame.ARW",
            "A run would give: 1 converted · 2 set · 0 skipped · 0 failed",
        ])
        XCTAssertTrue(lines[1].hasPrefix("  convert  frame.ARW  with "), lines[1])

        let result = try desqueeze("run", folder.path, "--factor", "1.5", "--trash-originals", "--dry-run", "--json")
        XCTAssertEqual(result.exitCode, 0)
        let json = try result.json()
        XCTAssertEqual(json["dryRun"] as? Bool, true)
        XCTAssertEqual(json["trashOriginals"] as? Bool, true)
        XCTAssertEqual(json["originalsInTrash"] as? Int, 1, "the count that a real run would give")
        XCTAssertEqual((json["steps"] as? [NSDictionary])?.last, ["name": "frame.ARW", "action": "trashOriginal"])
        XCTAssertEqual((json["steps"] as? [NSDictionary])?.map { $0["action"] as? String },
                       ["convert", "write", "write", "trashOriginal"])

        XCTAssertEqual(try folderState(), before, "no byte, no date, and no name may change")
        XCTAssertEqual(try names(in: discard), [])
    }

    // Off unless the flag is given: the two keys are there, and say so. No
    // environment variable turns the option on.
    func testWithoutTheFlagTheKeysSayOffAlsoWithAVariableThatLooksLikeTheFlag() throws {
        try makeShoot()
        let before = try folderState()
        let variables: [String: String?] = [
            "DESQUEEZE_TRASH_ORIGINALS": "1", "TRASH_ORIGINALS": "YES", "DESQUEEZE_OPTIONS": "--trash-originals",
        ]

        let result = try finish(process(["run", folder.path, "--factor", "1.5", "--dry-run", "--json"],
                                        environment: variables), started: { _ in })

        XCTAssertEqual(result.exitCode, 0)
        let json = try result.json()
        XCTAssertEqual(json["trashOriginals"] as? Bool, false)
        XCTAssertEqual(json["originalsInTrash"] as? Int, 0)
        XCTAssertEqual((json["steps"] as? [NSDictionary])?.map { $0["action"] as? String },
                       ["convert", "write", "write"])
        XCTAssertEqual(try folderState(), before)
    }

    // MARK: The two usage errors

    func testTheFlagWithNoConvertAndTheFlagOnScanOrRemoveAreUsageErrors() throws {
        try makeShoot()
        let before = try folderState()
        let lines: [([String], String)] = [
            (["run", folder.path, "--factor", "1.5", "--trash-originals", "--no-convert"],
             "desqueeze: --trash-originals does not go with --no-convert. "
                + "A run that converts nothing has no original to move."),
            (["scan", folder.path, "--trash-originals"], "desqueeze: --trash-originals does not go with scan."),
            (["remove", folder.path, "--trash-originals", "--json"],
             "desqueeze: --trash-originals does not go with remove. Remove never moves an original."),
        ]
        for (arguments, message) in lines {
            let result = try finish(process(arguments), started: { _ in })
            XCTAssertEqual(result.exitCode, 2, "\(arguments)")
            XCTAssertEqual(result.stdout, "", "a usage error prints nothing on standard output")
            XCTAssertEqual(result.stderr, "\(message)\nSee desqueeze --help.\n")
        }
        XCTAssertEqual(try folderState(), before)
        XCTAssertEqual(try names(in: discard), [])
    }
}
