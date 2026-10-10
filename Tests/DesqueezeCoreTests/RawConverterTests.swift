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
        let output = try converter().convert(arw)
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

    func testARunnerErrorAfterTheStartWithAFileReportsThePartialDNG() {
        converterWritesTheDNG(bytes: 10)
        runner.failure = NamedError(text: "The program could not be read.")
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("The program could not be read.", partial: dng))
        }
    }

    func testThrowsWhenExitIsZeroButNoDNGExists() {
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("Adobe DNG Converter made no DNG. It may not support this file."))
        }
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(disk.checked, [dngPath, dngPath])
    }

    // A DNG with no bytes is not a DNG. The converter made it, so it is partial.
    func testExitZeroWithAnEmptyDNGFailsAndReportsThePartialDNG() {
        converterWritesTheDNG(bytes: 0)
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("Adobe DNG Converter made an empty DNG.", partial: dng))
        }
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

    func size(_ path: String) -> Int? {
        paths.contains(path) ? sizes[path, default: 1_000] : nil
    }

    func exists(_ path: String) -> Bool {
        checked.append(path)
        return paths.contains(path)
    }
}
