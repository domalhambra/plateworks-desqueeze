import XCTest
@testable import DesqueezeCore

final class DnglabConverterTests: XCTestCase {
    let dnglab = URL(fileURLWithPath: "/opt/homebrew/bin/dnglab")
    let exiftool = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool")
    let arw = URL(fileURLWithPath: "/tmp/Shoot 1/DSC05680.ARW")
    let dngPath = "/tmp/Shoot 1/DSC05680.dng"
    var dng: URL { URL(fileURLWithPath: dngPath) }
    /// The hidden work file that dnglab writes (design 13.3).
    let workPath = "/tmp/Shoot 1/.DSC05680.desqueeze-work.dng"
    var work: URL { URL(fileURLWithPath: workPath) }
    /// What exiftool leaves beside the work file when it ends hard in the
    /// match write.
    let workTmpPath = "/tmp/Shoot 1/.DSC05680.desqueeze-work.dng_exiftool_tmp"

    /// An adapted lens at ISO 800: a full match.
    let adapted = ARWFacts(model: "ILCE-7SM3", iso: 800,
                           daylightLevels: ARWFacts.DaylightLevels(red: 2597, green: 1024, blue: 1556),
                           saysNoLensCorrection: true)
    /// A lens that reports itself, at ISO 80: rule 4 fails, and no other.
    let lens = ARWFacts(model: "ILCE-7SM3", iso: 80,
                        daylightLevels: ARWFacts.DaylightLevels(red: 2496, green: 1024, blue: 1617),
                        saysNoLensCorrection: false)

    static let noise800 = "9.17112993057145e-05 1.80963827089821e-07 0.000132825207904173 1.86198019692823e-07 "
        + "6.88838025482567e-05 1.77853114759923e-07"

    /// What the three programs, the discard and the rename do, and what
    /// they were asked.
    final class Tools: @unchecked Sendable {
        var dnglabExit: Int32 = 0
        /// The bytes of the file that dnglab leaves at the name that it was
        /// given. Nil: it leaves no file.
        var dnglabWrites: Int? = 1_000
        /// Each leftover that the converter asked to discard.
        var discarded: [String] = []
        /// Set when the discard must fail, as when the Trash refuses.
        var discardError: Error?
        /// Each rename that the converter asked for: from, then to.
        var renames: [[String]] = []
        var renameOutcome = ExclusiveRename.Outcome.moved
        /// The work file is gone when the rename is asked for: another
        /// program, or the person, took it away.
        var workFileIsGoneAtTheRename = false
        /// What dnglab prints on standard error.
        var dnglabError = ""
        var writeResult = ProcessResult(exitCode: 0, stdout: "    1 image files updated\n", stderr: "")
        /// Nil: the read-back gives what was written.
        var readBack: String?
        /// Thrown by the call with this number, counted from 1, after it ran.
        var failure: (call: Int, error: Error)?
        var written: [String] = []
    }

    var runner: FakeRunner!
    var disk: FakeDisk!
    var tools: Tools!

    override func setUp() {
        runner = FakeRunner()
        disk = FakeDisk()
        tools = Tools()
        let (runner, disk, tools, dnglab) = (runner!, disk!, tools!, dnglab)
        runner.handler = { call in
            if call.executable == dnglab.path {
                // dnglab writes where its last argument says.
                if let bytes = tools.dnglabWrites, let output = call.arguments.last {
                    disk.paths.insert(output)
                    disk.sizes[output] = bytes
                }
                return ProcessResult(exitCode: tools.dnglabExit, stdout: "", stderr: tools.dnglabError)
            }
            if call.arguments.contains("-overwrite_original") {
                tools.written = call.arguments.filter { $0.contains("=") }
                    .map { String($0[$0.index(after: $0.firstIndex(of: "=")!)...]) }
                return tools.writeResult
            }
            return ProcessResult(exitCode: 0, stdout: (tools.readBack ?? tools.written.joined(separator: "\t")) + "\n",
                                 stderr: "")
        }
    }

    func converter() -> DnglabConverter {
        let (runner, disk, tools) = (runner!, disk!, tools!)
        return DnglabConverter(
            executable: dnglab, exiftool: exiftool, runner: ThrowingRunner(runner, tools),
            discardLeftover: {
                tools.discarded.append($0.path)
                if let error = tools.discardError { throw error }
                disk.paths.remove($0.path)
            },
            fileExists: { disk.exists($0) }, fileSize: { disk.size($0) }, fileIsRegular: { disk.isRegularFile($0) },
            rename: { from, to in
                tools.renames.append([from.path, to.path])
                if tools.workFileIsGoneAtTheRename { disk.paths.remove(from.path) }
                if tools.renameOutcome == .moved { disk.move(from.path, to: to.path) }
                return tools.renameOutcome
            })
    }

    /// Passes each call on, and throws after the call that `Tools` names.
    struct ThrowingRunner: ProcessRunner {
        let runner: FakeRunner
        let tools: Tools

        init(_ runner: FakeRunner, _ tools: Tools) {
            self.runner = runner
            self.tools = tools
        }

        func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
            let result = try runner.run(executable, arguments)
            if let failure = tools.failure, failure.call == runner.calls.count { throw failure.error }
            return result
        }
    }

    func call(_ executable: URL, _ arguments: [String]) -> FakeRunner.Call {
        FakeRunner.Call(executable: executable.path, arguments: arguments)
    }

    var convertCall: FakeRunner.Call {
        call(dnglab, ["convert", "--embed-raw", "false", "/tmp/Shoot 1/DSC05680.ARW",
                      "/tmp/Shoot 1/.DSC05680.desqueeze-work.dng"])
    }

    /// The conversion fails with exactly `expected`. Whatever fails, dnglab's
    /// converter never reports `<base>.dng` as its partial output: it never
    /// writes to that name, so a file there is someone else's.
    func assertFails(_ expected: ConvertError, _ facts: ARWFacts? = nil, _ message: String = "",
                     file: StaticString = #filePath, line: UInt = #line) {
        let thrown = error(facts, file: file, line: line) as? ConvertError
        XCTAssertEqual(thrown, expected, message, file: file, line: line)
        XCTAssertNotEqual(thrown?.partial, dng, "the DNG's own name was reported as partial", file: file, line: line)
        XCTAssertFalse(disk.paths.contains(dngPath), "a failed conversion left a file at the DNG's name",
                       file: file, line: line)
    }

    func error(_ facts: ARWFacts? = nil, file: StaticString = #filePath, line: UInt = #line) -> Error? {
        var thrown: Error?
        XCTAssertThrowsError(try converter().convert(arw, facts: facts ?? adapted), file: file, line: line) {
            thrown = $0
        }
        return thrown
    }

    // MARK: A file name that is too long (design 13.9)

    // The rule is `ConverterRules`', so dnglab's converter has it too: no
    // dnglab starts, and no exiftool. A base of 223 letters is the first
    // that is too long: exiftool's temporary file beside the work file
    // would have 256 units. Until 2026-10-10 dnglab started for it, and
    // exiftool then failed in the match with the system's words.
    func testAnARWWhoseNameIsTooLongStartsNoProgram() {
        let long = URL(fileURLWithPath: "/tmp/Shoot 1/\(String(repeating: "n", count: 223)).ARW")
        XCTAssertThrowsError(try converter().convert(long, facts: adapted)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failedForAll("The file name is too long. Shorten it, then run again."))
        }
        XCTAssertEqual(runner.calls, [], "no dnglab and no exiftool")
        XCTAssertEqual(disk.checked, [])
        XCTAssertEqual(tools.discarded, [])
        XCTAssertEqual(tools.renames, [])
    }

    // MARK: A conversion that passes

    func testAFullMatchIsThreeCallsWithTheExactArguments() throws {
        let conversion = try converter().convert(arw, facts: adapted)

        XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: nil))
        guard runner.calls.count == 3 else { return XCTFail("\(runner.calls.count) calls, not 3") }
        // dnglab writes the work file, and both exiftool calls name it.
        XCTAssertEqual(runner.calls[0], convertCall)
        // One exiftool call writes every tag. No backup: the file is this
        // run's own, and has no earlier state to keep.
        XCTAssertEqual(runner.calls[1], call(exiftool, [
            "-m", "-overwrite_original",
            "-SubIFD:WhiteLevel=16383",
            "-IFD0:BaselineExposure=0.15",
            "-IFD0:CameraCalibration1=0.9888 0 0 0 1 0 0 0 0.9955",
            "-IFD0:CameraCalibration2=0.9888 0 0 0 1 0 0 0 0.9955",
            "-IFD0:NoiseProfile=\(Self.noise800)",
            "-IFD0:BaselineNoise=0.6",
            "-IFD0:BaselineSharpness=1.25",
            "-SubIFD:AntiAliasStrength=1",
            "-SubIFD:BayerGreenSplit=250",
            "-IFD0:OriginalRawFileName=DSC05680.ARW",
            "/tmp/Shoot 1/.DSC05680.desqueeze-work.dng",
        ]))
        XCTAssertEqual(runner.calls[2], call(exiftool, [
            "-m", "-n", "-T",
            "-SubIFD:WhiteLevel", "-IFD0:BaselineExposure", "-IFD0:CameraCalibration1", "-IFD0:CameraCalibration2",
            "-IFD0:NoiseProfile", "-IFD0:BaselineNoise", "-IFD0:BaselineSharpness", "-SubIFD:AntiAliasStrength",
            "-SubIFD:BayerGreenSplit", "-IFD0:OriginalRawFileName",
            "/tmp/Shoot 1/.DSC05680.desqueeze-work.dng",
        ]))
        // Only then the DNG gets its name, with the rename that never replaces.
        XCTAssertEqual(tools.renames, [[workPath, dngPath]])
        XCTAssertEqual(disk.paths, [dngPath], "the DNG is at its name, and no work file is left")
        XCTAssertEqual(tools.discarded, [], "there was no leftover to discard")
    }

    // MARK: The name of the work file

    // The sentence is made once, and a note adds it after a name that starts
    // with a period, and only then.
    func testTheHintAboutAHiddenFileIsOneSentenceThatOnlyAHiddenNameGets() {
        XCTAssertEqual(ConverterOutput.hiddenFileHint,
                       "It is a hidden file: in Finder, press Command-Shift-Period to see it.")
        XCTAssertEqual(ConverterOutput.hint(forFileNamed: ".X.desqueeze-work.dng"),
                       " It is a hidden file: in Finder, press Command-Shift-Period to see it.")
        XCTAssertEqual(ConverterOutput.hint(forFileNamed: "X.dng"), "")
        XCTAssertEqual(ConverterOutput.hint(forFileNamed: "X.dng_exiftool_tmp"), "")
    }

    // One function makes the name: a period, the base name, and the suffix,
    // in the folder of the ARW. The period hides it from the scan, Finder
    // and Lightroom.
    func testTheWorkFileIsAHiddenFileBesideTheARWWithTheBaseNameInIt() {
        func name(_ path: String) -> String { ConverterOutput.workURL(for: URL(fileURLWithPath: path)).path }
        XCTAssertEqual(name("/tmp/Shoot 1/DSC05680.ARW"), "/tmp/Shoot 1/.DSC05680.desqueeze-work.dng")
        XCTAssertEqual(name("/tmp/Shoot 1/frame 1.ARW"), "/tmp/Shoot 1/.frame 1.desqueeze-work.dng")
        XCTAssertEqual(name("/tmp/Shoot 1/lower.arw"), "/tmp/Shoot 1/.lower.desqueeze-work.dng")
        XCTAssertEqual(name("/tmp/Shoot 1/two.dots.ARW"), "/tmp/Shoot 1/.two.dots.desqueeze-work.dng")
        XCTAssertNotEqual(name("/tmp/Shoot 1/a.ARW"), name("/tmp/Shoot 2/a.ARW"))
    }

    func testTheScanDoesNotSeeAWorkFile() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let arw = folder.appendingPathComponent("frame 1.ARW")
        try Data("raw".utf8).write(to: arw)
        try Data("half a DNG".utf8).write(to: ConverterOutput.workURL(for: arw))
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs, [])
        XCTAssertEqual(contents.arws.map(\.lastPathComponent), ["frame 1.ARW"])
    }

    // dnglab's `-f` writes over a file. The pre-start check is the rule, and
    // the flag must never be there to defeat it.
    func testNoCallEverPassesTheOverrideFlag() throws {
        _ = try converter().convert(arw, facts: adapted)
        _ = try? converter().convert(arw, facts: adapted)
        for call in runner.calls where call.executable == dnglab.path {
            XCTAssertFalse(call.arguments.contains("-f"), "\(call.arguments)")
            XCTAssertFalse(call.arguments.contains("--override"), "\(call.arguments)")
        }
    }

    // Rule 4 alone fails: every tag is written, and the result says why the
    // DNG is no full match.
    func testALensFrameGetsEveryTagAndTheResultCarriesTheReason() throws {
        let conversion = try converter().convert(arw, facts: lens)
        XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: .noLensCorrection))
        guard runner.calls.count == 3 else { return XCTFail("\(runner.calls.count) calls, not 3") }
        XCTAssertEqual(runner.calls[1].arguments.count, 13, "the nine tags and the file name")
        XCTAssertTrue(runner.calls[1].arguments.contains("-IFD0:CameraCalibration1=1.0288 0 0 0 1 0 0 0 0.9579"))
        XCTAssertTrue(runner.calls[1].arguments.contains("-IFD0:OriginalRawFileName=DSC05680.ARW"))
    }

    // Rule 1, 2, 3 or 5 fails: the levels stay dnglab's own. The file name
    // is still written, because the pending rule needs it (design 4.1).
    func testWithNoTableRowOnlyTheFileNameIsWrittenAndTheResultCarriesTheReason() throws {
        let iso1250 = ARWFacts(model: "ILCE-7SM3", iso: 1250, daylightLevels: adapted.daylightLevels,
                               saysNoLensCorrection: true)
        let uncompressed = ARWFacts(model: "ILCE-7SM3", iso: 800, daylightLevels: adapted.daylightLevels,
                                    saysNoLensCorrection: true, rawFileType: 0)
        for (facts, rule) in [(ARWFacts.none, AdobeMatch.Rule.model), (iso1250, .iso),
                              (uncompressed, .compressedRaw)] {
            setUp()
            let conversion = try converter().convert(arw, facts: facts)
            XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: rule))
            XCTAssertEqual(runner.calls, [
                convertCall,
                call(exiftool, ["-m", "-overwrite_original", "-IFD0:OriginalRawFileName=DSC05680.ARW", workPath]),
                call(exiftool, ["-m", "-n", "-T", "-IFD0:OriginalRawFileName", workPath]),
            ])
        }
    }

    // exiftool prints a number in its own form. The compare is on numbers.
    func testAReadBackInAnotherTextFormOfTheSameNumbersPasses() throws {
        tools.readBack = ["16383", "0.15", "0.9888 0 0 0 1 0 0 0 0.9955", "0.9888 0 0 0 1 0 0 0 0.9955",
                          "9.17112993057145e-05 1.80963827089821e-07 1.32825207904173e-04 1.86198019692823e-07 "
                              + "6.88838025482567e-05 1.77853114759923e-07",
                          "0.6", "1.25", "1.0", "250", "DSC05680.ARW"].joined(separator: "\t")
        XCTAssertEqual(try converter().convert(arw, facts: adapted).dng, dng)
    }

    // MARK: A control character in the name of the ARW

    // exiftool prints a control character as a period. For `a<tab>b.ARW` the
    // real exiftool 13.55 read `OriginalRawFileName` back as `a.b.ARW`
    // (2026-10-09). The read-back compares in that form, so the conversion
    // passes. Before, such an ARW failed its match on every run.
    func testANameWithATabOrALineEndReadsBackAsExiftoolPrintsItAndPasses() throws {
        for (name, printed) in [("a\tb.ARW", "a.b.ARW"), ("n\nl.ARW", "n.l.ARW")] {
            setUp()
            let arw = URL(fileURLWithPath: "/tmp/Shoot 1/\(name)")
            tools.readBack = ["16383", "0.15", "0.9888 0 0 0 1 0 0 0 0.9955", "0.9888 0 0 0 1 0 0 0 0.9955",
                              Self.noise800, "0.6", "1.25", "1", "250", printed].joined(separator: "\t")
            let conversion = try converter().convert(arw, facts: adapted)
            XCTAssertEqual(conversion.dng, ConverterOutput.url(for: arw))
            XCTAssertTrue(runner.calls[1].arguments.contains("-IFD0:OriginalRawFileName=\(name)"),
                          "the real name is written, with its control character")
        }
    }

    // Only the control characters are folded. Another name is still wrong.
    func testAnotherNameStillFailsTheReadBackOfANameWithATab() {
        let arw = URL(fileURLWithPath: "/tmp/Shoot 1/a\tb.ARW")
        for wrong in ["a b.ARW", "ab.ARW", "a.b.arw", "a..b.ARW", "-"] {
            setUp()
            tools.readBack = wrong
            XCTAssertThrowsError(try converter().convert(arw, facts: .none), wrong) {
                // The sentence names what exiftool had to print. No tab
                // goes into a note.
                XCTAssertEqual(($0 as? ConvertError)?.text,
                               "The tag IFD0:OriginalRawFileName did not read back as a.b.ARW.", wrong)
            }
        }
    }

    // MARK: dnglab fails

    func testANonZeroExitWithAFileReportsTheWorkFileAndWritesNoTag() {
        tools.dnglabExit = 1
        assertFails(.failed("dnglab returned 1.", partial: work))
        XCTAssertEqual(runner.calls, [convertCall])
        XCTAssertEqual(tools.renames, [], "a failed conversion never gets the DNG's name")
    }

    // dnglab returns 6 when its output exists, and does not touch it. The
    // leftover was discarded before dnglab started, so this file came after
    // that. It is not this conversion's, and it is not reported.
    // The words are what dnglab 0.8.0 printed on 2026-10-09 for a work file
    // that was there, with exit code 6. dnglab names the file by its whole
    // path. The sentence has the name only: the file is beside the photo,
    // and a note names every other file by its name.
    func testExitCodeSixReportsNoPartialAlsoWithAFileAtTheWorkName() {
        tools.dnglabExit = 6
        tools.dnglabError = [
            "Converted 0/1 files, 1 failed:",
            "   /tmp/Shoot 1/DSC05680.ARW",
            "Total time: 0.00s",
            "Error: Already exists: /tmp/Shoot 1/.DSC05680.desqueeze-work.dng",
        ].joined(separator: "\n") + "\n"
        assertFails(.failed("dnglab returned 6. Already exists: .DSC05680.desqueeze-work.dng.", partial: nil))
        XCTAssertTrue(disk.paths.contains(workPath), "a file is at the work name")
        XCTAssertEqual(runner.calls, [convertCall])
        XCTAssertEqual(tools.renames, [])
    }

    // dnglab's reason is cut to 200 characters. The path of the work file
    // becomes its name before that, so a long path does not stay as a path
    // that is cut in the middle.
    func testTheWorkFileIsNamedByItsNameAlsoWhenItsPathIsLong() {
        let deep = "/tmp/" + String(repeating: "a folder with a long name/", count: 9) + "Shoot 1"
        let arw = URL(fileURLWithPath: deep + "/DSC05680.ARW")
        XCTAssertGreaterThan(deep.count, DnglabConverter.reasonLimit)
        tools.dnglabExit = 6
        tools.dnglabError = "Error: Already exists: \(deep)/.DSC05680.desqueeze-work.dng\n"
        XCTAssertThrowsError(try converter().convert(arw, facts: adapted)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("dnglab returned 6. Already exists: .DSC05680.desqueeze-work.dng.", partial: nil))
        }
    }

    // Only the path of the work file changes. Every other word of dnglab's
    // stays, also another path.
    func testTheOtherWordsOfDnglabsReasonStayAsTheyAre() {
        tools.dnglabExit = 1
        tools.dnglabError = "Error: Cannot read /tmp/Shoot 1/DSC05680.ARW, wanted by /tmp/Shoot 1/other.dng\n"
        assertFails(.failed(
            "dnglab returned 1. Cannot read /tmp/Shoot 1/DSC05680.ARW, wanted by /tmp/Shoot 1/other.dng.",
            partial: work))
    }

    // A file that dnglab cannot read: exit code 7, and no DNG.
    func testANonZeroExitWithNoFileReportsNoPartialDNG() {
        tools.dnglabExit = 7
        tools.dnglabWrites = nil
        assertFails(.failed("dnglab returned 7.", partial: nil))
        XCTAssertEqual(runner.calls, [convertCall])
    }

    // MARK: dnglab's own words

    /// What dnglab 0.8.0 printed on standard error on 2026-10-09 for a text
    /// file named `junk.ARW`, with exit code 7. The first line has the
    /// terminal colour codes that dnglab writes, also into a pipe.
    static let realStandardError = [
        "[\u{1B}[31mERROR \u{1B}[0m][dnglab_lib::jobs::raw2dng] Unsupported file: \"junk.ARW\"",
        "Error: No decoder found, model '', make: '', mode: ''",
        "Please see https://github.com/dnglab/dnglab/blob/main/CONTRIBUTE_SAMPLES.md how to contribute samples "
            + "to get this camera supported. (bin/dnglab/dnglab-lib/src/jobs/raw2dng.rs:121)",
        "Converted 0/1 files, 1 failed:",
        "   /tmp/Shoot 1/junk.ARW",
        "Total time: 0.02s",
        "Error: Unsupported file: Error: No decoder found, model '', make: '', mode: ''",
    ].joined(separator: "\n") + "\n"

    static let realReason = "Unsupported file: Error: No decoder found, model '', make: '', mode: ''"

    func testTheReasonIsTheLastErrorLineOfTheRealOutputWithoutItsPrefix() {
        XCTAssertEqual(DnglabConverter.reason(inStandardError: Self.realStandardError), Self.realReason)
    }

    // "dnglab returned 7." alone says nothing about the file. dnglab's own
    // reason follows it on the same line.
    func testAFailedConversionSaysTheExitCodeThenDnglabsReason() {
        tools.dnglabExit = 7
        tools.dnglabWrites = nil
        tools.dnglabError = Self.realStandardError
        XCTAssertEqual(error() as? ConvertError,
                       .failed("dnglab returned 7. \(Self.realReason).", partial: nil))
    }

    func testTheReasonKeepsThePartialOutput() {
        tools.dnglabExit = 1
        tools.dnglabError = "Error: The disk is full.\n"
        assertFails(.failed("dnglab returned 1. The disk is full.", partial: work))
    }

    func testWithNoErrorLineTheTextStaysAsItIs() {
        tools.dnglabExit = 7
        tools.dnglabWrites = nil
        for output in ["", "\n\n", "Converted 0/1 files, 1 failed:\nTotal time: 0.02s\n", "Error:\n", "Error:   \n",
                       "An Error: in the middle of a line\n"] {
            tools.dnglabError = output
            XCTAssertNil(DnglabConverter.reason(inStandardError: output), "\"\(output)\"")
            XCTAssertEqual(error() as? ConvertError, .failed("dnglab returned 7.", partial: nil), "\"\(output)\"")
        }
    }

    func testTheReasonIsTheLastErrorLineAndEmptyLinesAfterItDoNotCount() {
        XCTAssertEqual(DnglabConverter.reason(inStandardError: "Error: first\nother words\nError: second\n\n  \n"),
                       "second")
    }

    func testTerminalColourCodesAreRemovedFromTheReason() {
        XCTAssertEqual(
            DnglabConverter.reason(inStandardError: "\u{1B}[1;31mError:\u{1B}[0m No \u{1B}[33mdecoder\u{1B}[0m found\n"),
            "No decoder found")
    }

    func testAReasonIsCutToTwoHundredCharacters() {
        let long = String(repeating: "x", count: 450)
        XCTAssertEqual(DnglabConverter.reason(inStandardError: "Error: \(long)\n"), String(repeating: "x", count: 200))
        XCTAssertEqual(DnglabConverter.reason(inStandardError: "Error: \(String(long.prefix(200)))\n")?.count, 200)
    }

    // Adobe DNG Converter prints no such line, and its text does not change.
    func testAdobeDNGConverterHasNoReasonLine() {
        let runner = FakeRunner()
        runner.handler = { _ in ProcessResult(exitCode: 3, stdout: "", stderr: "Error: something\n") }
        let adobe = AdobeConverter(executable: URL(fileURLWithPath: "/fake/Adobe DNG Converter"), runner: runner,
                                   discardLeftover: { _ in }, fileExists: { _ in false }, fileSize: { _ in nil })
        XCTAssertThrowsError(try adobe.convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("Adobe DNG Converter returned 3.", partial: nil))
        }
    }

    // Killed in work, dnglab left a DNG of 0 bytes, of 4 bytes, or a cut-off
    // file (design 13.2).
    func testASignalWithAFileReportsTheWorkFileAndTheSignal() {
        for bytes in [0, 4, 12_100_000] {
            setUp()
            tools.dnglabWrites = bytes
            tools.failure = (1, ProcessSignalError(signal: 15, stdout: "", stderr: ""))
            assertFails(.failed("The program was ended by signal 15.", partial: work), nil, "\(bytes) bytes")
            XCTAssertEqual(runner.calls, [convertCall])
            XCTAssertEqual(tools.renames, [])
        }
    }

    func testASignalWithNoFileThrowsTheSignalErrorAsItIs() {
        tools.dnglabWrites = nil
        let signal = ProcessSignalError(signal: 9, stdout: "out", stderr: "err")
        tools.failure = (1, signal)
        XCTAssertEqual(error() as? ProcessSignalError, signal)
    }

    // dnglab never ran, so a file at the name is not this run's.
    func testARunnerErrorThatIsNoSignalPassesOnAsItCameAndReportsNoPartialDNG() {
        tools.failure = (1, NamedError(text: "The program could not start."))
        let thrown = error()
        XCTAssertNil(thrown as? ConvertError)
        XCTAssertEqual((thrown as? NamedError)?.text, "The program could not start.")
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testExitZeroWithNoDNGFails() {
        tools.dnglabWrites = nil
        XCTAssertEqual(error() as? ConvertError, .failed("dnglab made no DNG. It may not support this file."))
        XCTAssertEqual(runner.calls, [convertCall])
    }

    func testExitZeroWithAnEmptyWorkFileFailsAndReportsTheWorkFile() {
        tools.dnglabWrites = 0
        assertFails(.failed("dnglab made an empty DNG.", partial: work))
        XCTAssertEqual(runner.calls, [convertCall])
        XCTAssertEqual(tools.renames, [])
    }

    func testExitZeroWithAWorkFileOfUnknownSizeMadeNoDNGAndReportsNoPartialDNG() {
        disk.unreadableSizes = [workPath]
        XCTAssertEqual(error() as? ConvertError,
                       .failed("dnglab made no DNG. It may not support this file.", partial: nil))
    }

    // MARK: The match fails

    // dnglab made the work file in this run, so it is the partial output.
    func testAFailedMatchWriteReportsTheWorkFileWithExiftoolsWords() {
        tools.writeResult = ProcessResult(
            exitCode: 1, stdout: "    0 image files updated\n    1 files weren't updated due to errors\n",
            stderr: "Error: Not a valid TIFF - /tmp/Shoot 1/.DSC05680.desqueeze-work.dng\n")
        assertFails(.failed("The tags could not be written: Error: Not a valid TIFF", partial: work))
        XCTAssertEqual(runner.calls.count, 2, "no read-back after a write that failed")
        XCTAssertEqual(tools.renames, [], "a DNG with no match never gets its name")
    }

    // exiftool exits 0 when it changed nothing.
    func testAMatchWriteThatUpdatedNoFileFails() {
        tools.writeResult = ProcessResult(exitCode: 0, stdout: "    0 image files updated\n", stderr: "")
        assertFails(.failed("The tags could not be written: 0 image files updated", partial: work))
    }

    // dnglab ran, so every error after it reports the work file: also an
    // exiftool that cannot start, and one that a signal ended.
    func testAMatchWriteThatCannotStartOrIsEndedReportsTheWorkFile() {
        tools.failure = (2, NamedError(text: "The program could not start."))
        assertFails(.failed("The program could not start.", partial: work))

        setUp()
        tools.failure = (2, ProcessSignalError(signal: 2, stdout: "", stderr: ""))
        assertFails(.failed("The program was ended by signal 2.", partial: work))

        setUp()
        tools.failure = (3, ProcessSignalError(signal: 2, stdout: "", stderr: ""))
        assertFails(.failed("The program was ended by signal 2.", partial: work))
        XCTAssertEqual(tools.renames, [])
    }

    func testAReadBackThatDiffersInOneTagReportsTheWorkFileAndNamesTheTag() {
        func readBack(_ change: (inout [String]) -> Void) -> String {
            var cells = ["16383", "0.15", "0.9888 0 0 0 1 0 0 0 0.9955", "0.9888 0 0 0 1 0 0 0 0.9955", Self.noise800,
                         "0.6", "1.25", "1", "250", "DSC05680.ARW"]
            change(&cells)
            return cells.joined(separator: "\t")
        }
        let cases: [(String, String)] = [
            (readBack { $0[0] = "15360" }, "The tag SubIFD:WhiteLevel did not read back as 16383."),
            (readBack { $0[1] = "-0.85" }, "The tag IFD0:BaselineExposure did not read back as 0.15."),
            (readBack { $0[3] = "0.9889 0 0 0 1 0 0 0 0.9955" },
             "The tag IFD0:CameraCalibration2 did not read back as 0.9888 0 0 0 1 0 0 0 0.9955."),
            (readBack { $0[4] = AdobeMatch.ilce7SM3.byISO[640]!.noiseProfile.joined(separator: " ") },
             "The tag IFD0:NoiseProfile did not read back as \(Self.noise800)."),
            (readBack { $0[7] = "-" }, "The tag SubIFD:AntiAliasStrength did not read back as 1."),
            (readBack { $0[9] = "dsc05680.arw" }, "The tag IFD0:OriginalRawFileName did not read back as DSC05680.ARW."),
            (readBack { $0[9] = "-" }, "The tag IFD0:OriginalRawFileName did not read back as DSC05680.ARW."),
            (readBack { $0.removeLast() }, "The tags did not read back."),
            (readBack { $0.append("more") }, "The tags did not read back."),
            ("", "The tags did not read back."),
        ]
        for (text, words) in cases {
            setUp()
            tools.readBack = text
            assertFails(.failed(words, partial: work), nil, words)
            XCTAssertEqual(runner.calls.count, 3)
            XCTAssertEqual(tools.renames, [], "a DNG whose match did not read back never gets its name")
        }
    }

    // MARK: The rename

    // Another program made `<base>.dng` after the check before the start,
    // while dnglab worked. That file is not this run's: it is not reported,
    // and nothing replaces it. The work file is the partial output. The
    // error holds for every converter, so the job does not ask the next one.
    func testARenameThatFindsTheNameTakenReportsTheWorkFileAndNeverTheDNGOfTheOtherProgram() {
        let (disk, dngPath) = (disk!, dngPath)
        tools.renameOutcome = .nameTaken
        // The other program's DNG appears while dnglab works.
        let handler = runner.handler
        runner.handler = { call in
            if call.arguments.first == "convert" { disk.paths.insert(dngPath) }
            return handler(call)
        }
        let thrown = error() as? ConvertError
        XCTAssertEqual(thrown, .failedForAll("A DNG with this name exists already. Not converted.", partial: work))
        XCTAssertNotEqual(thrown?.partial, dng)
        XCTAssertEqual(runner.calls.count, 3, "the match was written and read back before the rename")
        XCTAssertEqual(tools.renames, [[workPath, dngPath]])
        XCTAssertEqual(disk.paths, [dngPath, workPath], "both files are where they were")
    }

    func testARenameThatFailsForAnotherReasonReportsTheWorkFileWithTheSystemsWords() {
        tools.renameOutcome = .failed(EACCES)
        assertFails(.failed("The DNG could not get the name DSC05680.dng: Permission denied.", partial: work))
        XCTAssertEqual(disk.paths, [workPath])
    }

    // MARK: A work file that is gone is not reported

    // The work file vanished before the rename: the system says "No such
    // file". The result reports no partial output, so the job sends nothing
    // to the Trash, and no note names a file that is not there.
    func testARenameThatFailsBecauseTheWorkFileIsGoneReportsNoPartial() {
        tools.renameOutcome = .failed(ENOENT)
        tools.workFileIsGoneAtTheRename = true
        assertFails(.failed("The DNG could not get the name DSC05680.dng: No such file or directory.", partial: nil))
        XCTAssertEqual(tools.renames, [[workPath, dngPath]])
        XCTAssertEqual(disk.paths, [])
    }

    // The same for a name that is taken, on the path of a volume with no
    // exclusive rename: the name is checked first, and the work file is gone.
    func testANameTakenWithAWorkFileThatIsGoneReportsNoPartial() {
        tools.renameOutcome = .nameTaken
        tools.workFileIsGoneAtTheRename = true
        XCTAssertEqual(error() as? ConvertError,
                       .failedForAll("A DNG with this name exists already. Not converted.", partial: nil))
    }

    // The same for a match that failed: the work file was there after
    // dnglab, and it is gone when the write of the tags has failed.
    func testAFailedMatchWithAWorkFileThatIsGoneReportsNoPartial() {
        let (disk, workPath) = (disk!, workPath)
        let handler = runner.handler
        runner.handler = { call in
            if call.arguments.contains("-overwrite_original") { disk.paths.remove(workPath) }
            return handler(call)
        }
        tools.writeResult = ProcessResult(exitCode: 1, stdout: "    0 image files updated\n",
                                          stderr: "Error: File not found - \(workPath)\n")
        assertFails(.failed("The tags could not be written: Error: File not found", partial: nil))
        XCTAssertEqual(tools.renames, [])
    }

    // On real files, with the rename of the system: the read-back of the
    // match is the last call before the rename, and here it takes the work
    // file away. The real `renamex_np` then answers "No such file".
    func testOnTheRealDiskAWorkFileThatVanishedBeforeTheRenameIsNotReported() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let arw = folder.appendingPathComponent("frame 1.ARW")
        let work = folder.appendingPathComponent(".frame 1.desqueeze-work.dng")
        try Data("raw bytes".utf8).write(to: arw)
        let tools = ScriptedTools()
        let scripted = tools.runner.handler
        tools.runner.handler = { call in
            let result = scripted(call)
            if call.arguments.contains("-T") { try? FileManager.default.removeItem(at: work) }
            return result
        }
        let converter = DnglabConverter(executable: ScriptedTools.dnglab, exiftool: ScriptedTools.exiftool,
                                        runner: tools.runner,
                                        discardLeftover: { XCTFail("no leftover: \($0.lastPathComponent)") })

        XCTAssertThrowsError(try converter.convert(arw, facts: adapted)) {
            XCTAssertEqual($0 as? ConvertError, .failed(
                "The DNG could not get the name frame 1.dng: No such file or directory.", partial: nil))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["frame 1.ARW"])
    }

    // The rename that a converter gets when no one gives it one must be the
    // exclusive one. Here no `rename:` is given, the files are real, and the
    // "dnglab" of the runner also makes `<base>.dng`, as another program
    // would at the wrong moment. A plain `rename` would put the work file
    // over that DNG.
    func testTheDefaultRenameNeverReplacesADNGThatAppearedWhileDnglabWorked() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let arw = folder.appendingPathComponent("frame 1.ARW")
        let dng = folder.appendingPathComponent("frame 1.dng")
        let work = folder.appendingPathComponent(".frame 1.desqueeze-work.dng")
        try Data("raw bytes".utf8).write(to: arw)
        let others = Data("another program's DNG".utf8)
        let tools = ScriptedTools()
        let scripted = tools.runner.handler
        tools.runner.handler = { call in
            let result = scripted(call)
            if call.executable == ScriptedTools.dnglab.path {
                FileManager.default.createFile(atPath: dng.path, contents: others)
            }
            return result
        }
        let converter = DnglabConverter(executable: ScriptedTools.dnglab, exiftool: ScriptedTools.exiftool,
                                        runner: tools.runner,
                                        discardLeftover: { XCTFail("no leftover: \($0.lastPathComponent)") })

        XCTAssertThrowsError(try converter.convert(arw, facts: adapted)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failedForAll("A DNG with this name exists already. Not converted.", partial: work))
        }

        XCTAssertEqual(try Data(contentsOf: dng), others, "the DNG of the other program has the same bytes")
        XCTAssertEqual(try Data(contentsOf: work), ScriptedTools.dnglabBytes, "the work file stays, for the job")
        XCTAssertEqual(tools.runner.calls.count, 3, "dnglab, the match write and its read-back all ran")
    }

    // MARK: A leftover work file (design 13.3, step 1)

    // A run that ended hard left the work file. Its name says that it is
    // this app's own, so it is discarded, and the conversion goes on.
    func testALeftoverWorkFileIsDiscardedBeforeDnglabStarts() throws {
        disk.paths = [workPath]
        disk.sizes[workPath] = 4
        let conversion = try converter().convert(arw, facts: adapted)
        XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: nil))
        XCTAssertEqual(tools.discarded, [workPath], "the discard gets the work file, and only it")
        XCTAssertEqual(runner.calls.count, 3)
        XCTAssertEqual(disk.paths, [dngPath])
    }

    // The Trash refused the leftover. No program starts, and the sentence
    // names the file to delete. No partial: this conversion made no file.
    func testALeftoverThatCannotBeDiscardedStopsTheConversionBeforeAnyProgram() {
        disk.paths = [workPath]
        tools.discardError = NamedError(text: "The Trash refused it.")
        assertFails(.failedForAll(
            "A leftover file, .DSC05680.desqueeze-work.dng, is beside this photo. \(hiddenFileSentence) "
                + "Delete it, then run again.",
            partial: nil))
        XCTAssertEqual(tools.discarded, [workPath])
        XCTAssertEqual(runner.calls, [], "no program started")
        XCTAssertEqual(disk.paths, [workPath], "the leftover is where it was")
    }

    // exiftool that ended hard in the match write left
    // `<work file>_exiftool_tmp`, and the real exiftool then refuses every
    // write of the work file. Both names are this app's own, so step 1
    // discards both, the work file first, and the conversion goes on.
    func testTheLeftoverOfExiftoolBesideTheWorkFileIsDiscardedWithTheWorkFile() throws {
        for leftovers in [[workTmpPath], [workPath, workTmpPath]] {
            setUp()
            disk.paths = Set(leftovers)
            let conversion = try converter().convert(arw, facts: adapted)
            XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: nil), "\(leftovers)")
            XCTAssertEqual(tools.discarded, leftovers, "the discard gets the two names of this app, and no other")
            XCTAssertEqual(runner.calls.count, 3, "\(leftovers)")
            XCTAssertEqual(disk.paths, [dngPath], "\(leftovers)")
        }
    }

    // The Trash refused the leftover of exiftool. No program starts, and
    // the sentence names that file.
    func testALeftoverOfExiftoolBesideTheWorkFileThatCannotBeDiscardedStopsTheConversion() {
        disk.paths = [workTmpPath]
        tools.discardError = NamedError(text: "The Trash refused it.")
        assertFails(.failedForAll(
            "A leftover file, .DSC05680.desqueeze-work.dng_exiftool_tmp, is beside this photo. \(hiddenFileSentence) "
                + "Delete it, then run again.",
            partial: nil))
        XCTAssertEqual(tools.discarded, [workTmpPath])
        XCTAssertEqual(runner.calls, [], "no program started")
        XCTAssertEqual(disk.paths, [workTmpPath], "the leftover is where it was")
    }

    // MARK: Step 1 removes only a regular file (design 13.3)

    // A folder or a link has the name of the work file, or of exiftool's
    // leftover beside it. The app does not send it to the Trash. The ARW
    // stops with the leftover note, no program starts, and nothing moves:
    // also not the regular file at the other name.
    func testAThingThatIsNoRegularFileAtALeftoverNameStopsTheConversionAndNothingMoves() {
        let names = [workPath: ".DSC05680.desqueeze-work.dng", workTmpPath: ".DSC05680.desqueeze-work.dng_exiftool_tmp"]
        for (notAFile, both) in [(workPath, false), (workTmpPath, false), (workPath, true), (workTmpPath, true)] {
            setUp()
            disk.paths = both ? [workPath, workTmpPath] : [notAFile]
            disk.notRegularFiles = [notAFile]
            assertFails(.failedForAll(
                "A leftover file, \(names[notAFile]!), is beside this photo. \(hiddenFileSentence) "
                    + "Delete it, then run again.",
                partial: nil), nil, notAFile)
            XCTAssertEqual(tools.discarded, [], "\(notAFile), both \(both): nothing moves")
            XCTAssertEqual(runner.calls, [], "\(notAFile): no program started")
            XCTAssertEqual(disk.paths, both ? [workPath, workTmpPath] : [notAFile])
        }
    }

    // The same on the real disk, with the questions that the app asks.
    func testOnTheRealDiskAFolderOrALinkAtALeftoverNameStopsTheConversionAndStaysAsItWas() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let files = FileManager.default
        let asked = CallLog()
        let real = DnglabConverter(executable: dnglab, exiftool: exiftool, runner: runner,
                                   discardLeftover: { asked.entries.append($0.lastPathComponent) })
        var number = 0
        for (what, make) in try RawConverterTests.thingsThatAreNoRegularFile(in: folder) {
            for suffix in ["", "_exiftool_tmp"] {
                number += 1
                let name = ".frame \(number).desqueeze-work.dng\(suffix)"
                let thing = folder.appendingPathComponent(name)
                try make(thing)
                let before = try files.attributesOfItem(atPath: thing.path)

                XCTAssertThrowsError(
                    try real.convert(folder.appendingPathComponent("frame \(number).ARW"), facts: adapted),
                    "\(what) at \(name)"
                ) {
                    XCTAssertEqual($0 as? ConvertError, .failedForAll(
                        "A leftover file, \(name), is beside this photo. \(hiddenFileSentence) Delete it, then run again.",
                        partial: nil), "\(what) at \(name)")
                }

                let after = try files.attributesOfItem(atPath: thing.path)
                XCTAssertEqual(after[.type] as? FileAttributeType, before[.type] as? FileAttributeType, what)
                XCTAssertEqual(after[.systemFileNumber] as? Int, before[.systemFileNumber] as? Int, what)
            }
        }
        XCTAssertEqual(asked.entries, [], "nothing was given to the discard")
        XCTAssertEqual(runner.calls, [], "no program started")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(".frame 1.desqueeze-work.dng/inside.txt")),
                       Data("inside".utf8), "the file in the folder is where it was")
    }

    // MARK: Before the start

    // The DNG that stopped the converter is not ours: no partial, no call.
    func testRefusesToStartWhenTheDNGExistsAlreadyAndDoesNotCallItPartial() {
        disk.paths = [dngPath]
        disk.sizes[dngPath] = 0
        XCTAssertEqual(error() as? ConvertError,
                       .failed("A DNG with this name exists already. Not converted.", partial: nil))
        XCTAssertEqual(runner.calls, [])
    }

    // A leftover file of exiftool beside the DNG's name, from a tag step
    // that ended hard: no program starts, nothing is discarded, and no
    // partial. The file is not this app's to remove.
    func testALeftoverFileOfExiftoolBesideTheDNGsNameStopsTheConversionBeforeAnyProgram() {
        // The two leftovers of this app are there too. They are not
        // discarded: the conversion could not pass, so nothing is touched.
        let leftover = "/tmp/Shoot 1/DSC05680.dng_exiftool_tmp"
        disk.paths = [leftover, workPath, workTmpPath]
        assertFails(.failedForAll(
            "A leftover file, DSC05680.dng_exiftool_tmp, is beside this photo. Delete it, then run again.",
            partial: nil))
        XCTAssertEqual(runner.calls, [])
        XCTAssertEqual(tools.discarded, [])
        XCTAssertEqual(tools.renames, [])
        XCTAssertEqual(disk.paths, [leftover, workPath, workTmpPath])
    }

    // The check of the DNG's name comes before step 1: with a DNG at the
    // name, nothing is discarded, and nothing starts.
    func testTheCheckOfTheNameComesBeforeTheLeftoverIsDiscarded() {
        disk.paths = [dngPath, workPath]
        XCTAssertEqual(error() as? ConvertError,
                       .failed("A DNG with this name exists already. Not converted.", partial: nil))
        XCTAssertEqual(tools.discarded, [])
        XCTAssertEqual(runner.calls, [])
        XCTAssertEqual(disk.paths, [dngPath, workPath])
    }

    func testOnTheRealDiskAFileAFolderAndADanglingLinkEachStopTheConverterBeforeItStarts() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let files = FileManager.default
        let plant: [(String, (URL) throws -> Void)] = [
            ("a file", { try Data("x".utf8).write(to: $0) }),
            ("a folder", { try files.createDirectory(at: $0, withIntermediateDirectories: false) }),
            ("a link to a folder", { try files.createSymbolicLink(at: $0, withDestinationURL: folder) }),
            ("a dangling link", {
                try files.createSymbolicLink(atPath: $0.path, withDestinationPath: folder.path + "/no such file")
            }),
        ]
        let real = DnglabConverter(executable: dnglab, exiftool: exiftool, runner: runner,
                                   discardLeftover: { _ in XCTFail("there is no leftover") })
        for (number, (what, make)) in plant.enumerated() {
            try make(folder.appendingPathComponent("frame \(number).dng"))
            XCTAssertThrowsError(
                try real.convert(folder.appendingPathComponent("frame \(number).ARW"), facts: adapted), what
            ) {
                XCTAssertEqual($0 as? ConvertError,
                               .failed("A DNG with this name exists already. Not converted.", partial: nil), what)
            }
        }
        XCTAssertEqual(runner.calls, [], "no program started")
    }
}
