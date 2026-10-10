import DesqueezeCore
import XCTest

/// The server as a program: its two flags, and a wrong command line. None of
/// these starts a session.
///
/// A wrong value for the test variable is not tested here. No test starts a
/// server whose backups could go to the Trash, so that case is in
/// `StartupTests`, in the test process.
final class CommandLineTests: ServerTestCase {
    struct Output {
        let stdout: String
        let stderr: String
        let exitCode: Int32?
    }

    /// Starts the server with `arguments`, with its standard input left open,
    /// and waits for it to end by itself.
    func run(_ arguments: [String], environment: [String: String?] = [:]) throws -> Output {
        let server = try launch(arguments, environment: environment)
        let exitCode = server.waitForExit()
        XCTAssertTrue(server.waitForEndOfOutput(), "the program must end with no word from a client")
        // `tearDown` checks that every line of standard output is JSON-RPC.
        // These programs print text, so the server leaves the list here.
        servers.removeAll { $0 === server }
        server.stop()
        return Output(stdout: server.outputLines.map { $0 + "\n" }.joined() + server.unfinishedOutput,
                      stderr: server.errorText, exitCode: exitCode)
    }

    func testVersionPrintsOneLineAndStartsNoServer() throws {
        let output = try run(["--version"])

        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.stdout, "desqueeze-mcp \(DesqueezeVersion.current)\n")
        XCTAssertEqual(output.stderr, "")
    }

    func testHelpPrintsAShortUsageAndStartsNoServer() throws {
        for flag in ["--help", "-h"] {
            let output = try run([flag])

            XCTAssertEqual(output.exitCode, 0, flag)
            XCTAssertTrue(output.stdout.contains("Usage:"), output.stdout)
            for name in Self.toolNames + ["--version", "--help", "claude mcp add"] {
                XCTAssertTrue(output.stdout.contains(name), "\(flag): the help names \(name)")
            }
            XCTAssertLessThan(output.stdout.split(separator: "\n").count, 30, "a short usage")
            XCTAssertEqual(output.stderr, "", flag)
        }
    }

    func testAnythingElseOnTheCommandLineIsAUsageErrorOnStandardError() throws {
        for arguments in [["--verbose"], ["scan"], [folder.path], ["--version", "--help"], ["--help", "x"], [""]] {
            let output = try run(arguments)

            XCTAssertEqual(output.exitCode, 2, "\(arguments)")
            XCTAssertEqual(output.stdout, "", "\(arguments): nothing on standard output")
            XCTAssertTrue(output.stderr.hasPrefix("desqueeze-mcp: "), output.stderr)
            XCTAssertTrue(output.stderr.contains("Usage:"), output.stderr)
        }
    }
}
