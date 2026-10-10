import XCTest
@testable import DesqueezeCore

final class RawConverterTests: XCTestCase {
    let executable = URL(fileURLWithPath: "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter")
    let arw = URL(fileURLWithPath: "/tmp/Shoot 1/DSC05680.ARW")
    let dngPath = "/tmp/Shoot 1/DSC05680.dng"
    /// The hidden work file that the converter writes (design 13.3).
    let workPath = "/tmp/Shoot 1/.DSC05680.desqueeze-work.dng"
    /// What exiftool leaves beside the work file when it ends hard in
    /// dnglab's match.
    let workTmpPath = "/tmp/Shoot 1/.DSC05680.desqueeze-work.dng_exiftool_tmp"
    var runner: FakeRunner!
    var disk: FakeDisk!
    var steps: Steps!

    /// What the discard and the rename do, and what they were asked.
    final class Steps: @unchecked Sendable {
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
    }

    override func setUp() {
        runner = FakeRunner()
        disk = FakeDisk()
        steps = Steps()
    }

    func converter() -> AdobeConverter {
        let (disk, steps) = (disk!, steps!)
        return AdobeConverter(
            executable: executable, runner: runner,
            discardLeftover: {
                steps.discarded.append($0.path)
                if let error = steps.discardError { throw error }
                disk.paths.remove($0.path)
            },
            fileExists: { disk.exists($0) }, fileSize: { disk.size($0) }, fileIsRegular: { disk.isRegularFile($0) },
            rename: { from, to in
                steps.renames.append([from.path, to.path])
                if steps.workFileIsGoneAtTheRename { disk.paths.remove(from.path) }
                if steps.renameOutcome == .moved { disk.move(from.path, to: to.path) }
                return steps.renameOutcome
            })
    }

    /// The converter writes its file while it runs, where its arguments
    /// say. With `bytes` 0 the file is empty, as one that a signal cut short.
    func converterWritesItsFile(exitCode: Int32 = 0, bytes: Int = 1_000) {
        let disk = self.disk!
        runner.handler = { call in
            let output = FakeAdobe.output(of: call.arguments)
            disk.paths.insert(output)
            disk.sizes[output] = bytes
            return ProcessResult(exitCode: exitCode, stdout: "", stderr: "")
        }
    }

    var dng: URL { URL(fileURLWithPath: dngPath) }
    var work: URL { URL(fileURLWithPath: workPath) }

    /// The conversion fails with exactly `expected`. Whatever fails, the
    /// converter never reports `<base>.dng` as its partial output, and never
    /// leaves a file there: it writes the work file, and nothing else.
    func assertFails(_ expected: ConvertError, _ message: String = "", file: StaticString = #filePath,
                     line: UInt = #line) {
        XCTAssertThrowsError(try converter().convert(arw), message, file: file, line: line) {
            XCTAssertEqual($0 as? ConvertError, expected, message, file: file, line: line)
            XCTAssertNotEqual(($0 as? ConvertError)?.partial, dng, "the DNG's own name was reported as partial",
                              file: file, line: line)
        }
        XCTAssertFalse(disk.paths.contains(dngPath), "a failed conversion left a file at the DNG's name",
                       file: file, line: line)
    }

    // `-o` gives the name of the work file, and `-d` its folder. One call:
    // Adobe's file needs no match, so no exiftool starts. Then the rename
    // that never replaces gives the work file the name `<base>.dng`.
    func testPassesTheExactArgumentsWritesTheWorkFileAndReturnsTheDNG() throws {
        converterWritesItsFile()
        let conversion = try converter().convert(arw)
        XCTAssertEqual(runner.calls, [FakeRunner.Call(executable: executable.path, arguments: [
            "-c", "-d", "/tmp/Shoot 1", "-o", ".DSC05680.desqueeze-work.dng", "/tmp/Shoot 1/DSC05680.ARW",
        ])])
        XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: nil), "Adobe's own DNG is never unmatched")
        XCTAssertEqual(steps.renames, [[workPath, dngPath]])
        XCTAssertEqual(disk.paths, [dngPath], "the DNG is at its name, and no work file is left")
        XCTAssertEqual(steps.discarded, [], "there was no leftover to discard")
    }

    // `-o` takes a name, not a path: the folder comes from `-d`.
    func testTheOutputNameIsTheNameOfTheWorkFileAndNeverAPath() throws {
        converterWritesItsFile()
        _ = try converter().convert(arw)
        let arguments = try XCTUnwrap(runner.calls.first?.arguments)
        let name = arguments[try XCTUnwrap(arguments.firstIndex(of: "-o")) + 1]
        XCTAssertEqual(name, ConverterOutput.workURL(for: arw).lastPathComponent)
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(arguments.contains("-h"), "-h opens a window, and the process never returns")
    }

    // The converter that returns non-zero may have written part of the file.
    // That file is the work file, whose name is this app's own.
    func testANonZeroExitWithAFileReportsTheWorkFile() {
        converterWritesItsFile(exitCode: 1)
        assertFails(.failed("Adobe DNG Converter returned 1.", partial: work))
        XCTAssertEqual(steps.renames, [], "a failed conversion never gets the DNG's name")
    }

    func testANonZeroExitWithNoFileReportsNoPartialDNG() {
        runner.handler = { _ in ProcessResult(exitCode: 1, stdout: "", stderr: "") }
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("Adobe DNG Converter returned 1.", partial: nil))
        }
    }

    // A signal ends the converter before it finishes. The file it began is
    // in the folder, and may have no bytes (design 4.3, tested 2026-10-09).
    func testASignalWithAFileReportsTheWorkFileAndTheSignal() {
        converterWritesItsFile(bytes: 0)
        runner.failure = ProcessSignalError(signal: 15, stdout: "", stderr: "")
        assertFails(.failed("The program was ended by signal 15.", partial: work))
        XCTAssertEqual(steps.renames, [])
    }

    func testASignalWithNoFileThrowsTheSignalErrorAsItIs() {
        let signal = ProcessSignalError(signal: 9, stdout: "out", stderr: "err")
        runner.failure = signal
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ProcessSignalError, signal)
        }
    }

    // Any other error means that the converter never ran: for example, the
    // program could not start. A file at the name is then not this run's,
    // so the error passes on as it came, and no partial is reported.
    func testARunnerErrorThatIsNoSignalPassesOnAsItCameAndReportsNoPartialDNG() {
        converterWritesItsFile(bytes: 10)
        runner.failure = NamedError(text: "The program could not start.")
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertNil($0 as? ConvertError, "not a conversion that failed: \($0)")
            XCTAssertEqual(($0 as? NamedError)?.text, "The program could not start.")
        }
    }

    func testThrowsWhenExitIsZeroButNoDNGExists() {
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("Adobe DNG Converter made no DNG. It may not support this file."))
        }
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(steps.renames, [], "with no work file there is nothing to rename")
        // Before the start: the name, the leftover of exiftool beside it,
        // and the two leftovers of this app. After the converter: the work
        // file again.
        XCTAssertEqual(disk.checked, [
            dngPath, "/tmp/Shoot 1/DSC05680.dng_exiftool_tmp",
            workPath, "/tmp/Shoot 1/.DSC05680.desqueeze-work.dng_exiftool_tmp", workPath,
        ])
    }

    // A DNG with no bytes is not a DNG. The converter made it, so it is partial.
    func testExitZeroWithAnEmptyWorkFileFailsAndReportsTheWorkFile() {
        converterWritesItsFile(bytes: 0)
        assertFails(.failed("Adobe DNG Converter made an empty DNG.", partial: work))
        XCTAssertEqual(steps.renames, [])
    }

    // The size could not be read: the file may be gone again. That is not
    // "0 bytes", so nothing here says that the file is this run's.
    func testExitZeroWithAWorkFileOfUnknownSizeMadeNoDNGAndReportsNoPartialDNG() {
        converterWritesItsFile()
        disk.unreadableSizes = [workPath]
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("Adobe DNG Converter made no DNG. It may not support this file.", partial: nil))
        }
    }

    // MARK: The real disk

    /// A converter on the real disk, with a runner that starts nothing, the
    /// rename of the system, and no leftover to discard.
    func converterOnTheRealDisk() -> AdobeConverter {
        AdobeConverter(executable: executable, runner: runner,
                       discardLeftover: { XCTFail("no leftover was expected: \($0.lastPathComponent)") })
    }

    /// The runner writes `bytes` where the arguments of Adobe DNG Converter
    /// say, on the real disk.
    func converterWritesARealFile(_ bytes: Data, also other: (() -> Void)? = nil) {
        runner.handler = { call in
            FileManager.default.createFile(atPath: FakeAdobe.output(of: call.arguments), contents: bytes)
            other?()
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
    }

    func testTheDefaultSizeReaderReadsARealFile() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let file = folder.appendingPathComponent("a.dng")
        try Data("nine byte".utf8).write(to: file)
        XCTAssertEqual(ConverterOutput.size(atPath: file.path), 9)

        try Data().write(to: file)
        XCTAssertEqual(ConverterOutput.size(atPath: file.path), 0, "an empty file has a size, and it is 0")
        XCTAssertNil(ConverterOutput.size(atPath: folder.appendingPathComponent("no such.dng").path))
    }

    // A converter on the real disk takes a real work file of some bytes as
    // a DNG, and the real rename gives it its name. No hidden file is left.
    func testAConverterOnTheRealDiskGivesTheWorkFileTheNameOfTheDNG() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let dng = folder.appendingPathComponent("a.dng")
        converterWritesARealFile(Data("a DNG".utf8))
        XCTAssertEqual(try converterOnTheRealDisk().convert(folder.appendingPathComponent("a.ARW")),
                       Conversion(dng: dng, unmatched: nil), "Adobe's own DNG is never unmatched")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["a.dng"],
                       "the listing has hidden files too: no work file is left")
        XCTAssertEqual(try Data(contentsOf: dng), Data("a DNG".utf8))
    }

    // The rename that a converter gets when no one gives it one must be the
    // exclusive one. Here no `rename:` is given, the files are real, and the
    // "Adobe DNG Converter" of the runner also makes `<base>.dng`, as another
    // program would at the wrong moment. A plain `rename` would put the work
    // file over that DNG.
    func testTheDefaultRenameNeverReplacesADNGThatAppearedWhileTheConverterWorked() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let dng = folder.appendingPathComponent("frame 1.dng")
        let work = folder.appendingPathComponent(".frame 1.desqueeze-work.dng")
        let others = Data("another program's DNG".utf8)
        converterWritesARealFile(Data("Adobe's DNG".utf8),
                                 also: { FileManager.default.createFile(atPath: dng.path, contents: others) })

        XCTAssertThrowsError(try converterOnTheRealDisk().convert(folder.appendingPathComponent("frame 1.ARW"))) {
            XCTAssertEqual($0 as? ConvertError,
                           .failedForAll("A DNG with this name exists already. Not converted.", partial: work))
        }

        XCTAssertEqual(try Data(contentsOf: dng), others, "the DNG of the other program has the same bytes")
        XCTAssertEqual(try Data(contentsOf: work), Data("Adobe's DNG".utf8), "the work file stays, for the job")
    }

    // Anything at the name stops the converter: a file, a folder, a link, and
    // a link that points at nothing. `fileExists` follows a link, so it says
    // that a dangling link is not there.
    func testAnythingAtTheNameStopsTheConverterBeforeItStarts() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let files = FileManager.default
        let target = folder.appendingPathComponent("elsewhere.bin")
        try Data("x".utf8).write(to: target)

        let plant: [(String, (URL) throws -> Void)] = [
            ("a file", { try Data("x".utf8).write(to: $0) }),
            ("an empty file", { try Data().write(to: $0) }),
            ("a folder", { try files.createDirectory(at: $0, withIntermediateDirectories: false) }),
            ("a link to a file", { try files.createSymbolicLink(at: $0, withDestinationURL: target) }),
            ("a link to a folder", { try files.createSymbolicLink(at: $0, withDestinationURL: folder) }),
            ("a dangling link", {
                try files.createSymbolicLink(atPath: $0.path, withDestinationPath: folder.path + "/no such file")
            }),
        ]
        for (number, (what, make)) in plant.enumerated() {
            let arw = folder.appendingPathComponent("frame \(number).ARW")
            let dng = folder.appendingPathComponent("frame \(number).dng")
            try make(dng)
            XCTAssertThrowsError(try converterOnTheRealDisk().convert(arw), what) {
                XCTAssertEqual($0 as? ConvertError,
                               .failed("A DNG with this name exists already. Not converted.", partial: nil), what)
            }
        }
        XCTAssertEqual(runner.calls, [], "the converter never started")
    }

    // The DNG that stopped it is not ours, so it is never reported as partial.
    func testRefusesToStartWhenTheDNGExistsAlready() {
        disk.paths = [dngPath]
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("A DNG with this name exists already. Not converted.", partial: nil))
        }
        XCTAssertEqual(runner.calls, [])
    }

    // MARK: A file name that is too long (design 13.9)

    /// The sentence of design 13.9. Held here, so a change of the core's
    /// constant fails the tests.
    static let nameTooLong = "The file name is too long. Shorten it, then run again."

    func arw(base: String) -> URL { URL(fileURLWithPath: "/tmp/Shoot 1/\(base).ARW") }

    // A file name can have 255 UTF-16 units, and the longest name that the
    // app makes for an ARW is exiftool's temporary file beside the work
    // file: the base name and 33 more units. A base of 240 is too long.
    func testAnARWWhoseNameIsTooLongStartsNoConverterAndTouchesNothing() {
        converterWritesItsFile()
        let long = arw(base: String(repeating: "n", count: 240))
        XCTAssertThrowsError(try converter().convert(long)) {
            XCTAssertEqual($0 as? ConvertError, .failedForAll(Self.nameTooLong),
                           "it holds for every converter, and no file is reported as partial")
        }
        XCTAssertEqual(runner.calls, [], "the converter must not start")
        XCTAssertEqual(disk.checked, [], "no question to the disk about a name that cannot be there")
        XCTAssertEqual(steps.discarded, [])
        XCTAssertEqual(steps.renames, [])
        XCTAssertEqual(disk.paths, [])
    }

    /// The longest name that the app makes for an ARW with this base name,
    /// spelled here and not taken from the core: exiftool's temporary file
    /// beside the hidden work file.
    func longestName(base: String) -> String { ".\(base).desqueeze-work.dng_exiftool_tmp" }

    /// Converts an ARW with this base name, and says whether the converter
    /// started. A refusal must be the sentence of the long name.
    func converts(base: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        runner.calls = []
        disk.paths = []
        do {
            let dng = try converter().convert(arw(base: base)).dng
            XCTAssertEqual(dng, ConverterOutput.url(for: arw(base: base)), file: file, line: line)
            XCTAssertEqual(runner.calls.count, 1, file: file, line: line)
            return true
        } catch {
            XCTAssertEqual(error as? ConvertError, .failedForAll(Self.nameTooLong), file: file, line: line)
            XCTAssertEqual(runner.calls, [], "the converter must not start", file: file, line: line)
            return false
        }
    }

    // The boundary (design 13.9). A base of 222 letters gives exiftool's
    // temporary file a name of 255 units, and 223 gives 256. Until
    // 2026-10-10 the rule counted the work file alone, so a base of 223 to
    // 235 letters started the converter and then failed in exiftool.
    func testTheLongestBaseNameThatConvertsHas222Letters() {
        converterWritesItsFile()
        let longest = String(repeating: "n", count: 222)
        XCTAssertEqual(longestName(base: longest).utf16.count, 255)
        XCTAssertTrue(converts(base: longest))
        XCTAssertFalse(converts(base: longest + "n"), "223 letters: exiftool's temporary file would have 256 units")
        XCTAssertFalse(converts(base: String(repeating: "n", count: 235)),
                       "the work file alone fits, and exiftool's temporary file does not")
    }

    // The file system counts UTF-16 units, not bytes of UTF-8. A name of
    // 222 "あ" has 666 bytes, and it is one unit for each letter: it
    // converts. Measured 2026-10-10 on APFS, HFS+ and ExFAT.
    func testTheLengthOfANameIsCountedInUTF16UnitsAndNotInBytes() {
        converterWritesItsFile()
        let longest = String(repeating: "\u{3042}", count: 222)
        XCTAssertEqual(longestName(base: longest).utf16.count, 255)
        XCTAssertEqual(longestName(base: longest).utf8.count, 699)
        XCTAssertTrue(converts(base: longest), "699 bytes, and 255 units")
        XCTAssertFalse(converts(base: longest + "\u{3042}"))
    }

    // HFS+ stores an accented letter as its two parts, so the name is
    // counted in its decomposed form. "é" is one unit as typed, and two
    // units on the disk: 111 of them are 222 units, and 112 are 224.
    func testTheLengthOfANameIsCountedInItsDecomposedForm() {
        converterWritesItsFile()
        let longest = String(repeating: "\u{E9}", count: 111)
        XCTAssertEqual(longest.utf16.count, 111, "one unit for each letter, as typed")
        XCTAssertEqual(longestName(base: longest).decomposedStringWithCanonicalMapping.utf16.count, 255)
        XCTAssertTrue(converts(base: longest))
        let tooLong = longest + "\u{E9}"
        XCTAssertEqual(longestName(base: tooLong).utf16.count, 145, "far under the limit, counted as typed")
        XCTAssertFalse(converts(base: tooLong), "112 letters are 224 units on the disk")
        // The same letters, typed in the decomposed form already.
        XCTAssertTrue(converts(base: String(repeating: "e\u{301}", count: 111)))
        XCTAssertFalse(converts(base: String(repeating: "e\u{301}", count: 112)))
    }

    // MARK: A leftover file of exiftool (design 13.3)

    // exiftool that ended hard in the tag step left
    // `<base>.dng_exiftool_tmp`. It refuses every later write beside it, so
    // the tag step could never pass. The ARW is not converted, by no
    // converter, and the sentence names the file. The file is not this
    // app's to remove: nothing is discarded, also not a leftover work file.
    func testALeftoverFileOfExiftoolBesideTheDNGsNameStopsTheConverterAndNothingIsDiscarded() {
        let leftover = "/tmp/Shoot 1/DSC05680.dng_exiftool_tmp"
        disk.paths = [leftover, workPath, workTmpPath]
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failedForAll(
                "A leftover file, DSC05680.dng_exiftool_tmp, is beside this photo. Delete it, then run again.",
                partial: nil))
        }
        XCTAssertEqual(runner.calls, [], "the converter never started")
        XCTAssertEqual(steps.discarded, [])
        XCTAssertEqual(disk.paths, [leftover, workPath, workTmpPath])
    }

    // A file with another name is no leftover of this ARW.
    func testALeftoverOfAnotherPhotoDoesNotStopTheConverter() throws {
        converterWritesItsFile()
        disk.paths = ["/tmp/Shoot 1/DSC05681.dng_exiftool_tmp", "/tmp/Shoot 1/DSC05680.ARW_exiftool_tmp",
                      "/tmp/Shoot 2/DSC05680.dng_exiftool_tmp"]
        XCTAssertEqual(try converter().convert(arw).dng.path, dngPath)
    }

    func testOnTheRealDiskALeftoverFileOfExiftoolStopsTheConverter() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let leftover = folder.appendingPathComponent("frame 1.dng_exiftool_tmp")
        try Data("half a write".utf8).write(to: leftover)
        XCTAssertThrowsError(try converterOnTheRealDisk().convert(folder.appendingPathComponent("frame 1.ARW"))) {
            XCTAssertEqual($0 as? ConvertError, .failedForAll(
                "A leftover file, frame 1.dng_exiftool_tmp, is beside this photo. Delete it, then run again."))
        }
        XCTAssertEqual(runner.calls, [])
        XCTAssertEqual(try Data(contentsOf: leftover), Data("half a write".utf8))
    }

    func testRefusesToStartWhenAnEmptyDNGExistsAlreadyAndDoesNotCallItPartial() {
        disk.paths = [dngPath]
        disk.sizes[dngPath] = 0
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("A DNG with this name exists already. Not converted.", partial: nil))
        }
        XCTAssertEqual(runner.calls, [])
    }

    // The check of the DNG's name comes before step 1: with a DNG at the
    // name, nothing is discarded, and nothing starts.
    func testTheCheckOfTheNameComesBeforeTheLeftoverIsDiscarded() {
        disk.paths = [dngPath, workPath]
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("A DNG with this name exists already. Not converted.", partial: nil))
        }
        XCTAssertEqual(steps.discarded, [])
        XCTAssertEqual(runner.calls, [])
        XCTAssertEqual(disk.paths, [dngPath, workPath])
    }

    // MARK: A leftover work file (design 13.3, step 1)

    // A run that ended hard left the work file: its own, or dnglab's. Its
    // name says that it is this app's own, so it is discarded, and the
    // conversion goes on. The real converter would write beside it, as
    // `.DSC05680.desqueeze-work_1.dng`.
    func testALeftoverWorkFileIsDiscardedBeforeTheConverterStarts() throws {
        converterWritesItsFile()
        disk.paths = [workPath]
        disk.sizes[workPath] = 4
        let conversion = try converter().convert(arw)
        XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: nil))
        XCTAssertEqual(steps.discarded, [workPath], "the discard gets the work file, and only it")
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(disk.paths, [dngPath])
    }

    // The Trash refused the leftover. The converter does not start, and the
    // sentence names the file to delete. No partial: this conversion made
    // no file.
    func testALeftoverThatCannotBeDiscardedStopsTheConversionBeforeTheConverterStarts() {
        disk.paths = [workPath]
        steps.discardError = NamedError(text: "The Trash refused it.")
        assertFails(.failedForAll(
            "A leftover file, .DSC05680.desqueeze-work.dng, is beside this photo. \(hiddenFileSentence) "
                + "Delete it, then run again.",
            partial: nil))
        XCTAssertEqual(steps.discarded, [workPath])
        XCTAssertEqual(runner.calls, [], "the converter did not start")
        XCTAssertEqual(disk.paths, [workPath], "the leftover is where it was")
    }

    // exiftool that ended hard in dnglab's match left
    // `<work file>_exiftool_tmp`. Both names are this app's own, so step 1
    // discards both, the work file first, and the conversion goes on. Before,
    // that file stopped the ARW on every run, with a note about a file that
    // Finder does not show.
    func testTheLeftoverOfExiftoolBesideTheWorkFileIsDiscardedWithTheWorkFile() throws {
        for leftovers in [[workTmpPath], [workPath, workTmpPath]] {
            setUp()
            converterWritesItsFile()
            disk.paths = Set(leftovers)
            let conversion = try converter().convert(arw)
            XCTAssertEqual(conversion, Conversion(dng: dng, unmatched: nil), "\(leftovers)")
            XCTAssertEqual(steps.discarded, leftovers, "the discard gets the two names of this app, and no other")
            XCTAssertEqual(runner.calls.count, 1, "\(leftovers)")
            XCTAssertEqual(disk.paths, [dngPath], "\(leftovers)")
        }
    }

    // The Trash refused the leftover of exiftool. The converter does not
    // start, and the sentence names that file.
    func testALeftoverOfExiftoolBesideTheWorkFileThatCannotBeDiscardedStopsTheConversion() {
        disk.paths = [workTmpPath]
        steps.discardError = NamedError(text: "The Trash refused it.")
        assertFails(.failedForAll(
            "A leftover file, .DSC05680.desqueeze-work.dng_exiftool_tmp, is beside this photo. \(hiddenFileSentence) "
                + "Delete it, then run again.",
            partial: nil))
        XCTAssertEqual(steps.discarded, [workTmpPath])
        XCTAssertEqual(runner.calls, [], "the converter did not start")
        XCTAssertEqual(disk.paths, [workTmpPath], "the leftover is where it was")
    }

    // MARK: Step 1 removes only a regular file (design 13.3)

    // A folder or a link has the name of the work file, or of exiftool's
    // leftover beside it. That is no leftover of a run: the app does not
    // send it to the Trash. The ARW stops with the leftover note, the
    // converter does not start, and nothing moves: also not the regular file
    // at the other name.
    func testAThingThatIsNoRegularFileAtALeftoverNameStopsTheConversionAndNothingMoves() {
        let names = [workPath: ".DSC05680.desqueeze-work.dng", workTmpPath: ".DSC05680.desqueeze-work.dng_exiftool_tmp"]
        for (notAFile, both) in [(workPath, false), (workTmpPath, false), (workPath, true), (workTmpPath, true)] {
            setUp()
            converterWritesItsFile()
            disk.paths = both ? [workPath, workTmpPath] : [notAFile]
            disk.notRegularFiles = [notAFile]
            assertFails(.failedForAll(
                "A leftover file, \(names[notAFile]!), is beside this photo. \(hiddenFileSentence) "
                    + "Delete it, then run again.",
                partial: nil), notAFile)
            XCTAssertEqual(steps.discarded, [], "\(notAFile), both \(both): nothing moves")
            XCTAssertEqual(runner.calls, [], "\(notAFile): the converter did not start")
            XCTAssertEqual(disk.paths, both ? [workPath, workTmpPath] : [notAFile])
        }
    }

    /// The things that are no regular file, each planted at one name.
    static func thingsThatAreNoRegularFile(in folder: URL) throws -> [(String, (URL) throws -> Void)] {
        let files = FileManager.default
        let target = folder.appendingPathComponent("a file of the person.bin")
        try Data("a file of the person".utf8).write(to: target)
        return [
            ("a folder with a file in it", {
                try files.createDirectory(at: $0, withIntermediateDirectories: false)
                try Data("inside".utf8).write(to: $0.appendingPathComponent("inside.txt"))
            }),
            ("a link to a file", { try files.createSymbolicLink(at: $0, withDestinationURL: target) }),
            ("a link to a folder", { try files.createSymbolicLink(at: $0, withDestinationURL: folder) }),
            ("a dangling link", {
                try files.createSymbolicLink(atPath: $0.path, withDestinationPath: folder.path + "/no such file")
            }),
        ]
    }

    func testOnlyARegularFileIsARegularFileOnTheRealDisk() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let file = folder.appendingPathComponent("a.dng")
        try Data().write(to: file)
        XCTAssertTrue(ConverterOutput.isRegularFile(atPath: file.path), "an empty file is a regular file")
        XCTAssertFalse(ConverterOutput.isRegularFile(atPath: folder.appendingPathComponent("no such file").path))
        for (number, (what, make)) in try Self.thingsThatAreNoRegularFile(in: folder).enumerated() {
            let thing = folder.appendingPathComponent("thing \(number)")
            try make(thing)
            XCTAssertFalse(ConverterOutput.isRegularFile(atPath: thing.path), what)
            XCTAssertTrue(ConverterOutput.exists(atPath: thing.path), what)
        }
    }

    // The same on the real disk, with the questions that the app asks: a
    // folder with a file in it, a link to a file, a link to a folder, and a
    // link that points at nothing, each at the name of the work file and at
    // the name of exiftool's leftover beside it.
    func testOnTheRealDiskAFolderOrALinkAtALeftoverNameStopsTheConversionAndStaysAsItWas() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let files = FileManager.default
        let asked = CallLog()
        let converter = AdobeConverter(executable: executable, runner: runner,
                                       discardLeftover: { asked.entries.append($0.lastPathComponent) })
        var number = 0
        for (what, make) in try Self.thingsThatAreNoRegularFile(in: folder) {
            for suffix in ["", "_exiftool_tmp"] {
                number += 1
                let arw = folder.appendingPathComponent("frame \(number).ARW")
                let name = ".frame \(number).desqueeze-work.dng\(suffix)"
                let thing = folder.appendingPathComponent(name)
                try make(thing)
                let before = try files.attributesOfItem(atPath: thing.path)

                XCTAssertThrowsError(try converter.convert(arw), "\(what) at \(name)") {
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
        XCTAssertEqual(runner.calls, [], "the converter never started")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("a file of the person.bin")),
                       Data("a file of the person".utf8))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(".frame 1.desqueeze-work.dng/inside.txt")),
                       Data("inside".utf8), "the file in the folder is where it was")
    }

    // MARK: The rename (design 13.3, step 5)

    // Another program made `<base>.dng` after the check before the start,
    // while the converter worked. That file is not this run's: it is not
    // reported, and nothing replaces it. The work file is the partial
    // output, and the error holds for every converter.
    func testARenameThatFindsTheNameTakenReportsTheWorkFileAndNeverTheDNGOfTheOtherProgram() {
        let (disk, dngPath) = (disk!, dngPath)
        steps.renameOutcome = .nameTaken
        runner.handler = { call in
            let output = FakeAdobe.output(of: call.arguments)
            disk.paths.formUnion([output, dngPath])
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failedForAll("A DNG with this name exists already. Not converted.", partial: work))
        }
        XCTAssertEqual(steps.renames, [[workPath, dngPath]])
        XCTAssertEqual(disk.paths, [dngPath, workPath], "both files are where they were")
    }

    func testARenameThatFailsForAnotherReasonReportsTheWorkFileWithTheSystemsWords() {
        converterWritesItsFile()
        steps.renameOutcome = .failed(EACCES)
        assertFails(.failed("The DNG could not get the name DSC05680.dng: Permission denied.", partial: work))
        XCTAssertEqual(disk.paths, [workPath])
    }

    // The work file vanished before the rename: the system says "No such
    // file". The result reports no partial output, so the job sends nothing
    // to the Trash, and no note names a file that is not there.
    func testARenameThatFailsBecauseTheWorkFileIsGoneReportsNoPartial() {
        converterWritesItsFile()
        steps.renameOutcome = .failed(ENOENT)
        steps.workFileIsGoneAtTheRename = true
        assertFails(.failed("The DNG could not get the name DSC05680.dng: No such file or directory.", partial: nil))
        XCTAssertEqual(steps.renames, [[workPath, dngPath]])
        XCTAssertEqual(disk.paths, [])
    }

    func testANameTakenWithAWorkFileThatIsGoneReportsNoPartial() {
        converterWritesItsFile()
        steps.renameOutcome = .nameTaken
        steps.workFileIsGoneAtTheRename = true
        assertFails(.failedForAll("A DNG with this name exists already. Not converted.", partial: nil))
    }
}

/// Answers "does this file exist" from a set, and records each question.
final class FakeDisk: @unchecked Sendable {
    var paths: Set<String> = []
    /// The size of a file. A file in `paths` with no entry here has bytes.
    var sizes: [String: Int] = [:]
    var checked: [String] = []

    /// Files that are there, and whose size cannot be read.
    var unreadableSizes: Set<String> = []

    func size(_ path: String) -> Int? {
        guard paths.contains(path), !unreadableSizes.contains(path) else { return nil }
        return sizes[path, default: 1_000]
    }

    func exists(_ path: String) -> Bool {
        checked.append(path)
        return paths.contains(path)
    }

    /// Things that are there, and that are no regular file: a folder, or a
    /// symbolic link.
    var notRegularFiles: Set<String> = []

    func isRegularFile(_ path: String) -> Bool {
        paths.contains(path) && !notRegularFiles.contains(path)
    }

    /// A rename: the file has the new name, with its size.
    func move(_ path: String, to name: String) {
        paths.remove(path)
        paths.insert(name)
        sizes[name] = sizes.removeValue(forKey: path)
    }
}
