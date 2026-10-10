import XCTest
@testable import DesqueezeCore

final class DnglabConverterTests: XCTestCase {
    let dnglab = URL(fileURLWithPath: "/opt/homebrew/bin/dnglab")
    let exiftool = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool")
    let arw = URL(fileURLWithPath: "/tmp/Shoot 1/DSC05680.ARW")
    let dngPath = "/tmp/Shoot 1/DSC05680.dng"
    var dng: URL { URL(fileURLWithPath: dngPath) }

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

    /// What the three programs do, and what they were asked.
    final class Tools: @unchecked Sendable {
        var dnglabExit: Int32 = 0
        /// The bytes of the DNG that dnglab leaves. Nil: it leaves no file.
        var dnglabWrites: Int? = 1_000
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
        let (runner, disk, tools, dnglab, dngPath) = (runner!, disk!, tools!, dnglab, dngPath)
        runner.handler = { call in
            if call.executable == dnglab.path {
                if let bytes = tools.dnglabWrites {
                    disk.paths.insert(dngPath)
                    disk.sizes[dngPath] = bytes
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
        return DnglabConverter(executable: dnglab, exiftool: exiftool, runner: ThrowingRunner(runner, tools),
                               fileExists: { disk.exists($0) }, fileSize: { disk.size($0) })
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
        call(dnglab, ["convert", "--embed-raw", "false", "/tmp/Shoot 1/DSC05680.ARW", "/tmp/Shoot 1/DSC05680.dng"])
    }

    func error(_ facts: ARWFacts? = nil, file: StaticString = #filePath, line: UInt = #line) -> Error? {
        var thrown: Error?
        XCTAssertThrowsError(try converter().convert(arw, facts: facts ?? adapted), file: file, line: line) {
            thrown = $0
        }
        return thrown
    }

    // MARK: A conversion that passes

    func testAFullMatchIsThreeCallsWithTheExactArguments() throws {
        let conversion = try converter().convert(arw, facts: adapted)

        XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: nil))
        guard runner.calls.count == 3 else { return XCTFail("\(runner.calls.count) calls, not 3") }
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
            "/tmp/Shoot 1/DSC05680.dng",
        ]))
        XCTAssertEqual(runner.calls[2], call(exiftool, [
            "-m", "-n", "-T",
            "-SubIFD:WhiteLevel", "-IFD0:BaselineExposure", "-IFD0:CameraCalibration1", "-IFD0:CameraCalibration2",
            "-IFD0:NoiseProfile", "-IFD0:BaselineNoise", "-IFD0:BaselineSharpness", "-SubIFD:AntiAliasStrength",
            "-SubIFD:BayerGreenSplit", "-IFD0:OriginalRawFileName",
            "/tmp/Shoot 1/DSC05680.dng",
        ]))
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

    // Rule 1, 2 or 3 fails: the levels stay dnglab's own. The file name is
    // still written, because the pending rule needs it (design 4.1).
    func testWithNoTableRowOnlyTheFileNameIsWrittenAndTheResultCarriesTheReason() throws {
        let iso1250 = ARWFacts(model: "ILCE-7SM3", iso: 1250, daylightLevels: adapted.daylightLevels,
                               saysNoLensCorrection: true)
        for (facts, rule) in [(ARWFacts.none, AdobeMatch.Rule.model), (iso1250, .iso)] {
            setUp()
            let conversion = try converter().convert(arw, facts: facts)
            XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: rule))
            XCTAssertEqual(runner.calls, [
                convertCall,
                call(exiftool, ["-m", "-overwrite_original", "-IFD0:OriginalRawFileName=DSC05680.ARW",
                                "/tmp/Shoot 1/DSC05680.dng"]),
                call(exiftool, ["-m", "-n", "-T", "-IFD0:OriginalRawFileName", "/tmp/Shoot 1/DSC05680.dng"]),
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

    // MARK: dnglab fails

    func testANonZeroExitWithAFileReportsThePartialDNGAndWritesNoTag() {
        tools.dnglabExit = 1
        XCTAssertEqual(error() as? ConvertError, .failed("dnglab returned 1.", partial: dng))
        XCTAssertEqual(runner.calls, [convertCall])
    }

    // A file that dnglab cannot read: exit code 7, and no DNG.
    func testANonZeroExitWithNoFileReportsNoPartialDNG() {
        tools.dnglabExit = 7
        tools.dnglabWrites = nil
        XCTAssertEqual(error() as? ConvertError, .failed("dnglab returned 7.", partial: nil))
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

    func testTheReasonKeepsThePartialDNG() {
        tools.dnglabExit = 1
        tools.dnglabError = "Error: The disk is full.\n"
        XCTAssertEqual(error() as? ConvertError, .failed("dnglab returned 1. The disk is full.", partial: dng))
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
                                   fileExists: { _ in false }, fileSize: { _ in nil })
        XCTAssertThrowsError(try adobe.convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("Adobe DNG Converter returned 3.", partial: nil))
        }
    }

    // Killed in work, dnglab left a DNG of 0 bytes, of 4 bytes, or a cut-off
    // file (design 13.2).
    func testASignalWithAFileReportsThePartialDNGAndTheSignal() {
        for bytes in [0, 4, 12_100_000] {
            setUp()
            tools.dnglabWrites = bytes
            tools.failure = (1, ProcessSignalError(signal: 15, stdout: "", stderr: ""))
            XCTAssertEqual(error() as? ConvertError, .failed("The program was ended by signal 15.", partial: dng),
                           "\(bytes) bytes")
            XCTAssertEqual(runner.calls, [convertCall])
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

    func testExitZeroWithAnEmptyDNGFailsAndReportsThePartialDNG() {
        tools.dnglabWrites = 0
        XCTAssertEqual(error() as? ConvertError, .failed("dnglab made an empty DNG.", partial: dng))
        XCTAssertEqual(runner.calls, [convertCall])
    }

    func testExitZeroWithADNGOfUnknownSizeMadeNoDNGAndReportsNoPartialDNG() {
        disk.unreadableSizes = [dngPath]
        XCTAssertEqual(error() as? ConvertError,
                       .failed("dnglab made no DNG. It may not support this file.", partial: nil))
    }

    // MARK: The match fails

    // dnglab made the DNG in this run, so the file is the partial output.
    func testAFailedMatchWriteReportsThePartialDNGWithExiftoolsWords() {
        tools.writeResult = ProcessResult(
            exitCode: 1, stdout: "    0 image files updated\n    1 files weren't updated due to errors\n",
            stderr: "Error: Not a valid TIFF - /tmp/Shoot 1/DSC05680.dng\n")
        XCTAssertEqual(error() as? ConvertError,
                       .failed("The tags could not be written: Error: Not a valid TIFF", partial: dng))
        XCTAssertEqual(runner.calls.count, 2, "no read-back after a write that failed")
    }

    // exiftool exits 0 when it changed nothing.
    func testAMatchWriteThatUpdatedNoFileFails() {
        tools.writeResult = ProcessResult(exitCode: 0, stdout: "    0 image files updated\n", stderr: "")
        XCTAssertEqual(error() as? ConvertError,
                       .failed("The tags could not be written: 0 image files updated", partial: dng))
    }

    // dnglab ran, so every error after it reports the partial DNG: also an
    // exiftool that cannot start, and one that a signal ended.
    func testAMatchWriteThatCannotStartOrIsEndedReportsThePartialDNG() {
        tools.failure = (2, NamedError(text: "The program could not start."))
        XCTAssertEqual(error() as? ConvertError, .failed("The program could not start.", partial: dng))

        setUp()
        tools.failure = (2, ProcessSignalError(signal: 2, stdout: "", stderr: ""))
        XCTAssertEqual(error() as? ConvertError, .failed("The program was ended by signal 2.", partial: dng))

        setUp()
        tools.failure = (3, ProcessSignalError(signal: 2, stdout: "", stderr: ""))
        XCTAssertEqual(error() as? ConvertError, .failed("The program was ended by signal 2.", partial: dng))
    }

    func testAReadBackThatDiffersInOneTagReportsThePartialDNGAndNamesTheTag() {
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
            XCTAssertEqual(error() as? ConvertError, .failed(words, partial: dng), words)
            XCTAssertEqual(runner.calls.count, 3)
        }
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
        let real = DnglabConverter(executable: dnglab, exiftool: exiftool, runner: runner)
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
