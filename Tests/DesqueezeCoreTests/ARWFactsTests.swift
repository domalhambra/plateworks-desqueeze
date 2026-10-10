import XCTest
@testable import DesqueezeCore

final class ARWFactsTests: XCTestCase {
    let exiftool = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool")

    /// What exiftool 13.55 printed on 2026-10-09 for seven files, with the
    /// arguments of `ARWFactsReader`. The first two frames are from a lens
    /// that reports itself (Sony FE 24-105mm). The next three are from an
    /// adapted lens, as every anamorphic frame is. The last two are no
    /// photos: a text file and an empty file, each named `.ARW`.
    static let realOutput = [
        "iso80.ARW\tILCE-7SM3\t80\t2496 1024 1617\t17",
        "iso3200.ARW\tILCE-7SM3\t3200\t2496 1024 1617\t17",
        "iso400.ARW\tILCE-7SM3\t400\t2597 1024 1556\t255",
        "iso50.ARW\tILCE-7SM3\t50\t2597 1024 1556\t255",
        "iso12800.ARW\tILCE-7SM3\t12800\t2597 1024 1556\t255",
        "junk.ARW\t-\t-\t-\t-",
        "empty.ARW\t-\t-\t-\t-",
    ].joined(separator: "\n") + "\n"

    func facts(_ iso: Int, _ red: Int, _ blue: Int, noLensCorrection: Bool) -> ARWFacts {
        ARWFacts(model: "ILCE-7SM3", iso: iso,
                 daylightLevels: ARWFacts.DaylightLevels(red: red, green: 1024, blue: blue),
                 saysNoLensCorrection: noLensCorrection)
    }

    func testParsesTheRealOutputOfBothKindsOfFrame() {
        let parsed = ARWFactsReader.parse(Self.realOutput)
        XCTAssertEqual(parsed.count, 7)
        // A lens that reports itself: other daylight levels, and correction data.
        XCTAssertEqual(parsed["iso80.ARW"], facts(80, 2496, 1617, noLensCorrection: false))
        XCTAssertEqual(parsed["iso3200.ARW"], facts(3200, 2496, 1617, noLensCorrection: false))
        // An adapted lens: the ARW says that it has no correction data.
        XCTAssertEqual(parsed["iso400.ARW"], facts(400, 2597, 1556, noLensCorrection: true))
        XCTAssertEqual(parsed["iso50.ARW"], facts(50, 2597, 1556, noLensCorrection: true))
        XCTAssertEqual(parsed["iso12800.ARW"], facts(12800, 2597, 1556, noLensCorrection: true))
    }

    // exiftool prints a row of dashes for a file that it cannot read. Such a
    // file has no facts. That is not an error.
    func testAFileThatExiftoolCannotReadHasNoFacts() {
        let parsed = ARWFactsReader.parse(Self.realOutput)
        XCTAssertEqual(parsed["junk.ARW"], ARWFacts.none)
        XCTAssertEqual(parsed["empty.ARW"], ARWFacts.none)
        XCTAssertEqual(ARWFacts.none,
                       ARWFacts(model: nil, iso: nil, daylightLevels: nil, saysNoLensCorrection: false))
    }

    // Only 255 says "no correction data". Every other value, and no value,
    // is not that statement.
    func testOnlyTheValue255SaysThatTheARWHasNoLensCorrectionData() {
        for (value, expected) in [("255", true), ("17", false), ("0", false), ("1", false), ("-", false),
                                  ("", false), ("255 255", false), ("No correction params available", false)] {
            let parsed = ARWFactsReader.parse("a.ARW\tILCE-7SM3\t800\t2597 1024 1556\t\(value)\n")
            XCTAssertEqual(parsed["a.ARW"]?.saysNoLensCorrection, expected, "\"\(value)\"")
        }
    }

    func testAValueThatIsNotWhatTheTagHoldsIsNoFact() {
        func parse(iso: String = "800", levels: String = "2597 1024 1556") -> ARWFacts? {
            ARWFactsReader.parse("a.ARW\tILCE-7SM3\t\(iso)\t\(levels)\t255\n")["a.ARW"]
        }
        XCTAssertEqual(parse()?.iso, 800)
        for iso in ["-", "", "800 800", "8e2", "800.5", "auto", "-800", "0"] {
            XCTAssertNil(parse(iso: iso)?.iso, "\"\(iso)\"")
            XCTAssertEqual(parse(iso: iso)?.model, "ILCE-7SM3", "the other facts stay")
        }
        for levels in ["-", "", "2597 1024", "2597 1024 1556 1024", "2597 1024 x", "2597.5 1024 1556",
                       "-2597 1024 1556"] {
            XCTAssertNil(parse(levels: levels)?.daylightLevels, "\"\(levels)\"")
        }
    }

    func testARowWithTheWrongNumberOfCellsIsDropped() {
        let parsed = ARWFactsReader.parse("""
        a.ARW\tILCE-7SM3\t800\t2597 1024 1556
        b.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255\textra
        Warning: something
        c.ARW\tILCE-7SM3\t800\t2597 1024 1556\t255

        """)
        XCTAssertEqual(Array(parsed.keys), ["c.ARW"])
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
            "-SubIFD:DistortionCorrection", "/tmp/Shoot 1/iso80.ARW", "/tmp/Shoot 1/iso400.ARW",
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
                return "\(name)\tILCE-7SM3\t\(name.dropFirst(5).dropLast(4))\t2597 1024 1556\t255\n"
            }
            return ProcessResult(exitCode: 0, stdout: rows.joined(), stderr: "")
        }
        let read = ARWFactsReader(exiftool: exiftool, runner: runner).read(arws)

        XCTAssertEqual(ARWFactsReader.batchSize, 200)
        XCTAssertEqual(runner.calls.map { $0.arguments.filter { $0.hasPrefix("/") }.count }, [200, 200, 50])
        XCTAssertEqual(runner.calls.flatMap { $0.arguments.filter { $0.hasPrefix("/") } }, arws.map(\.path),
                       "every file is in one call, in the order of the list")
        for call in runner.calls {
            XCTAssertEqual(Array(call.arguments.prefix(8)), [
                "-m", "-n", "-T", "-filename", "-IFD0:Model", "-ExifIFD:ISO", "-SR2SubIFD:WB_RGBLevelsDaylight",
                "-SubIFD:DistortionCorrection",
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
            return ProcessResult(exitCode: 0, stdout: "\(first)\tILCE-7SM3\t800\t2597 1024 1556\t255\n", stderr: "")
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
        let read = ARWFactsReader(exiftool: exiftool, runner: runner).read([URL(fileURLWithPath: "/tmp/iso80.ARW")])
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
