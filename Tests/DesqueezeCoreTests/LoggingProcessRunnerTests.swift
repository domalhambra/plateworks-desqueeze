import XCTest
@testable import DesqueezeCore

final class LoggingProcessRunnerTests: XCTestCase {
    let tool = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool")
    var inner: FakeRunner!
    var lines: LineBox!
    var runner: LoggingProcessRunner!

    final class LineBox: @unchecked Sendable {
        var lines: [String] = []
    }

    struct StartError: LocalizedError {
        var errorDescription: String? { "The file does not exist." }
    }

    final class ThrowingRunner: ProcessRunner {
        func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult { throw StartError() }
    }

    override func setUp() {
        inner = FakeRunner()
        lines = LineBox()
        let box = lines!
        runner = LoggingProcessRunner(wrapping: inner) { box.lines.append($0) }
    }

    func testTheCallGoesToTheWrappedRunnerAndItsResultComesBack() throws {
        let result = ProcessResult(exitCode: 3, stdout: "out\n", stderr: "err\n")
        inner.handler = { _ in result }
        XCTAssertEqual(try runner.run(tool, ["-m", "/tmp/Shoot 1/a.dng"]), result)
        XCTAssertEqual(inner.calls, [FakeRunner.Call(executable: tool.path, arguments: ["-m", "/tmp/Shoot 1/a.dng"])])
    }

    func testTheSinkGetsTheCommandLineTheExitCodeAndBothOutputs() throws {
        inner.handler = { _ in
            ProcessResult(exitCode: 1, stdout: "    0 image files updated\n    1 files weren't updated due to errors\n",
                          stderr: "Error: Not a valid TIFF - /tmp/Shoot 1/junk.dng\n")
        }
        _ = try runner.run(tool, ["-m", "-SubIFD:DefaultScale=1.5 1", "/tmp/Shoot 1/junk.dng"])
        XCTAssertEqual(lines.lines, [
            "$ /opt/homebrew/bin/exiftool -m '-SubIFD:DefaultScale=1.5 1' '/tmp/Shoot 1/junk.dng'",
            "  exit 1",
            "  stdout:     0 image files updated",
            "  stdout:     1 files weren't updated due to errors",
            "  stderr: Error: Not a valid TIFF - /tmp/Shoot 1/junk.dng",
        ])
    }

    func testACommandWithNoOutputLogsOnlyItsLineAndItsExitCode() throws {
        _ = try runner.run(tool, ["-ver"])
        XCTAssertEqual(lines.lines, ["$ /opt/homebrew/bin/exiftool -ver", "  exit 0"])
    }

    // The command line is on the sink before the program starts, so a program
    // that never returns is still named.
    func testTheCommandLineIsLoggedBeforeTheProgramRuns() throws {
        let box = lines!
        var seenAtStart: [String] = []
        inner.handler = { _ in
            seenAtStart = box.lines
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        _ = try runner.run(tool, ["-ver"])
        XCTAssertEqual(seenAtStart, ["$ /opt/homebrew/bin/exiftool -ver"])
    }

    func testAProgramThatDoesNotStartIsLoggedAndTheErrorGoesOn() {
        let box = lines!
        let failing = LoggingProcessRunner(wrapping: ThrowingRunner()) { box.lines.append($0) }
        XCTAssertThrowsError(try failing.run(URL(fileURLWithPath: "/no/such tool"), ["a b"])) {
            XCTAssertTrue($0 is StartError)
        }
        XCTAssertEqual(lines.lines, ["$ '/no/such tool' 'a b'", "  did not start: The file does not exist."])
    }

    // The program started, so "did not start" would be wrong. The output it
    // wrote before the signal is still worth reading.
    func testAProgramThatASignalEndedIsLoggedWithTheSignalAndItsOutput() {
        final class Ended: ProcessRunner {
            func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
                throw ProcessSignalError(signal: 9, stdout: "half\n", stderr: "")
            }
        }
        let box = lines!
        let ended = LoggingProcessRunner(wrapping: Ended()) { box.lines.append($0) }
        XCTAssertThrowsError(try ended.run(tool, ["-ver"])) {
            XCTAssertEqual($0 as? ProcessSignalError, ProcessSignalError(signal: 9, stdout: "half\n", stderr: ""))
        }
        XCTAssertEqual(lines.lines, ["$ /opt/homebrew/bin/exiftool -ver", "  ended by signal 9", "  stdout: half"])
    }

    // Each argument reads back as one argument: a reader, or a shell, cannot
    // split it at a space.
    func testAnArgumentIsQuotedOnlyWhenItNeedsIt() {
        XCTAssertEqual(LoggingProcessRunner.quoted("-SubIFD:DefaultScale"), "-SubIFD:DefaultScale")
        XCTAssertEqual(LoggingProcessRunner.quoted("/opt/homebrew/bin/exiftool"), "/opt/homebrew/bin/exiftool")
        XCTAssertEqual(LoggingProcessRunner.quoted("ImageHashType=SHA256"), "ImageHashType=SHA256")
        XCTAssertEqual(LoggingProcessRunner.quoted("/tmp/Shoot 1/a.dng"), "'/tmp/Shoot 1/a.dng'")
        XCTAssertEqual(LoggingProcessRunner.quoted("-SubIFD:DefaultScale=1.5 1"), "'-SubIFD:DefaultScale=1.5 1'")
        XCTAssertEqual(LoggingProcessRunner.quoted(""), "''")
        XCTAssertEqual(LoggingProcessRunner.quoted("Dom's shoot"), #"'Dom'\''s shoot'"#)
        XCTAssertEqual(LoggingProcessRunner.quoted("a\tb"), "'a\tb'")
        XCTAssertEqual(LoggingProcessRunner.quoted("$HOME"), "'$HOME'")
        XCTAssertEqual(LoggingProcessRunner.quoted("été.dng"), "'été.dng'")
    }

    // /bin/sh splits the logged line back into the arguments that were sent.
    func testTheLoggedLineSplitsBackIntoTheSameArguments() throws {
        let arguments = ["-m", "-SubIFD:DefaultScale=1.5 1", "/tmp/Shoot 1/Dom's \"best\" $HOME.dng", "", "a  b"]
        let line = arguments.map(LoggingProcessRunner.quoted).joined(separator: " ")
        let result = try SystemProcessRunner().run(
            URL(fileURLWithPath: "/bin/sh"), ["-c", "for a in \(line); do printf '%s\\n' \"$a\"; done"])
        XCTAssertEqual(result.stdout.components(separatedBy: "\n").dropLast(), arguments[...])
    }
}
