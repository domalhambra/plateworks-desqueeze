import DesqueezeCore
import XCTest

/// The built tool where a run cannot complete cleanly: exit code 1, a backup
/// that has lost its DNG, and a wrong value for the test variable.
final class EndToEndFailureTests: BuiltToolTestCase {
    // MARK: Exit code 1

    func testAFolderThatDoesNotExistGivesOne() throws {
        let missing = base.appendingPathComponent("No such folder").path

        let text = try desqueeze("scan", missing)
        XCTAssertEqual(text.exitCode, 1)
        XCTAssertEqual(text.stdout, "")
        XCTAssertEqual(text.messages.first, "desqueeze: This folder could not be read: \(missing)")

        let json = try desqueeze("run", missing, "--factor", "1.5", "--json")
        XCTAssertEqual(json.exitCode, 1)
        XCTAssertEqual(try json.json()["error"] as? String, "This folder could not be read: \(missing)")
    }

    func testABlockedFileGivesOneAndIsNotTouched() throws {
        let held = try copyFixture("sample.dng", as: "held.dng")
        try copyFixture("sample.dng", as: "free.dng")
        let backup = folder.appendingPathComponent("held.dng_original")
        try Data("an older backup".utf8).write(to: backup)
        let heldBefore = try Data(contentsOf: held)

        let result = try desqueeze("run", folder.path, "--factor", "1.5", "--json")

        XCTAssertEqual(result.exitCode, 1)
        let json = try result.json()
        XCTAssertEqual(counts(json), [0, 1, 0, 1, 0, 0], "blocked, not skipped")
        XCTAssertEqual(json["notes"] as? [NSDictionary], [[
            "name": "held.dng", "kind": "blockedByBackup",
            "message": "Blocked. An older backup, held.dng_original, is beside this file. Move it away, then run again.",
            "detail": NSNull(),
        ]])
        XCTAssertEqual(try Data(contentsOf: held), heldBefore)
        XCTAssertEqual(try Data(contentsOf: backup), Data("an older backup".utf8))
        XCTAssertEqual(try names(in: discard), ["free.dng_original"], "only the backup that this run made")

        // The same folder, as text.
        let text = try desqueeze("run", folder.path, "--factor", "1.5")
        XCTAssertEqual(text.exitCode, 1)
        XCTAssertEqual(text.stdout, """
            0 set · 1 skipped · 1 blocked · 0 failed
            held.dng: Blocked. An older backup, held.dng_original, is beside this file. Move it away, then run again.

            """)
    }

    func testAFileThatFailsGivesOneAndTheToolsOwnWords() throws {
        try copyFixture("sample.dng", as: "good.dng")
        try Data("not a photo".utf8).write(to: folder.appendingPathComponent("junk.dng"))

        let result = try desqueeze("run", folder.path, "--factor", "1.5", "--json")

        XCTAssertEqual(result.exitCode, 1)
        let json = try result.json()
        XCTAssertEqual(counts(json), [0, 1, 0, 0, 1, 0])
        let note = try XCTUnwrap((json["notes"] as? [NSDictionary])?.first)
        XCTAssertEqual(note["name"] as? String, "junk.dng")
        XCTAssertEqual(note["kind"] as? String, "failed")
        XCTAssertEqual(note["message"] as? String, "Not changed.")
        XCTAssertEqual((note["detail"] as? String)?.hasPrefix("Error"), true)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("junk.dng")), Data("not a photo".utf8))
    }

    func testAReadOnlyFolderScansWithZeroAndRunsWithOneAndNoFileIsTried() throws {
        try makeShoot()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        let before = try folderState()

        let scan = try desqueeze("scan", folder.path, "--json")
        XCTAssertEqual(scan.exitCode, 0, "the scan completed")
        XCTAssertEqual(try scan.json()["writable"] as? Bool, false)

        let run = try desqueeze("run", folder.path, "--factor", "1.5", "--json")
        XCTAssertEqual(run.exitCode, 1)
        let json = try run.json()
        XCTAssertEqual(counts(json), [0, 0, 0, 0, 0, 1])
        XCTAssertEqual((json["notes"] as? [NSDictionary])?.map { $0["kind"] as? String }, ["folderReadOnly"])
        XCTAssertEqual(run.messages, [])
        XCTAssertEqual(try folderState(), before)
    }

    // MARK: The orphan backup

    // Found with the real tools before the fix: the run converted frame.ARW
    // and gave two notes that said opposite things about one photo.
    func testAnOrphanBackupClaimsItsARWSoTheRunConvertsNothing() throws {
        try copyFixture("sample.dng", as: "frame.dng_original")
        try copyFixture("sample.ARW", as: "frame.ARW")
        let before = try folderState()

        let scan = try desqueeze("scan", folder.path, "--json").json()
        XCTAssertEqual(scan["pendingARWs"] as? [String], [])
        XCTAssertEqual(scan["orphanBackups"] as? [String], ["frame.dng_original"])

        let result = try desqueeze("run", folder.path, "--factor", "1.5", "--json")
        XCTAssertEqual(result.exitCode, 0)
        let json = try result.json()
        XCTAssertEqual(counts(json), [0, 0, 0, 0, 0, 0])
        XCTAssertEqual((json["notes"] as? [NSDictionary])?.map { $0["kind"] as? String }, ["orphanBackup"])
        XCTAssertEqual(try folderState(), before)
    }

    // MARK: A pipe that closes early

    // `desqueeze run … | head -1` closes the pipe in the middle of a run. A
    // write to it raises SIGPIPE, and the default action ends the process
    // with half the files done. The tool ignores SIGPIPE, completes the run,
    // and loses only the output (design 12.1).
    func testAClosedPipeDoesNotStopARun() throws {
        let count = 10
        for number in 1...count { try copyFixture("sample.dng", as: "photo \(number).dng") }

        let process = process(["run", folder.path, "--factor", "1.5", "--verbose"])
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        // Read the first output, so the run is under way. Then close both
        // ends that read, as `head` does. The run has more to write.
        let first = err.fileHandleForReading.availableData
        XCTAssertFalse(first.isEmpty, "the run did not start")
        try err.fileHandleForReading.close()
        try out.fileHandleForReading.close()

        let limit = Date().addingTimeInterval(120)
        while process.isRunning, Date() < limit { usleep(10_000) }
        if process.isRunning {
            process.terminate()
            return XCTFail("the tool did not end by itself")
        }
        XCTAssertEqual(process.terminationReason, .exit,
                       "the tool ended by signal \(process.terminationStatus): a closed pipe must not end it")
        XCTAssertEqual(process.terminationStatus, 0)

        let scales = try scales()
        XCTAssertEqual(scales.count, count)
        XCTAssertEqual(Set(scales.values), ["1.5 1"], "every DNG has the tag")
        XCTAssertEqual(try names(in: folder), (1...count).map { "photo \($0).dng" }.sorted(),
                       "no backup and no work file stays in the folder")
        XCTAssertEqual(try names(in: discard).count, count, "every backup was discarded")
    }

    // MARK: The test folder for backups

    // The variable must name a folder. `=1` starts nothing, so nobody gets a
    // run with no Trash by a typing error.
    func testAWrongValueForTheTestVariableStopsTheToolBeforeItReadsAFolder() throws {
        try makeShoot()
        let before = try folderState()
        for value in ["1", "", "relative", folder.appendingPathComponent("frame.ARW").path] {
            let result = try desqueeze("run", folder.path, "--factor", "1.5",
                                       environment: [FileBackups.testFolderVariable: value])
            XCTAssertEqual(result.exitCode, 1, value)
            XCTAssertEqual(result.stdout, "", value)
            XCTAssertTrue(result.stderr.hasPrefix(
                "desqueeze: DESQUEEZE_TEST_BACKUP_FOLDER is set, and its value is not a folder: \"\(value)\"."), value)
        }
        XCTAssertEqual(try folderState(), before)
    }

    // With --json, standard output gets the one error object, as it does for
    // every failure that has no report. Standard error keeps its message.
    func testAWrongValueForTheTestVariableWithJSONPrintsTheErrorObject() throws {
        try makeShoot()
        let before = try folderState()
        for value in ["1", "", "relative", folder.appendingPathComponent("frame.ARW").path] {
            for arguments in [["run", folder.path, "--factor", "1.5", "--json"], ["scan", folder.path, "--json"],
                              ["remove", folder.path, "--dry-run", "--json"]] {
                let result = try finish(process(arguments, environment: [FileBackups.testFolderVariable: value]),
                                        started: { _ in })
                XCTAssertEqual(result.exitCode, 1, "\(value) \(arguments)")
                let json = try result.json()
                XCTAssertEqual(Set(json.allKeys.compactMap { $0 as? String }), ["error", "detail"], value)
                XCTAssertEqual(json["error"] as? String,
                               "DESQUEEZE_TEST_BACKUP_FOLDER is set, and its value is not a folder: \"\(value)\".")
                XCTAssertEqual(json["detail"] as? String, "It is for tests only. Unset it, then run again.")
                XCTAssertEqual(result.stderr, "desqueeze: \(json["error"] as! String) \(json["detail"] as! String)\n",
                               "standard error keeps its message")
            }
        }
        XCTAssertEqual(try folderState(), before)
    }

    // A usage error wins over the bad variable: exit 2, nothing on standard output.
    func testAUsageErrorWinsOverAWrongTestVariable() throws {
        for arguments in [["run", folder.path, "--json"], ["scan", "--frob", "--json"]] {
            let result = try finish(process(arguments, environment: [FileBackups.testFolderVariable: "1"]),
                                    started: { _ in })
            XCTAssertEqual(result.exitCode, 2, "\(arguments)")
            XCTAssertEqual(result.stdout, "", "\(arguments)")
            XCTAssertTrue(result.stderr.hasPrefix("desqueeze: "), result.stderr)
            XCTAssertFalse(result.stderr.contains(FileBackups.testFolderVariable))
        }
    }

    func testTheToolSaysWhenItDoesNotUseTheTrash() throws {
        try makeShoot()
        let result = try desqueeze("scan", folder.path)
        XCTAssertEqual(result.stderr, "Test mode: every file that would go to the Trash goes to \(discard.path).\n")
    }
}
