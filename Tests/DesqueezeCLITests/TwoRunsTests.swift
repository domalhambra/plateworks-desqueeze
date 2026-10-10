import DesqueezeCore
import XCTest

/// One run in a folder at a time (design 13.9), with two processes of the
/// built tool and the real exiftool.
final class TwoRunsTests: BuiltToolTestCase {
    static let fileCount = 10
    static let sentence = "Another Desqueeze run is working in this folder. Wait for it to end, then run again."

    // The second run starts while the first is in its loop. It must not
    // start: its step 1 would take the first run's files for leftovers.
    func testASecondRunInTheSameFolderIsRefusedAndTheFirstCompletes() throws {
        for number in 1...Self.fileCount { try copyFixture("sample.dng", as: "photo \(number).dng") }
        // The second process discards into a folder of its own, so the test
        // can see that it discarded nothing.
        let secondDiscard = base.appendingPathComponent("Discarded by the second run")
        try FileManager.default.createDirectory(at: secondDiscard, withIntermediateDirectories: true)
        let variable = [FileBackups.testFolderVariable: secondDiscard.path as String?]

        let first = process(["run", folder.path, "--factor", "1.5", "--json"])
        var sawProgress = false
        var firstWorkedToTheEndOfTheSecond = false
        var seconds: [Output] = []
        let result = try finish(first) { standardError in
            // Wait for the first file to complete, so the run is in its loop.
            let limit = Date().addingTimeInterval(60)
            while !standardError().contains("1/\(Self.fileCount) "), first.isRunning, Date() < limit {
                usleep(2_000)
            }
            sawProgress = standardError().contains("1/\(Self.fileCount) ")
            seconds.append(try desqueeze("run", folder.path, "--factor", "2", "--json", environment: variable))
            seconds.append(try desqueeze("remove", folder.path, environment: variable))
            firstWorkedToTheEndOfTheSecond = first.isRunning
        }
        XCTAssertTrue(sawProgress, "the first run did not start: \(result.stderr)")
        XCTAssertTrue(firstWorkedToTheEndOfTheSecond,
                      "the first run ended before the second: this Mac is too fast for \(Self.fileCount) files")

        // The second run, and a remove: neither started.
        let json = try XCTUnwrap(seconds.first).json()
        XCTAssertEqual(json["error"] as? String, Self.sentence)
        XCTAssertEqual(json.count, 2, "the error object, and no report")
        for second in seconds {
            XCTAssertEqual(second.exitCode, 1)
            XCTAssertEqual(second.messages, ["desqueeze: \(Self.sentence)"], "no progress: no file was tried")
        }
        XCTAssertEqual(seconds.last?.stdout, "")
        XCTAssertEqual(try names(in: secondDiscard), [], "the second run discarded nothing")

        // The first run: every file set, at its own factor.
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let report = try result.json()
        XCTAssertEqual(counts(report), [0, Self.fileCount, 0, 0, 0, 0])
        XCTAssertEqual(report["notes"] as? [NSDictionary], [])
        XCTAssertEqual(try names(in: folder), (1...Self.fileCount).map { "photo \($0).dng" }.sorted(),
                       "no backup, no work file and no exiftool file stays in the folder")
        XCTAssertEqual(try names(in: discard).count, Self.fileCount, "one backup for each file that was set")
        XCTAssertEqual(Set(try scales().values), ["1.5 1"])
    }

    // The lock goes with the run: the next run in the folder starts.
    func testTwoRunsInARowBothPass() throws {
        for number in 1...2 { try copyFixture("sample.dng", as: "photo \(number).dng") }
        let first = try desqueeze("run", folder.path, "--factor", "1.5", "--json")
        XCTAssertEqual(first.exitCode, 0, first.stderr)
        XCTAssertEqual(counts(try first.json()), [0, 2, 0, 0, 0, 0])
        let second = try desqueeze("run", folder.path, "--factor", "2", "--json")
        XCTAssertEqual(second.exitCode, 0, second.stderr)
        XCTAssertEqual(counts(try second.json()), [0, 2, 0, 0, 0, 0])
        XCTAssertEqual(Set(try scales().values), ["2 1"])
    }
}
