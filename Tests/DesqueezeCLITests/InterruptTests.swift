import DesqueezeCore
import XCTest

/// Control-C on the built tool, in the middle of a real run.
final class InterruptTests: BuiltToolTestCase {
    static let fileCount = 8

    /// A terminal sends Control-C to the foreground process group. `Process`
    /// starts each child in a group of its own, so the group of the tool
    /// holds the tool and no exiftool. The signal goes to that group, as the
    /// terminal sends it.
    func interrupt(_ process: Process) {
        let id = process.processIdentifier
        XCTAssertEqual(getpgid(id), id, "the tool leads a process group of its own")
        XCTAssertEqual(kill(-id, SIGINT), 0)
    }

    func testControlCStopsAfterTheCurrentFilePrintsTheResultSoFarAndGivesOne() throws {
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
            interrupt(process)
        }
        XCTAssertTrue(sawProgress, "the run did not start: \(result.stderr)")

        XCTAssertEqual(result.exitCode, 1)
        let json = try result.json()
        XCTAssertEqual(json["stopped"] as? Bool, true)
        let set = try XCTUnwrap(json["set"] as? Int)
        XCTAssertGreaterThanOrEqual(set, 1)
        XCTAssertLessThan(set, Self.fileCount, "the run must stop before the last file")
        XCTAssertEqual(json["failed"] as? Int, 0, "the file in work must complete: exiftool must not get the signal")
        XCTAssertEqual(json["notes"] as? [NSDictionary], [])
        XCTAssertTrue(result.messages.contains("Stopping after the current file."), result.stderr)

        // Each file is whole: set and checked with its backup gone, or not started.
        XCTAssertEqual(try names(in: folder), (1...Self.fileCount).map { "photo \($0).dng" },
                       "no backup and no exiftool work file stays in the folder")
        XCTAssertEqual(try names(in: discard).count, set, "one backup for each file that was set")
        let scan = try desqueeze("scan", folder.path, "--json").json()
        let scales = try XCTUnwrap(scan["dngs"] as? [NSDictionary]).map { $0["scale"] as? String }
        XCTAssertEqual(scales.filter { $0 == "1.5 1" }.count, set)
        XCTAssertEqual(scales.filter { $0 == "1 1" }.count, Self.fileCount - set)
    }
}
