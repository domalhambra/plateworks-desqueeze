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
        return AdobeConverter(executable: executable, runner: runner, fileExists: { disk.exists($0) })
    }

    /// The converter writes the DNG while it runs.
    func converterWritesTheDNG(exitCode: Int32 = 0) {
        let disk = self.disk!
        let dngPath = self.dngPath
        runner.handler = { _ in
            disk.paths.insert(dngPath)
            return ProcessResult(exitCode: exitCode, stdout: "", stderr: "")
        }
    }

    func testPassesTheExactArgumentsAndReturnsTheDNG() throws {
        converterWritesTheDNG()
        let output = try converter().convert(arw)
        XCTAssertEqual(runner.calls, [FakeRunner.Call(executable: executable.path, arguments: [
            "-c", "-d", "/tmp/Shoot 1", "/tmp/Shoot 1/DSC05680.ARW",
        ])])
        XCTAssertEqual(output.path, dngPath)
    }

    func testThrowsWhenTheExitCodeIsNotZero() {
        converterWritesTheDNG(exitCode: 1)
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("Adobe DNG Converter returned 1."))
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

    // The real converter never overwrites: it would write DSC05680_1.dng.
    func testRefusesToStartWhenTheDNGExistsAlready() {
        disk.paths = [dngPath]
        XCTAssertThrowsError(try converter().convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("A DNG with this name exists already. Not converted."))
        }
        XCTAssertEqual(runner.calls, [])
    }
}

/// Answers "does this file exist" from a set, and records each question.
final class FakeDisk: @unchecked Sendable {
    var paths: Set<String> = []
    var checked: [String] = []

    func exists(_ path: String) -> Bool {
        checked.append(path)
        return paths.contains(path)
    }
}
