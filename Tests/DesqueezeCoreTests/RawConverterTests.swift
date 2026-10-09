import XCTest
@testable import DesqueezeCore

final class RawConverterTests: XCTestCase {
    let executable = URL(fileURLWithPath: "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter")
    let arw = URL(fileURLWithPath: "/tmp/Shoot 1/DSC05680.ARW")

    func testPassesTheExactArgumentsAndReturnsTheDNG() throws {
        let runner = FakeRunner()
        let converter = AdobeConverter(executable: executable, runner: runner, fileExists: { _ in true })
        let output = try converter.convert(arw)
        XCTAssertEqual(runner.calls, [FakeRunner.Call(executable: executable.path, arguments: [
            "-c", "-d", "/tmp/Shoot 1", "/tmp/Shoot 1/DSC05680.ARW",
        ])])
        XCTAssertEqual(output.path, "/tmp/Shoot 1/DSC05680.dng")
    }

    func testThrowsWhenTheExitCodeIsNotZero() {
        let runner = FakeRunner()
        runner.handler = { _ in ProcessResult(exitCode: 1, stdout: "", stderr: "") }
        let converter = AdobeConverter(executable: executable, runner: runner, fileExists: { _ in true })
        XCTAssertThrowsError(try converter.convert(arw)) {
            XCTAssertEqual($0 as? ConvertError, .failed("Adobe DNG Converter returned 1."))
        }
    }

    func testThrowsWhenExitIsZeroButNoDNGExists() {
        let checked = PathBox()
        let converter = AdobeConverter(executable: executable, runner: FakeRunner(), fileExists: {
            checked.path = $0
            return false
        })
        XCTAssertThrowsError(try converter.convert(arw)) {
            XCTAssertEqual($0 as? ConvertError,
                           .failed("Adobe DNG Converter made no DNG. It may not support this file."))
        }
        XCTAssertEqual(checked.path, "/tmp/Shoot 1/DSC05680.dng")
    }
}

private final class PathBox: @unchecked Sendable {
    var path: String?
}
