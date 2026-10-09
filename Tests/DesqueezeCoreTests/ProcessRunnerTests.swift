import XCTest
@testable import DesqueezeCore

final class ProcessRunnerTests: XCTestCase {
    let runner = SystemProcessRunner()
    let shell = URL(fileURLWithPath: "/bin/sh")

    func testCapturesStandardOutputAndExitZero() throws {
        let result = try runner.run(shell, ["-c", "echo hello"])
        XCTAssertEqual(result, ProcessResult(exitCode: 0, stdout: "hello\n", stderr: ""))
    }

    func testCapturesStandardErrorAndTheExitCode() throws {
        let result = try runner.run(shell, ["-c", "echo bad 1>&2; exit 3"])
        XCTAssertEqual(result, ProcessResult(exitCode: 3, stdout: "", stderr: "bad\n"))
    }

    func testArgumentsReachTheProgramWithoutAShell() throws {
        let result = try runner.run(URL(fileURLWithPath: "/bin/echo"), ["a b", "$HOME", "*"])
        XCTAssertEqual(result.stdout, "a b $HOME *\n")
    }

    func testLargeOutputOnBothStreamsDoesNotHang() throws {
        let script = "head -c 200000 /dev/zero | tr '\\0' 'e' 1>&2; head -c 200000 /dev/zero | tr '\\0' 'o'"
        let result = try runner.run(shell, ["-c", script])
        XCTAssertEqual(result.stdout.count, 200_000)
        XCTAssertEqual(result.stderr.count, 200_000)
    }

    // A program that a signal ended has no exit code of its own. The status
    // that `Process` gives for it is the signal number, and a caller that
    // read it as an exit code would say "returned 15".
    func testAProgramThatASignalEndedIsAnErrorThatNamesTheSignal() throws {
        XCTAssertThrowsError(try runner.run(shell, ["-c", "echo partial; echo noise 1>&2; kill -TERM $$"])) { error in
            guard let ended = error as? ProcessSignalError else { return XCTFail("\(error)") }
            XCTAssertEqual(ended.signal, SIGTERM)
            XCTAssertEqual(ended.stdout, "partial\n")
            XCTAssertEqual(ended.stderr, "noise\n")
            XCTAssertEqual(ended.localizedDescription, "The program was ended by signal 15.")
        }
    }

    func testAProgramThatExitsWithTheNumberOfASignalIsStillAnExitCode() throws {
        let result = try runner.run(shell, ["-c", "exit 15"])
        XCTAssertEqual(result, ProcessResult(exitCode: 15, stdout: "", stderr: ""))
    }

    func testAMissingExecutableThrows() {
        XCTAssertThrowsError(try runner.run(URL(fileURLWithPath: "/nonexistent/exiftool"), []))
    }

    // One run makes two or three calls for each photo. Foundation autoreleases
    // the pipe handles, so without a pool inside `run` a 700-photo folder
    // passes the descriptor limit and every later call fails.
    func testRepeatedCallsDoNotHoldFileDescriptors() throws {
        func openDescriptors() throws -> Int {
            try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
        }
        _ = try runner.run(shell, ["-c", "true"])
        let before = try openDescriptors()
        for _ in 0..<20 { _ = try runner.run(shell, ["-c", "true"]) }
        for _ in 0..<20 { _ = try? runner.run(URL(fileURLWithPath: "/nonexistent/tool"), []) }
        XCTAssertLessThanOrEqual(try openDescriptors(), before + 4)
    }

    // A terminal sends Control-C to every process of the foreground group.
    // The command line tool stops a run after its current file, and that
    // needs exiftool and the converter to be out of the tool's group. An
    // exiftool that stops between its two renames leaves an orphan backup.
    func testAProgramStartsInAProcessGroupOfItsOwn() throws {
        let result = try runner.run(shell, ["-c", "ps -o pgid= -p $$"])
        let childGroup = try XCTUnwrap(Int32(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertNotEqual(childGroup, getpgrp(), "the child must not be in the group of this process")
    }
}
