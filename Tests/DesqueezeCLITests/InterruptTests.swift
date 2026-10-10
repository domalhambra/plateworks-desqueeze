import DesqueezeCore
import XCTest

/// A signal to the built tool, in the middle of a real run: Control-C, and
/// the `SIGHUP` of a Terminal window that closes.
final class InterruptTests: BuiltToolTestCase {
    static let fileCount = 8

    /// A terminal sends Control-C to the foreground process group. `Process`
    /// starts each child in a group of its own, so the group of the tool
    /// normally holds the tool and no exiftool. The signal goes to that group,
    /// as the terminal sends it. A program that is just starting can still
    /// get it, and the test below allows that one outcome.
    func interrupt(_ process: Process) {
        let id = process.processIdentifier
        XCTAssertEqual(getpgid(id), id, "the tool leads a process group of its own")
        XCTAssertEqual(kill(-id, SIGINT), 0)
    }

    func testControlCStopsAfterTheCurrentFilePrintsTheResultSoFarAndGivesOne() throws {
        try assertTheRunStopsAfterItsCurrentFile(allowedSignal: SIGINT) { interrupt($0) }
    }

    // A Terminal window that closes sends SIGHUP. With the system's action
    // the tool would end at once, in the middle of a file. The signal goes
    // to the tool alone, by the process id of the process that this test
    // started, so no exiftool gets it and no file may fail.
    func testAClosedTerminalWindowStopsTheRunAfterItsCurrentFile() throws {
        try assertTheRunStopsAfterItsCurrentFile(allowedSignal: nil) { process in
            XCTAssertTrue(process.isRunning)
            XCTAssertEqual(kill(process.processIdentifier, SIGHUP), 0)
        }
    }

    /// Starts a run on eight DNG files, sends the signal after the first
    /// file, and checks that the run stopped after its current file with
    /// every file whole.
    ///
    /// - Parameters:
    ///   - allowedSignal: the signal that one program in work may have got,
    ///     when the signal went to the tool's group. Nil when it went to the
    ///     tool alone: no file may fail then.
    ///   - send: sends the signal to the tool that this test started.
    func assertTheRunStopsAfterItsCurrentFile(allowedSignal: Int32?, send: (Process) -> Void) throws {
        for number in 1...Self.fileCount { try copyFixture("sample.dng", as: "photo \(number).dng") }

        let process = process(["run", folder.path, "--factor", "1.5", "--json"])
        var sawProgress = false
        let result = try finish(process) { standardError in
            // Wait for the first file to complete, so the run is in its loop.
            let limit = Date().addingTimeInterval(60)
            while !standardError().contains("1/\(Self.fileCount) "), process.isRunning, Date() < limit {
                usleep(2_000)
            }
            sawProgress = standardError().contains("1/\(Self.fileCount) ")
            send(process)
        }
        XCTAssertTrue(sawProgress, "the run did not start: \(result.stderr)")

        XCTAssertEqual(result.exitCode, 1)
        let json = try result.json()
        XCTAssertEqual(json["stopped"] as? Bool, true)
        let failed = try XCTUnwrap(json["failed"] as? Int)
        let notes = try XCTUnwrap(json["notes"] as? [NSDictionary])
        let set = try XCTUnwrap(json["set"] as? Int)
        XCTAssertGreaterThanOrEqual(set, 1)
        XCTAssertLessThan(set, Self.fileCount, "the run must stop before the last file")
        XCTAssertTrue(result.messages.contains("Stopping after the current file."), result.stderr)

        // The tools normally do not get a signal that went to the tool's
        // group. One that is just starting can (design 12.1). That one file
        // is then `failed`, its detail names the signal, and it is left as
        // it was. Nothing else may fail: not a second file, and not for
        // another reason.
        XCTAssertEqual(failed, notes.count, "every failed file has its note")
        XCTAssertLessThanOrEqual(failed, allowedSignal == nil ? 0 : 1,
                                 "at most one program was just starting, and none when the tool alone got the signal: \(notes)")
        var failedName: String?
        if let note = notes.first, let allowedSignal {
            failedName = note["name"] as? String
            XCTAssertEqual(note["kind"] as? String, "failed")
            let detail = try XCTUnwrap(note["detail"] as? String)
            // With its period: "signal 20" to "signal 29" must not pass.
            XCTAssertTrue(detail.contains("signal \(allowedSignal)."),
                          "the only allowed failure is signal \(allowedSignal): \(detail)")
        }

        // Each file is whole: set and checked with its backup gone, or not
        // started, or (rarely) the one that the signal reached, as it was.
        XCTAssertEqual(try names(in: folder), (1...Self.fileCount).map { "photo \($0).dng" },
                       "no backup and no exiftool work file stays in the folder")
        XCTAssertEqual(try names(in: discard).count, set, "one backup for each file that was set")
        let scan = try desqueeze("scan", folder.path, "--json").json()
        let dngs = try XCTUnwrap(scan["dngs"] as? [NSDictionary])
        let scales = dngs.map { $0["scale"] as? String }
        XCTAssertEqual(scales.filter { $0 == "1.5 1" }.count, set)
        XCTAssertEqual(scales.filter { $0 == "1 1" }.count, Self.fileCount - set)
        if let failedName {
            let scale = dngs.first { $0["name"] as? String == failedName }?["scale"] as? String
            XCTAssertEqual(scale, "1 1", "the file that the signal reached is unchanged")
        }
    }
}
