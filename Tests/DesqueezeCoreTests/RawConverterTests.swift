import XCTest
@testable import DesqueezeCore

final class RawConverterTests: XCTestCase {
    let executable = URL(fileURLWithPath: "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter")
    let arw = URL(fileURLWithPath: "/tmp/Shoot 1/DSC05680.ARW")
    let dngPath = "/tmp/Shoot 1/DSC05680.dng"
    var runner: FakeRunner!
    var disk: FakeDisk!

    override func setUp() {
        runner = FakeRunner()
        disk = FakeDisk()
    }

    func converter() -> AdobeConverter {
        let disk = self.disk!
        return AdobeConverter(executable: executable, runner: runner, fileExists: { disk.exists($0) },
                              fileSize: { disk.size($0) })
    }

    /// The converter writes the DNG while it runs. With `bytes` 0 the file
    /// is empty, as one that a signal cut short.
    func converterWritesTheDNG(exitCode: Int32 = 0, bytes: Int = 1_000) {
        let disk = self.disk!
        let dngPath = self.dngPath
        runner.handler = { _ in
            disk.paths.insert(dngPath)
            disk.sizes[dngPath] = bytes
            return ProcessResult(exitCode: exitCode, stdout: "", stderr: "")
        }
    }

    var dng: URL { URL(fileURLWithPath: dngPath) }

    func testPassesTheExactArgumentsAndReturnsTheDNG() throws {
        converterWritesTheDNG()
        let output = try converter().convert(arw).dng
        XCTAssertEqual(runner.calls, [FakeRunner.Call(executable: executable.path, arguments: [
            "-c", "-d", "/tmp/Shoot 1", "/tmp/Shoot 1/DSC05680.ARW",
        ])])
        XCTAssertEqual(output.path, dngPath)
    }

    // The converter that returns non-zero may have written part of the file.
    // That file is this run's, because the guard proved that none was there.
    func testANonZeroExitWithAFileReportsThePartialDNG() {
        converterWritesTheDNG(exitCode: 1)
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("Adobe DNG Converter returned 1.", partial: dng))
        }
    }

    func testANonZeroExitWithNoFileReportsNoPartialDNG() {
        runner.handler = { _ in ProcessResult(exitCode: 1, stdout: "", stderr: "") }
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("Adobe DNG Converter returned 1.", partial: nil))
        }
    }

    // A signal ends the converter before it finishes. The file it began is
    // in the folder, and may have no bytes (design 4.3, tested 2026-10-09).
    func testASignalWithAFileReportsThePartialDNGAndTheSignal() {
        converterWritesTheDNG(bytes: 0)
        runner.failure = ProcessSignalError(signal: 15, stdout: "", stderr: "")
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("The program was ended by signal 15.", partial: dng))
        }
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
        converterWritesTheDNG(bytes: 10)
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
        // Before the start: the name, and the two leftovers of exiftool.
        // After the converter: the name again.
        XCTAssertEqual(disk.checked, [
            dngPath, "/tmp/Shoot 1/DSC05680.dng_exiftool_tmp",
            "/tmp/Shoot 1/.DSC05680.desqueeze-work.dng_exiftool_tmp", dngPath,
        ])
    }

    // A DNG with no bytes is not a DNG. The converter made it, so it is partial.
    func testExitZeroWithAnEmptyDNGFailsAndReportsThePartialDNG() {
        converterWritesTheDNG(bytes: 0)
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("Adobe DNG Converter made an empty DNG.", partial: dng))
        }
    }

    // The size could not be read: the file may be gone again. That is not
    // "0 bytes", so nothing here says that the file is this run's.
    func testExitZeroWithADNGOfUnknownSizeMadeNoDNGAndReportsNoPartialDNG() {
        converterWritesTheDNG()
        disk.unreadableSizes = [dngPath]
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("Adobe DNG Converter made no DNG. It may not support this file.", partial: nil))
        }
    }

    // MARK: The real disk

    /// A converter on the real disk, with a runner that starts nothing.
    func converterOnTheRealDisk() -> AdobeConverter { AdobeConverter(executable: executable, runner: runner) }

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

    // A converter on the real disk takes a real DNG of some bytes as a DNG.
    func testAConverterOnTheRealDiskAcceptsADNGWithBytes() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let dng = folder.appendingPathComponent("a.dng")
        runner.handler = { _ in
            FileManager.default.createFile(atPath: dng.path, contents: Data("a DNG".utf8))
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        XCTAssertEqual(try converterOnTheRealDisk().convert(folder.appendingPathComponent("a.ARW")),
                       Conversion(dng: dng, unmatched: nil), "Adobe's own DNG is never unmatched")
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

    // The real converter never overwrites: it would write DSC05680_1.dng.
    // The DNG that stopped it is not ours, so it is never reported as partial.
    func testRefusesToStartWhenTheDNGExistsAlready() {
        disk.paths = [dngPath]
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("A DNG with this name exists already. Not converted.", partial: nil))
        }
        XCTAssertEqual(runner.calls, [])
    }

    // MARK: A leftover file of exiftool (design 13.3)

    // exiftool that ended hard left `<name>_exiftool_tmp`. It refuses every
    // later write beside it, so the tag step could never pass. The ARW is
    // not converted, by no converter, and the sentence names the file.
    func testALeftoverFileOfExiftoolStopsTheConverterBeforeItStartsAndIsNoPartial() {
        for leftover in ["DSC05680.dng_exiftool_tmp", ".DSC05680.desqueeze-work.dng_exiftool_tmp"] {
            setUp()
            disk.paths = ["/tmp/Shoot 1/" + leftover]
            XCTAssertThrowsError(try converter().convert(arw), leftover) {
                XCTAssertEqual($0 as? ConvertError, .failedForAll(
                    "A leftover file, \(leftover), is beside this photo."
                        + (leftover.hasPrefix(".") ? " \(hiddenFileSentence)" : "") + " Delete it, then run again.",
                    partial: nil))
            }
            XCTAssertEqual(runner.calls, [], "\(leftover): the converter never started")
        }
    }

    // A file with another name is no leftover of this ARW.
    func testALeftoverOfAnotherPhotoDoesNotStopTheConverter() throws {
        converterWritesTheDNG()
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

    /// A rename: the file has the new name, with its size.
    func move(_ path: String, to name: String) {
        paths.remove(path)
        paths.insert(name)
        sizes[name] = sizes.removeValue(forKey: path)
    }
}
