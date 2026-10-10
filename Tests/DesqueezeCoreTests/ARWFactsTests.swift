import XCTest
@testable import DesqueezeCore

final class ARWFactsTests: XCTestCase {
    let exiftool = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool")

    /// What exiftool 13.55 printed on 2026-10-09 for seven files, with the
    /// arguments of `ARWFactsReader`. The first two frames are from a lens
    /// that reports itself (Sony FE 24-105mm). The next three are from an
    /// adapted lens, as every anamorphic frame is. All five are compressed
    /// raw: `SonyRawFileType` 2, the last column. The last two files are no
    /// photos: a text file and an empty file, each named `.ARW`.
    static let realOutput = [
        "iso80.ARW\tILCE-7SM3\t80\t2496 1024 1617\t17\t2",
        "iso3200.ARW\tILCE-7SM3\t3200\t2496 1024 1617\t17\t2",
        "iso400.ARW\tILCE-7SM3\t400\t2597 1024 1556\t255\t2",
        "iso50.ARW\tILCE-7SM3\t50\t2597 1024 1556\t255\t2",
        "iso12800.ARW\tILCE-7SM3\t12800\t2597 1024 1556\t255\t2",
        "junk.ARW\t-\t-\t-\t-\t-",
        "empty.ARW\t-\t-\t-\t-\t-",
    ].joined(separator: "\n") + "\n"

    /// A frame of compressed raw. The lens fact is 255, or the 17 of a lens
    /// that reports itself.
    func facts(_ iso: Int, _ red: Int, _ blue: Int, noLensCorrection: Bool) -> ARWFacts {
        ARWFacts(model: "ILCE-7SM3", iso: iso,
                 daylightLevels: ARWFacts.DaylightLevels(red: red, green: 1024, blue: blue),
                 distortionCorrection: noLensCorrection ? 255 : 17, rawFileType: 2)
    }

    /// The names of the seven files of `realOutput`.
    static let realNames = ["iso80.ARW", "iso3200.ARW", "iso400.ARW", "iso50.ARW", "iso12800.ARW", "junk.ARW",
                            "empty.ARW"]

    /// The facts that the reader gives for the files `names` when exiftool
    /// prints `output`: `ARWFactsReader.read`, the one way in that the
    /// product uses. Every test of the parsing goes through it.
    func parse(_ output: String, files names: [String] = ["a.ARW"]) -> [String: ARWFacts] {
        reader(printing: output).0.read(names.map { URL(fileURLWithPath: "/tmp/Shoot 1/\($0)") })
    }

    func testParsesTheRealOutputOfBothKindsOfFrame() {
        let parsed = parse(Self.realOutput, files: Self.realNames)
        XCTAssertEqual(parsed.count, 7)
        // A lens that reports itself: other daylight levels, and correction data.
        XCTAssertEqual(parsed["iso80.ARW"], facts(80, 2496, 1617, noLensCorrection: false))
        XCTAssertEqual(parsed["iso3200.ARW"], facts(3200, 2496, 1617, noLensCorrection: false))
        // An adapted lens: the ARW says that it has no correction data.
        XCTAssertEqual(parsed["iso400.ARW"], facts(400, 2597, 1556, noLensCorrection: true))
        XCTAssertEqual(parsed["iso50.ARW"], facts(50, 2597, 1556, noLensCorrection: true))
        XCTAssertEqual(parsed["iso12800.ARW"], facts(12800, 2597, 1556, noLensCorrection: true))
        // Every measured frame is compressed raw, so rule 5 holds for each.
        XCTAssertEqual(parsed.values.filter(\.isCompressedRaw).count, 5)
        XCTAssertEqual(parsed["iso400.ARW"]?.rawFileType, 2)
        XCTAssertTrue(AdobeMatch.match(parsed["iso400.ARW"] ?? .none).isFull)
    }

    // exiftool prints a row of dashes for a file that it cannot read. Such a
    // file has no facts. That is not an error.
    func testAFileThatExiftoolCannotReadHasNoFacts() {
        let parsed = parse(Self.realOutput, files: Self.realNames)
        XCTAssertEqual(parsed["junk.ARW"], ARWFacts.none)
        XCTAssertEqual(parsed["empty.ARW"], ARWFacts.none)
        XCTAssertEqual(ARWFacts.none, ARWFacts(model: nil, iso: nil, daylightLevels: nil,
                                               distortionCorrection: nil, rawFileType: nil))
        XCTAssertFalse(ARWFacts.none.saysNoLensCorrection)
        XCTAssertFalse(ARWFacts.none.isCompressedRaw)
    }

    // Only 255 says "no correction data". Every other value, and no value,
    // is not that statement.
    func testOnlyTheValue255SaysThatTheARWHasNoLensCorrectionData() {
        for (value, expected) in [("255", true), ("17", false), ("0", false), ("1", false), ("-", false),
                                  ("", false), ("255 255", false), ("No correction params available", false)] {
            let parsed = parse("a.ARW\tILCE-7SM3\t800\t2597 1024 1556\t\(value)\t2\n")
            XCTAssertEqual(parsed["a.ARW"]?.saysNoLensCorrection, expected, "\"\(value)\"")
        }
    }

    // The fact is the number that the file holds. No number is "the ARW does
    // not say", and that is not the same as another number.
    func testTheLensFactIsTheNumberOrNilWhenTheARWDoesNotSay() {
        func lensFact(_ value: String) -> Int? {
            parse("a.ARW\tILCE-7SM3\t800\t2597 1024 1556\t\(value)\t2\n")["a.ARW"]?.distortionCorrection
        }
        XCTAssertEqual(lensFact("255"), 255)
        XCTAssertEqual(lensFact("17"), 17)
        XCTAssertEqual(lensFact("0"), 0)
        for value in ["-", "", "255 255", "No correction params available", "-1", "1.5"] {
            XCTAssertNil(lensFact(value), "\"\(value)\"")
        }
    }

    // Rule 5 (design 13.4). Only 2, "Sony Compressed RAW", is the kind that
    // was measured. Every other value, and no value, is not that kind.
    func testOnlyTheValue2SaysThatTheARWIsCompressedRaw() {
        for (value, kind, expected) in [
            ("2", 2 as Int?, true), ("0", 0, false), ("1", 1, false), ("3", 3, false), ("4", 4, false),
            ("22", 22, false), ("-", nil, false), ("", nil, false), ("2 2", nil, false), ("2.0", nil, false),
            ("-2", nil, false), ("Sony Compressed RAW", nil, false),
        ] {
            let parsed = parse("a.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\t\(value)\n")["a.ARW"]
            XCTAssertEqual(parsed?.rawFileType, kind, "\"\(value)\"")
            XCTAssertEqual(parsed?.isCompressedRaw, expected, "\"\(value)\"")
            XCTAssertEqual(parsed?.iso, 800, "the other facts stay")
        }
        XCTAssertEqual(ARWFacts.compressedRaw, 2)
    }

    func testAValueThatIsNotWhatTheTagHoldsIsNoFact() {
        func facts(iso: String = "800", levels: String = "2597 1024 1556") -> ARWFacts? {
            parse("a.ARW\tILCE-7SM3\t\(iso)\t\(levels)\t255\t2\n")["a.ARW"]
        }
        XCTAssertEqual(facts()?.iso, 800)
        for iso in ["-", "", "800 800", "8e2", "800.5", "auto", "-800", "0"] {
            XCTAssertNil(facts(iso: iso)?.iso, "\"\(iso)\"")
            XCTAssertEqual(facts(iso: iso)?.model, "ILCE-7SM3", "the other facts stay")
        }
        for levels in ["-", "", "2597 1024", "2597 1024 1556 1024", "2597 1024 x", "2597.5 1024 1556",
                       "-2597 1024 1556"] {
            XCTAssertNil(facts(levels: levels)?.daylightLevels, "\"\(levels)\"")
        }
    }

    func testARowWithTheWrongNumberOfCellsIsDropped() {
        let parsed = parse("""
        a.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255
        b.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\t2\textra
        Warning: something
        c.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\t2

        """, files: ["a.ARW", "b.ARW", "c.ARW", "Warning: something"])
        XCTAssertEqual(Array(parsed.keys), ["c.ARW"])
    }

    // MARK: A control character in a file name

    /// What exiftool 13.55 printed on 2026-10-09 for three copies of one
    /// frame: `a<tab>b.ARW`, `a.b.ARW` and `plain.ARW`. The tab is printed
    /// as a period, so the first two rows have one name.
    static let realOutputWithATab = "a.b.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\t2\n"
        + "a.b.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\t2\n"
        + "plain.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\t2\n"

    func testExiftoolPrintsEachControlCharacterAsAPeriod() {
        XCTAssertEqual(ExiftoolText.printed("a\tb.ARW"), "a.b.ARW")
        XCTAssertEqual(ExiftoolText.printed("n\nl\u{7F}\u{1} q.ARW"), "n.l.. q.ARW", "as the real exiftool printed it")
        XCTAssertEqual(ExiftoolText.printed("r\r\nn.ARW"), "r..n.ARW", "two characters, two periods")
        XCTAssertEqual(ExiftoolText.printed("\u{1F}\u{20}\u{7E}\u{80}"), ". ~\u{80}", "only U+0001 to U+001F and U+007F")
        XCTAssertEqual(ExiftoolText.printed("uni é ü 写真.ARW"), "uni é ü 写真.ARW")
        XCTAssertEqual(ExiftoolText.printed("DSC05680.ARW"), "DSC05680.ARW")
    }

    // Two rows share a name: no one can say which row is whose. Neither
    // file gets facts, and "no facts" is "no full match".
    func testANameThatTwoRowsShareGivesNoFacts() {
        // One file of the list has the name that the two rows share.
        let files = ["a.b.ARW", "plain.ARW"]
        let parsed = parse(Self.realOutputWithATab, files: files)
        XCTAssertEqual(parsed.keys.sorted(), ["plain.ARW"])
        XCTAssertEqual(parsed["plain.ARW"], facts(800, 2597, 1556, noLensCorrection: true))
        // Also when the two rows are equal, and when there are three.
        XCTAssertEqual(parse(Self.realOutputWithATab + Self.realOutputWithATab, files: files), [:])
    }

    func reader(printing output: String) -> (ARWFactsReader, FakeRunner) {
        let runner = FakeRunner()
        runner.handler = { _ in ProcessResult(exitCode: 0, stdout: output, stderr: "") }
        return (ARWFactsReader(exiftool: exiftool, runner: runner), runner)
    }

    func testTwoFilesWhoseNamesPrintAsOneGetNoFactsAndTheOthersKeepTheirs() {
        let (reader, _) = reader(printing: Self.realOutputWithATab)
        let read = reader.read(["a\tb.ARW", "a.b.ARW", "plain.ARW"].map { URL(fileURLWithPath: "/tmp/Shoot 1/\($0)") })
        XCTAssertEqual(read.keys.sorted(), ["plain.ARW"])
        XCTAssertNil(read["a\tb.ARW"])
        XCTAssertNil(read["a.b.ARW"])
    }

    // One file with a tab in its name, and no other file that prints as it:
    // the row is its own, and the facts come back under the real name.
    func testOneFileWithATabInItsNameGetsItsFactsUnderItsRealName() {
        let (reader, runner) = reader(printing: "a.b.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\t2\n")
        let read = reader.read([URL(fileURLWithPath: "/tmp/Shoot 1/a\tb.ARW")])
        XCTAssertEqual(read, ["a\tb.ARW": facts(800, 2597, 1556, noLensCorrection: true)])
        XCTAssertEqual(runner.calls.first?.arguments.last, "/tmp/Shoot 1/a\tb.ARW", "the path goes to exiftool as it is")
    }

    // The two rows can come from two calls, when the files are in two
    // batches. The name is still shared.
    func testANameThatIsSharedAcrossTwoBatchesGivesNoFacts() {
        var arws = (1...200).map { URL(fileURLWithPath: "/tmp/Shoot 1/frame\($0).ARW") }
        arws[0] = URL(fileURLWithPath: "/tmp/Shoot 1/a\tb.ARW")
        arws.append(URL(fileURLWithPath: "/tmp/Shoot 1/a.b.ARW"))
        let runner = FakeRunner()
        runner.handler = { call in
            let rows = call.arguments.filter { $0.hasPrefix("/") }.map {
                "\(ExiftoolText.printed(URL(fileURLWithPath: $0).lastPathComponent))\tILCE-7SM3\t800\t2597 1024 1556\t255\t2\n"
            }
            return ProcessResult(exitCode: 0, stdout: rows.joined(), stderr: "")
        }
        let read = ARWFactsReader(exiftool: exiftool, runner: runner).read(arws)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(read.count, 199)
        XCTAssertNil(read["a\tb.ARW"])
        XCTAssertNil(read["a.b.ARW"])
        XCTAssertNotNil(read["frame200.ARW"])
    }

    // Two rows with one name, and one file of the list with that name: the
    // read does not pick one of them.
    func testTwoRowsWithOneNameGiveNoFactsAlsoToTheOneFileOfTheList() {
        let (reader, _) = reader(printing: "a.b.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\t2\n"
            + "a.b.ARW\tILCE-7SM3\t80\t2496 1024 1617\t17\t2\n")
        XCTAssertEqual(reader.read([URL(fileURLWithPath: "/tmp/Shoot 1/a.b.ARW")]), [:])
    }

    // A row that no file of the list asked for is no one's facts.
    func testOnlyTheFilesOfTheListGetFacts() {
        let (reader, _) = reader(printing: Self.realOutput)
        XCTAssertEqual(reader.read([URL(fileURLWithPath: "/tmp/iso80.ARW")]).keys.sorted(), ["iso80.ARW"])
    }

    // MARK: The read

    func testOneCallForAShortListWithTheExactArguments() {
        let runner = FakeRunner()
        runner.handler = { _ in ProcessResult(exitCode: 0, stdout: Self.realOutput, stderr: "") }
        let reader = ARWFactsReader(exiftool: exiftool, runner: runner)
        let read = reader.read([URL(fileURLWithPath: "/tmp/Shoot 1/iso80.ARW"),
                                URL(fileURLWithPath: "/tmp/Shoot 1/iso400.ARW")])
        XCTAssertEqual(runner.calls, [FakeRunner.Call(executable: exiftool.path, arguments: [
            "-m", "-n", "-T", "-filename", "-IFD0:Model", "-ExifIFD:ISO", "-SR2SubIFD:WB_RGBLevelsDaylight",
            "-SubIFD:DistortionCorrection", "-SubIFD:SonyRawFileType",
            "/tmp/Shoot 1/iso80.ARW", "/tmp/Shoot 1/iso400.ARW",
        ])])
        XCTAssertEqual(read["iso80.ARW"]?.iso, 80)
        XCTAssertEqual(read["iso400.ARW"]?.saysNoLensCorrection, true)
    }

    // The list is the command line, and the system refuses a command line
    // that is too long. So the read is made in batches.
    func testFourHundredAndFiftyFilesAreReadInThreeCallsAndEveryFileGetsItsFacts() {
        let arws = (1...450).map { URL(fileURLWithPath: "/tmp/Shoot 1/frame\($0).ARW") }
        let runner = FakeRunner()
        // One row for each file of the call, with the file's number as its ISO.
        runner.handler = { call in
            let rows = call.arguments.filter { $0.hasPrefix("/") }.map { path -> String in
                let name = URL(fileURLWithPath: path).lastPathComponent
                return "\(name)\tILCE-7SM3\t\(name.dropFirst(5).dropLast(4))\t2597 1024 1556\t255\t2\n"
            }
            return ProcessResult(exitCode: 0, stdout: rows.joined(), stderr: "")
        }
        let read = ARWFactsReader(exiftool: exiftool, runner: runner).read(arws)

        XCTAssertEqual(ARWFactsReader.batchSize, 200)
        XCTAssertEqual(runner.calls.map { $0.arguments.filter { $0.hasPrefix("/") }.count }, [200, 200, 50])
        XCTAssertEqual(runner.calls.flatMap { $0.arguments.filter { $0.hasPrefix("/") } }, arws.map(\.path),
                       "every file is in one call, in the order of the list")
        for call in runner.calls {
            XCTAssertEqual(Array(call.arguments.prefix(9)), [
                "-m", "-n", "-T", "-filename", "-IFD0:Model", "-ExifIFD:ISO", "-SR2SubIFD:WB_RGBLevelsDaylight",
                "-SubIFD:DistortionCorrection", "-SubIFD:SonyRawFileType",
            ])
        }
        XCTAssertEqual(read.count, 450)
        for number in [1, 200, 201, 400, 401, 450] {
            XCTAssertEqual(read["frame\(number).ARW"], facts(number, 2597, 1556, noLensCorrection: true), "\(number)")
        }
    }

    func testExactlyOneBatchOfFilesIsOneCall() {
        let runner = FakeRunner()
        _ = ARWFactsReader(exiftool: exiftool, runner: runner)
            .read((1...200).map { URL(fileURLWithPath: "/tmp/frame\($0).ARW") })
        XCTAssertEqual(runner.calls.count, 1)
    }

    /// Fails the call with this number, counted from 1, and answers the
    /// others with one row for the first file of the call.
    final class OneCallFails: ProcessRunner, @unchecked Sendable {
        let failing: Int
        var calls = 0

        init(failing: Int) { self.failing = failing }

        func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
            calls += 1
            if calls == failing { throw NamedError(text: "The program could not start.") }
            let first = URL(fileURLWithPath: arguments.first { $0.hasPrefix("/") } ?? "").lastPathComponent
            return ProcessResult(exitCode: 0, stdout: "\(first)\tILCE-7SM3\t800\t2597 1024 1556\t255\t2\n",
                                 stderr: "")
        }
    }

    // The files of that batch have no facts. The other batches keep theirs.
    func testABatchWhoseReadFailsDoesNotTakeTheFactsOfTheOtherBatches() {
        let runner = OneCallFails(failing: 2)
        let read = ARWFactsReader(exiftool: exiftool, runner: runner)
            .read((1...450).map { URL(fileURLWithPath: "/tmp/frame\($0).ARW") })
        XCTAssertEqual(runner.calls, 3)
        XCTAssertEqual(read.keys.sorted(), ["frame1.ARW", "frame401.ARW"])
    }

    func testAnEmptyListStartsNoProgram() {
        let runner = FakeRunner()
        XCTAssertEqual(ARWFactsReader(exiftool: exiftool, runner: runner).read([]), [:])
        XCTAssertEqual(runner.calls, [])
    }

    // exiftool exits 1 when one file is unreadable. The other rows are valid.
    func testANonZeroExitStillGivesTheRows() {
        let runner = FakeRunner()
        runner.handler = { _ in ProcessResult(exitCode: 1, stdout: Self.realOutput, stderr: "") }
        let names = ["iso80", "iso3200", "iso400", "iso50", "iso12800", "junk", "empty"]
        let read = ARWFactsReader(exiftool: exiftool, runner: runner)
            .read(names.map { URL(fileURLWithPath: "/tmp/\($0).ARW") })
        XCTAssertEqual(read.count, 7)
    }

    // No facts is "no full match". It is not an error that stops the run.
    func testAReadThatFailsGivesNoFactsAndDoesNotThrow() {
        let runner = FakeRunner()
        runner.failure = NamedError(text: "The program could not start.")
        let read = ARWFactsReader(exiftool: exiftool, runner: runner).read([URL(fileURLWithPath: "/tmp/a.ARW")])
        XCTAssertEqual(read, [:])
        XCTAssertEqual(runner.calls.count, 1)
    }
}
