import DesqueezeCore
import XCTest
@testable import DesqueezeCLI

/// The exit code of each result, with fake tools: 0 when the command
/// completed and no file failed or was blocked, 1 for the cases of the design.
final class ExitCodeTests: XCTestCase {
    var h: ToolHarness!

    override func setUpWithError() throws { h = try ToolHarness() }
    override func tearDown() { h.cleanUp() }

    func testAFailedFileGivesOne() throws {
        try h.touch("A.dng", "junk.dng")
        h.tools.scales = ["A.dng": "1 1"]
        h.tools.failWrites = ["junk.dng"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--json"), 1)
        let json = try h.json()
        XCTAssertEqual(json["failed"] as? Int, 1)
        XCTAssertEqual(json["set"] as? Int, 1)
        let note = try XCTUnwrap((json["notes"] as? [NSDictionary])?.first)
        XCTAssertEqual(note["kind"] as? String, "failed")
        XCTAssertEqual(note["detail"] as? String, "Error: Not a valid TIFF")
    }

    // A DNG with no full match is converted. Its note does not make the
    // code 1 (design 13.4).
    func testANoteForADNGWithNoFullMatchGivesZero() {
        var summary = RunSummary()
        summary.convertedByDnglab = 1
        summary.notes = [FileNote(name: "X.dng", kind: .convertedUnmatched, message: "Converted.", detail: nil)]
        let folder = URL(fileURLWithPath: "/tmp/Shoot 1")
        XCTAssertEqual(DesqueezeTool.exitCode(RunReport(folder: folder, factor: .noStretch, summary: summary)), 0)
        summary.failed = 1
        XCTAssertEqual(DesqueezeTool.exitCode(RunReport(folder: folder, factor: .noStretch, summary: summary)), 1)
    }

    // An original that stays is information. Its note does not make the
    // code 1 (design 14.3).
    func testANoteForAnOriginalThatStaysGivesZero() {
        var summary = RunSummary()
        summary.convertedByDnglab = 1
        summary.trashOriginals = true
        summary.notes = [FileNote(name: "X.ARW", kind: .originalKept,
                                  message: "The original changed during the run, so it stays.", detail: nil)]
        let folder = URL(fileURLWithPath: "/tmp/Shoot 1")
        XCTAssertEqual(DesqueezeTool.exitCode(RunReport(folder: folder, factor: .noStretch, summary: summary)), 0)
    }

    // A run on a volume that gives no folder lock went on, and nothing
    // failed. Its note does not make the code 1 (design 13.9).
    func testANoteForAVolumeWithNoFolderLockGivesZero() {
        var summary = RunSummary()
        summary.set = 2
        summary.notes = [FileNote(name: "Shoot 1", kind: .noFolderLock,
                                  message: "This volume gives no folder lock.", detail: nil)]
        let folder = URL(fileURLWithPath: "/tmp/Shoot 1")
        XCTAssertEqual(DesqueezeTool.exitCode(RunReport(folder: folder, factor: .noStretch, summary: summary)), 0)
        summary.blocked = 1
        XCTAssertEqual(DesqueezeTool.exitCode(RunReport(folder: folder, factor: .noStretch, summary: summary)), 1)
    }

    func testABlockedFileGivesOneInARunAndInADryRun() throws {
        try h.touch("A.dng", "A.dng_original")
        h.tools.scales = ["A.dng": "1 1"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--dry-run", "--json"), 1)
        XCTAssertEqual(try h.json()["blocked"] as? Int, 1)
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--json"), 1)
        let json = try h.json()
        XCTAssertEqual(json["blocked"] as? Int, 1)
        XCTAssertEqual(json["skipped"] as? Int, 0)
        XCTAssertEqual(((json["notes"] as? [NSDictionary])?.first)?["kind"] as? String, "blockedByBackup")
        XCTAssertEqual(h.tools.scales, ["A.dng": "1 1"], "the file was not written")
    }

    // The scan completed, so it gives 0: the report says that the folder is
    // read-only (design 12.1). A run cannot do its work there, so it gives 1.
    func testAReadOnlyFolderGivesZeroForScanAndOneForEachRun() throws {
        try h.touch("A.dng")
        h.tools.scales = ["A.dng": "1 1"]
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: h.shoot.path)

        XCTAssertEqual(h.run("scan", "Shoot 1", "--json"), 0)
        XCTAssertEqual(try h.json()["writable"] as? Bool, false)
        XCTAssertEqual(h.run("scan", "Shoot 1"), 0)
        XCTAssertTrue(h.out.lines.contains("This folder is read-only. Desqueeze cannot change its files."))

        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--json"), 1)
        XCTAssertEqual(((try h.json()["notes"] as? [NSDictionary])?.first)?["kind"] as? String, "folderReadOnly")
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--dry-run"), 1)
        XCTAssertEqual(h.run("remove", "Shoot 1"), 1)
        XCTAssertEqual(h.run("remove", "Shoot 1", "--dry-run"), 1)
        XCTAssertEqual(h.tools.scales, ["A.dng": "1 1"])
    }

    func testAStoppedRunPrintsTheResultSoFarAndGivesOne() throws {
        try h.touch("A.dng", "B.dng")
        h.tools.scales = ["A.dng": "1 1", "B.dng": "1 1"]
        h.cancel.cancel()
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--json"), 1)
        let json = try h.json()
        XCTAssertEqual(json["stopped"] as? Bool, true)
        XCTAssertEqual(json["set"] as? Int, 0)
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5"), 1)
        XCTAssertEqual(h.out.lines, ["0 set · 0 skipped · 0 failed · stopped"])
    }

    func testASecondRunSkipsEveryFileAndGivesZero() throws {
        try h.touch("A.dng", "B.dng")
        h.tools.scales = ["A.dng": "1 1", "B.dng": "1 1"]
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5"), 0)
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5"), 0)
        XCTAssertEqual(h.out.lines, ["0 set · 2 skipped · 0 failed"])
    }

    // An orphan backup is reported by every command, and is not a failure.
    func testAFolderWithOnlyAnOrphanBackupIsReportedAndGivesZero() throws {
        try h.touch("lost.dng_original")
        let sentence = "lost.dng_original: A backup with no DNG beside it. Rename it to lost.dng to get the photo back."
        XCTAssertEqual(h.run("scan", "Shoot 1"), 0)
        XCTAssertTrue(h.out.lines.contains(sentence))
        XCTAssertFalse(h.out.text.contains("No DNG or ARW files"))
        XCTAssertEqual(h.run("scan", "Shoot 1", "--json"), 0)
        XCTAssertEqual(try h.json()["orphanBackups"] as? [String], ["lost.dng_original"])
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5"), 0)
        XCTAssertEqual(h.out.lines, ["0 set · 0 skipped · 0 failed", sentence])
        XCTAssertEqual(h.run("remove", "Shoot 1", "--dry-run", "--json"), 0)
        XCTAssertEqual(((try h.json()["notes"] as? [NSDictionary])?.first)?["kind"] as? String, "orphanBackup")
    }

    func testAnEmptyFolderSaysSoAndGivesZero() {
        XCTAssertEqual(h.run("scan", "Shoot 1"), 0)
        XCTAssertTrue(h.out.lines.contains("No DNG or ARW files in this folder."))
    }

    // Run and remove say it too, in text mode. The JSON does not change.
    func testRunAndRemoveOnAnEmptyFolderSayTheSentenceAndGiveZero() throws {
        for arguments in [["run", "Shoot 1", "--factor", "1.5"], ["remove", "Shoot 1"]] {
            XCTAssertEqual(DesqueezeTool.run(arguments, in: h.environment), 0, "\(arguments)")
            XCTAssertEqual(DesqueezeTool.run(arguments + ["--dry-run"], in: h.environment), 0, "\(arguments)")
        }
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5"), 0)
        XCTAssertEqual(h.out.lines, [FolderText.noPhotos])
        XCTAssertEqual(h.run("remove", "Shoot 1"), 0)
        XCTAssertEqual(h.out.lines, [FolderText.noPhotos])
        XCTAssertEqual(h.run("remove", "Shoot 1", "--dry-run"), 0)
        XCTAssertEqual(h.out.lines, ["Dry run. No file was changed.", FolderText.noPhotos])

        XCTAssertEqual(h.run("remove", "Shoot 1", "--json"), 0)
        let json = try h.json()
        XCTAssertEqual(Set(json.allKeys.compactMap { $0 as? String }),
                       ["folder", "factor", "dryRun", "converted", "convertedByDnglab", "convertedByAdobe", "set",
                        "skipped", "blocked", "failed", "stopped", "unconvertedARWs", "trashOriginals",
                        "originalsInTrash", "notes"])
        XCTAssertFalse(h.out.text.contains("No DNG or ARW"))
    }

    // Remove has no ARW work, but a folder with an ARW is not empty.
    func testRemoveOnAFolderWithOnlyAnARWFileDoesNotSayItIsEmpty() throws {
        try h.touch("X.ARW")
        XCTAssertEqual(h.run("remove", "Shoot 1"), 0)
        XCTAssertEqual(h.out.lines, ["0 set · 0 skipped · 0 failed"])
    }

    // MARK: The test folder for backups

    func testTheToolSaysOnStandardErrorWhenBackupsDoNotGoToTheTrash() throws {
        try h.touch("A.dng")
        h.tools.scales = ["A.dng": "1 1"]
        h.testBackupFolder = h.base
        XCTAssertEqual(h.run("run", "Shoot 1", "--factor", "1.5", "--json"), 0)
        XCTAssertEqual(h.err.lines.first, "Test mode: every file that would go to the Trash goes to \(h.base.path).")
        _ = try h.json()

        h.testBackupFolder = nil
        h.run("remove", "Shoot 1")
        XCTAssertFalse(h.err.text.contains("Test mode"))
    }
}
