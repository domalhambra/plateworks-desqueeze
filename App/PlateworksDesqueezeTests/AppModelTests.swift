import AppKit
// With `@testable`, for one thing: the test of a lock call that fails makes
// a `FolderLock` on its own three calls. The core gives no public way to
// make one, so the app cannot run with a lock that does not lock.
@testable import DesqueezeCore
import XCTest

/// The window's state (design, section 5). Each test has its own model, on
/// fakes and on temporary folders. No test starts the app, opens a window,
/// starts a tool, or reaches the Trash.
@MainActor
final class AppModelTests: XCTestCase {
    /// A time after the double-click time, so Cancel is a real Cancel.
    private var afterTheDoubleClickTime: TimeInterval { NSEvent.doubleClickInterval + 0.01 }

    // MARK: Scans

    // The first folder's scan lands while the second folder's scan is in
    // flight. It is stale: it shows nothing, and the window still scans.
    func testAStaleScanShowsNothingAndDoesNotEndTheScanningState() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        let a = try h.folder("A", files: ["a1.dng"])
        let b = try h.folder("B", files: ["b1.dng", "b2.dng"])
        h.tag.readGate("A").close()
        h.tag.readGate("B").close()

        XCTAssertTrue(h.model.handleDrop([a]))
        await h.wait("the scan of A is in work") { h.tag.readGate("A").arrivals == 1 }
        XCTAssertTrue(h.model.handleDrop([b]))
        await h.wait("the scan of B is in work") { h.tag.readGate("B").arrivals == 1 }

        h.tag.readGate("A").open()
        await h.settle()
        XCTAssertEqual(h.model.folderName, "B")
        XCTAssertNil(h.model.snapshot, "the scan of A is not the newest scan")
        XCTAssertTrue(h.model.isScanning, "only the scan of B ends the scanning state")
        XCTAssertFalse(h.model.canRun)

        h.tag.readGate("B").open()
        await h.wait("the scan of B lands") { !h.model.isScanning }
        XCTAssertEqual(h.model.snapshot?.folder.lastPathComponent, "B")
        XCTAssertEqual(h.model.snapshot?.dngs.map(\.name), ["b1.dng", "b2.dng"])
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")
    }

    // The other order: the second folder's scan lands first, and the first
    // folder's scan lands after it.
    func testAScanThatLandsAfterANewerScanDoesNotReplaceIt() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        let a = try h.folder("A", files: ["a1.dng"])
        let b = try h.folder("B", files: ["b1.dng", "b2.dng"])
        h.tag.readGate("A").close()

        XCTAssertTrue(h.model.handleDrop([a]))
        await h.wait("the scan of A is in work") { h.tag.readGate("A").arrivals == 1 }
        XCTAssertTrue(h.model.handleDrop([b]))
        await h.wait("the scan of B lands") { !h.model.isScanning }
        XCTAssertEqual(h.model.snapshot?.folder.lastPathComponent, "B")

        h.tag.readGate("A").open()
        await h.settle()
        XCTAssertEqual(h.model.folderName, "B")
        XCTAssertEqual(h.model.snapshot?.folder.lastPathComponent, "B")
        XCTAssertEqual(h.model.snapshot?.dngs.count, 2)
        XCTAssertFalse(h.model.isScanning)
    }

    func testAScanThatFailsShowsTheSentenceOfTheCore() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        XCTAssertFalse(h.model.exiftoolMissing)
        h.tag.failReads(true)
        await h.load(try h.folder("Shoot", files: ["a.dng"]))

        XCTAssertEqual(h.model.folderMessages, ["This folder could not be read."])
        XCTAssertEqual(h.model.folderMessages, [FolderText.unreadable])
        XCTAssertNil(h.model.countsLine)
        XCTAssertFalse(h.model.canRun)
    }

    // MARK: Run and Cancel

    func testCancelStopsAtOnceAndTheRunEndsIdleWithAStoppedResultAndNewCounts() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        let shoot = try h.folder("Shoot", files: ["a.dng", "b.dng"])
        let other = try h.folder("Other", files: ["o.dng"])
        await h.load(shoot)
        XCTAssertTrue(h.model.acceptsDrop)

        h.tag.writeGate.close()
        h.model.run()
        XCTAssertEqual(h.model.phase, .running)
        await h.wait("the first file is in work") { h.tag.writeGate.arrivals == 1 }

        h.time += afterTheDoubleClickTime
        h.model.cancel()
        XCTAssertEqual(h.model.phase, .stopping, "the click is acknowledged at once")
        XCTAssertTrue(h.model.isFinishing)

        // Nothing can start now, and no drop is taken.
        h.model.cancel()
        h.model.run()
        h.model.remove()
        XCTAssertFalse(h.model.acceptsDrop, "the drop zone must not show that it takes a drop")
        XCTAssertFalse(h.model.handleDrop([other]))
        XCTAssertEqual(h.model.phase, .stopping)
        XCTAssertEqual(h.model.folderName, "Shoot")
        XCTAssertNil(h.model.summary)

        // A file that comes during the run is in the counts after the run.
        try h.touch("c.dng", in: shoot)
        h.tag.writeGate.open()
        await h.runEnds()

        XCTAssertEqual(h.phases, [.idle, .running, .stopping, .rescanning, .idle])
        XCTAssertEqual(h.model.summary?.cancelled, true)
        XCTAssertEqual(h.model.summary?.set, 1, "the file in work completes, and no other file starts")
        XCTAssertEqual(h.tag.writes, ["1.5 1 a.dng"], "no second run started")
        XCTAssertEqual(h.model.snapshot?.dngs.map(\.name), ["a.dng", "b.dng", "c.dng"])
        XCTAssertEqual(h.tag.reads, ["Shoot", "Shoot", "Shoot"], "the load, the run's own scan, the scan after")
        XCTAssertFalse(h.model.isScanning)
        XCTAssertFalse(h.model.isRunning)
        XCTAssertTrue(h.model.acceptsDrop)
    }

    // The second click of a double-click on Run lands on Cancel, which is in
    // the place of Run by then.
    func testACancelInsideTheDoubleClickTimeOfTheStartDoesNothing() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng", "b.dng"]))

        h.tag.writeGate.close()
        h.model.run()
        await h.wait("the first file is in work") { h.tag.writeGate.arrivals == 1 }

        h.time += NSEvent.doubleClickInterval / 2
        h.model.cancel()
        XCTAssertEqual(h.model.phase, .running)
        XCTAssertFalse(h.model.isFinishing)

        h.tag.writeGate.open()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.set, 2, "every file is set")
        XCTAssertEqual(h.model.summary?.cancelled, false)
        XCTAssertEqual(h.tag.writes, ["1.5 1 a.dng", "1.5 1 b.dng"])
        XCTAssertEqual(h.phases, [.idle, .running, .rescanning, .idle])
    }

    func testTheEndOfARunSaysTheCountsLineToVoiceOver() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng", "b.dng"]))
        XCTAssertEqual(h.announcements, [])

        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.announcements, ["2 set · 0 skipped · 0 failed"])
        XCTAssertEqual(h.announcements, [try XCTUnwrap(h.model.summary).countsLine])
    }

    // The run's own scan fails, so there is no summary. The window shows the
    // sentence of the core then, and VoiceOver hears it.
    func testTheEndOfARunWhoseScanFailedSaysTheUnreadableSentenceToVoiceOver() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))

        h.tag.failReads(true)
        h.model.run()
        await h.runEnds()
        XCTAssertNil(h.model.summary)
        XCTAssertEqual(h.model.folderMessages, [FolderText.unreadable])
        XCTAssertEqual(h.announcements, [FolderText.unreadable])
    }

    // MARK: One run in a folder at a time (design 13.9)

    // The test holds the lock that a run takes, as the command line tool
    // does while it works in the folder. The lock is the system's own, on a
    // temporary folder.
    func testARunWhileAnotherRunWorksInTheFolderShowsTheSentenceAndReturnsToIdle() async throws {
        let sentence = "Another Desqueeze run is working in this folder. Wait for it to end, then run again."
        let h = try ModelHarness()
        defer { h.cleanUp() }
        let folder = try h.folder("Shoot", files: ["a.dng", "b.dng"])
        await h.load(folder)
        guard case .held(let other) = FolderLock.system.take(folder) else { return XCTFail("the lock of the test") }
        defer { other.release() }

        for click in [h.model.run, h.model.remove] {
            click()
            XCTAssertEqual(h.model.phase, .running)
            await h.runEnds()
            XCTAssertEqual(h.model.folderMessages, [sentence], "where the message of a failed scan shows")
            XCTAssertNil(h.model.summary, "no run, so no result")
            XCTAssertEqual(h.tag.writes, [], "no file was tried")
            XCTAssertEqual(h.announcements.last, sentence)
            // The folder is not unreadable: its counts are there, from a new
            // scan, and the buttons are on again.
            XCTAssertEqual(h.model.countsLine, "2 DNG")
            XCTAssertTrue(h.model.canRun)
            XCTAssertTrue(h.model.canRemove)
        }
        XCTAssertEqual(h.phases, [.idle, .running, .rescanning, .idle, .running, .rescanning, .idle])

        // The other run ended. The next click runs, and the sentence is gone.
        other.release()
        h.model.run()
        XCTAssertEqual(h.model.folderMessages, [], "the sentence goes at the next click")
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.set, 2)
        XCTAssertEqual(h.model.folderMessages, [])
        XCTAssertEqual(h.announcements.last, "2 set · 0 skipped · 0 failed")
    }

    func testANewFolderTakesTheSentenceOfARefusedRunAway() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        let folder = try h.folder("Shoot", files: ["a.dng"])
        await h.load(folder)
        guard case .held(let other) = FolderLock.system.take(folder) else { return XCTFail("the lock of the test") }
        defer { other.release() }
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.folderMessages.count, 1)

        await h.load(try h.folder("Other", files: ["c.dng"]))
        XCTAssertEqual(h.model.folderMessages, [])
    }

    // One state, one message. A run is refused, and the scan that follows
    // the refusal fails: the folder went away. The scan is the newer event,
    // so the window shows "could not be read", and VoiceOver hears the
    // same. Until 2026-10-10 VoiceOver heard the refusal.
    func testAfterARefusalAScanThatFailsWinsInTheWindowAndForVoiceOver() async throws {
        let sentence = "Another Desqueeze run is working in this folder. Wait for it to end, then run again."
        let h = try ModelHarness()
        defer { h.cleanUp() }
        let folder = try h.folder("Shoot", files: ["a.dng"])
        await h.load(folder)
        guard case .held(let other) = FolderLock.system.take(folder) else { return XCTFail("the lock of the test") }
        defer { other.release() }

        // The refused run reads nothing. Only the scan after it meets this.
        h.tag.failReads(true)
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.folderMessages, ["This folder could not be read."])
        XCTAssertEqual(h.announcements, ["This folder could not be read."], "VoiceOver hears what the window shows")
        XCTAssertNil(h.model.runRefusal, "the refusal is not kept behind the newer message")
        XCTAssertFalse(h.announcements.contains(sentence))

        // The folder is back. The next scan shows its counts, and no
        // sentence about a click that the newer event replaced.
        h.tag.failReads(false)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertEqual(h.model.folderMessages, [])
        XCTAssertEqual(h.model.countsLine, "1 DNG")
    }

    // The same rule for a scan that fails later, when the app becomes
    // active again: the refusal goes, and it does not come back with the
    // next good scan.
    func testAScanThatFailsLaterTakesTheSentenceOfARefusedRunAway() async throws {
        let sentence = "Another Desqueeze run is working in this folder. Wait for it to end, then run again."
        let h = try ModelHarness()
        defer { h.cleanUp() }
        let folder = try h.folder("Shoot", files: ["a.dng"])
        await h.load(folder)
        guard case .held(let other) = FolderLock.system.take(folder) else { return XCTFail("the lock of the test") }
        defer { other.release() }
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.folderMessages, [sentence])

        // A good scan keeps the sentence: nothing newer has happened.
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertEqual(h.model.folderMessages, [sentence])

        h.tag.failReads(true)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertEqual(h.model.folderMessages, ["This folder could not be read."])

        h.tag.failReads(false)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertEqual(h.model.folderMessages, [], "the refusal does not come back")
    }

    // MARK: A lock call that fails (design 13.9, the last row of the table)

    /// A lock whose call fails with `code`: the system gave an error that
    /// says nothing about the lock. It opens and closes nothing.
    private func lockThatFails(with code: Int32) -> FolderLock {
        FolderLock(open: { _ in (descriptor: 7, code: 0) }, lock: { _ in code }, close: { _ in })
    }

    // The run does not start. The window shows the folder as one that could
    // not be read, and the system's words on the detail line, as the
    // command line tool and the MCP server do. Until 2026-10-10 the window
    // showed the sentence alone.
    func testALockCallThatFailsShowsTheSystemsWordsOnTheDetailLine() async throws {
        let h = try ModelHarness(lock: lockThatFails(with: EIO))
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng", "b.dng"]))
        XCTAssertEqual(h.model.folderMessages, [])
        XCTAssertNil(h.model.folderMessageDetail)

        for click in [h.model.run, h.model.remove] {
            click()
            await h.runEnds()
            XCTAssertEqual(h.model.folderMessages, ["This folder could not be read."])
            XCTAssertEqual(h.model.folderMessageDetail, "Input/output error")
            XCTAssertEqual(h.model.folderMessageDetail, FolderLock.Failed(code: EIO).localizedDescription,
                           "the words are the core's")
            XCTAssertNil(h.model.summary, "no run, so no result")
            XCTAssertNil(h.model.runRefusal, "no other run works in the folder")
            XCTAssertEqual(h.tag.writes, [], "no file was tried")
            XCTAssertEqual(h.saves, [], "a run that did not start saves no factor")
            XCTAssertEqual(h.announcements.last, "This folder could not be read.")

            // The next scan reads the folder. It is newer than the click
            // that failed, so the detail goes with the sentence.
            h.model.appBecameActive()
            await h.wait("the scan lands") { !h.model.isScanning }
            XCTAssertEqual(h.model.folderMessages, [])
            XCTAssertNil(h.model.folderMessageDetail)
            XCTAssertEqual(h.model.countsLine, "2 DNG")
        }
    }

    // The detail is the system's words for the number that the call gave.
    func testTheDetailLineOfALockCallThatFailsHasTheWordsOfItsError() async throws {
        let h = try ModelHarness(lock: lockThatFails(with: EBADF))
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.folderMessageDetail, "Bad file descriptor")
    }

    func testANewFolderAndAScanThatFailsTakeTheDetailLineAway() async throws {
        let h = try ModelHarness(lock: lockThatFails(with: EIO))
        defer { h.cleanUp() }
        let shoot = try h.folder("Shoot", files: ["a.dng"])
        await h.load(shoot)
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.folderMessageDetail, "Input/output error")

        // A scan that fails is the newer event. It has no words of the
        // system, so the sentence stands alone.
        h.tag.failReads(true)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertEqual(h.model.folderMessages, ["This folder could not be read."])
        XCTAssertNil(h.model.folderMessageDetail)

        h.tag.failReads(false)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.folderMessageDetail, "Input/output error")
        // Another folder takes the detail away at once, before its scan
        // lands: nothing about the folder before it stays.
        let other = try h.folder("Other", files: ["c.dng"])
        h.tag.readGate("Other").close()
        XCTAssertTrue(h.model.handleDrop([other]))
        XCTAssertTrue(h.model.isScanning)
        XCTAssertNil(h.model.folderMessageDetail, "another folder takes the detail away")
        h.tag.readGate("Other").open()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertEqual(h.model.folderMessages, [])
        XCTAssertNil(h.model.folderMessageDetail)
    }

    // Only a lock call that failed has the detail line. A run whose own
    // scan failed, and a run that another run kept out, have none.
    func testARunWhoseScanFailedAndARefusedRunHaveNoDetailLine() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        let folder = try h.folder("Shoot", files: ["a.dng"])
        await h.load(folder)

        h.tag.failReads(true)
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.folderMessages, ["This folder could not be read."])
        XCTAssertNil(h.model.folderMessageDetail)

        h.tag.failReads(false)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        guard case .held(let other) = FolderLock.system.take(folder) else { return XCTFail("the lock of the test") }
        defer { other.release() }
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.folderMessages, [FolderLock.busyMessage])
        XCTAssertNil(h.model.folderMessageDetail)
    }

    // MARK: Remove

    // The folder has one ARW with no DNG. Remove has no ARW work, so it
    // leaves none. A run with no converter leaves the one.
    func testRemoveSaysThatItIsRemoveAndRunDoesNot() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng", "b.ARW"]))
        XCTAssertEqual(h.model.snapshot?.pendingARWs.count, 1)

        h.model.remove()
        await h.runEnds()
        XCTAssertEqual(h.tag.writes, ["1 1 a.dng"])
        XCTAssertEqual(h.model.summary?.set, 1)
        XCTAssertEqual(h.model.summary?.unconvertedARWs, 0, "Remove reports no ARW file left")

        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.tag.writes, ["1 1 a.dng", "1.5 1 a.dng"])
        XCTAssertEqual(h.model.summary?.unconvertedARWs, 1, "a run reports the ARW file it left")
        XCTAssertEqual(h.backups.discarded, ["a.dng", "a.dng"], "the backups went to the fake, not to the Trash")
    }

    // MARK: Quit

    func testAQuitDuringARunWaitsForTheJobAndStartsNoScan() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng", "b.dng"]))

        h.tag.writeGate.close()
        h.model.run()
        await h.wait("the first file is in work") { h.tag.writeGate.arrivals == 1 }
        XCTAssertEqual(h.tag.reads.count, 2, "the load, and the run's own scan")

        // Inside the double-click time, on purpose: that rule is for the
        // Cancel button, and a quit does not wait for it.
        XCTAssertEqual(h.model.answerQuit(), .afterRun)
        let returned = Flag()
        // Nothing awaits this task: if the quit path never returned, the
        // bounded wait below fails the test, and the test must still end.
        Task {
            await h.model.stopRunForQuit()
            returned.isSet = true
        }
        await h.settle()
        XCTAssertEqual(h.backups.discarded, [], "the file in work is not complete")
        XCTAssertEqual(h.model.phase, .stopping)

        // A second quit request, while the first waits.
        XCTAssertEqual(h.model.answerQuit(), .alreadyWaiting)

        h.tag.writeGate.open()
        await h.wait("the quit path returns") { returned.isSet }
        XCTAssertEqual(h.backups.discarded, ["a.dng"], "the quit path returned after the file in work was complete")
        XCTAssertEqual(h.tag.writes, ["1.5 1 a.dng"], "no other file started")

        await h.settle()
        XCTAssertEqual(h.tag.reads.count, 2, "no scan after the run: it would leave an exiftool process behind")
        XCTAssertFalse(h.phases.contains(.rescanning))
        XCTAssertFalse(h.model.isScanning)
    }

    // While the quit path waits, the test's own wait would see "not yet".
    func testTheQuitPathDoesNotReturnWhileTheJobIsInItsFile() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))
        h.tag.writeGate.close()
        h.model.run()
        await h.wait("the file is in work") { h.tag.writeGate.arrivals == 1 }

        // The app delegate asks first, and only then stops the run.
        XCTAssertEqual(h.model.answerQuit(), .afterRun)
        let returned = Flag()
        Task {
            await h.model.stopRunForQuit()
            returned.isSet = true
        }
        await h.settle()
        XCTAssertFalse(returned.isSet, "the job has not returned")
        h.tag.writeGate.open()
        await h.wait("the quit path returns") { returned.isSet }
    }

    func testAQuitWithNoRunQuitsNowAndTheQuitPathReturnsAtOnce() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        XCTAssertEqual(h.model.answerQuit(), .now)
        XCTAssertEqual(h.model.answerQuit(), .now, "a quit that needs no wait leaves no state")
        await h.load(try h.folder("Shoot", files: ["a.dng"]))
        XCTAssertEqual(h.model.answerQuit(), .now)

        let returned = Flag()
        Task {
            await h.model.stopRunForQuit()
            returned.isSet = true
        }
        await h.wait("the quit path returns") { returned.isSet }
        XCTAssertEqual(h.tag.reads.count, 1)
    }

    // `answerQuit` is the only writer of the quit flag. A stop with no run in
    // work, and no answer before it, leaves the next answer at "now".
    func testTheQuitPathAloneDoesNotMakeALaterQuitWait() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }

        let returned = Flag()
        Task {
            await h.model.stopRunForQuit()
            returned.isSet = true
        }
        await h.wait("the quit path returns") { returned.isSet }
        XCTAssertEqual(h.model.answerQuit(), .now, "nothing is in work, so nothing is waited for")
    }

    // MARK: The app becomes active

    func testWhenTheAppBecomesActiveTheLoadedFolderIsScannedAgainAndTheResultStays() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        let shoot = try h.folder("Shoot", files: ["a.dng"])
        await h.load(shoot)
        h.model.run()
        await h.runEnds()
        let result = try XCTUnwrap(h.model.summary)

        // Another app puts a file in the folder.
        try h.touch("b.dng", in: shoot)
        h.model.appBecameActive()
        XCTAssertTrue(h.model.isScanning)
        await h.wait("the scan lands") { !h.model.isScanning }

        XCTAssertEqual(h.model.snapshot?.dngs.map(\.name), ["a.dng", "b.dng"])
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")
        XCTAssertEqual(h.model.summary, result, "the result of the last run stays")
        XCTAssertEqual(h.model.folderName, "Shoot")
    }

    func testWhenTheAppBecomesActiveNothingStartsDuringAScanOrARunOrWithNoFolder() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }

        // No folder.
        h.model.appBecameActive()
        XCTAssertFalse(h.model.isScanning)

        // During a scan.
        let shoot = try h.folder("Shoot", files: ["a.dng"])
        h.tag.readGate("Shoot").close()
        XCTAssertTrue(h.model.handleDrop([shoot]))
        await h.wait("the scan is in work") { h.tag.reads.count == 1 }
        h.model.appBecameActive()
        await h.settle()
        XCTAssertEqual(h.tag.reads.count, 1, "no second scan beside the first")
        h.tag.readGate("Shoot").open()
        await h.wait("the scan lands") { !h.model.isScanning }

        // During a run.
        h.tag.writeGate.close()
        h.model.run()
        await h.wait("the file is in work") { h.tag.writeGate.arrivals == 1 }
        h.model.appBecameActive()
        XCTAssertFalse(h.model.isScanning)
        await h.settle()
        XCTAssertEqual(h.tag.reads.count, 2, "the load, and the run's own scan")
        h.tag.writeGate.open()
        await h.runEnds()
        XCTAssertEqual(h.tag.reads.count, 3, "and the one scan after the run")
    }

    func testAScanOnActivateThatFailsShowsTheMessageOfAFailedScan() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))
        XCTAssertEqual(h.model.folderMessages, [])

        h.tag.failReads(true)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertEqual(h.model.folderMessages, [FolderText.unreadable])
        XCTAssertNil(h.model.snapshot)
        XCTAssertFalse(h.model.canRun)
    }

    // MARK: The factor

    func testTextInTheCustomFieldSelectsTheCustomFactor() throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        XCTAssertEqual(h.model.choice, .preset(SqueezeFactor(1.5)!), "with no saved factor")

        h.model.customText = "1.6"
        XCTAssertEqual(h.model.choice, .custom)
        XCTAssertEqual(h.model.factor, SqueezeFactor(1.6))

        h.model.select(SqueezeFactor(2)!)
        XCTAssertEqual(h.model.choice, .preset(SqueezeFactor(2)!))
        XCTAssertEqual(h.model.factor, SqueezeFactor(2))
    }

    func testAFactorThatIsNoFactorGetsTheRuleOfTheCoreAndNewTextTakesItAway() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))

        h.model.customText = "9"
        h.model.run()
        XCTAssertEqual(h.model.customError, "Enter a number from 1 to 4, with at most four decimal places.")
        XCTAssertEqual(h.model.customError, "Enter \(SqueezeFactor.ruleText).")
        XCTAssertEqual(h.model.phase, .idle)
        XCTAssertEqual(h.tag.writes, [])

        h.model.customText = "1.6"
        XCTAssertNil(h.model.customError)
    }

    // "1,5" breaks the rule, and the rule alone does not say how. The words
    // are the core's, so the command line tool says them too.
    func testAFactorWithACommaGetsTheRuleAndTheHintAboutThePeriod() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))

        h.model.customText = "1,5"
        h.model.run()
        XCTAssertEqual(h.model.customError, "Enter a number from 1 to 4, with at most four decimal places. "
            + "Use a period for the decimal point.")
        XCTAssertEqual(h.model.phase, .idle)
        XCTAssertEqual(h.tag.writes, [])
    }

    func testARunSavesItsFactorAndTheNextModelStartsWithIt() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))
        XCTAssertNil(h.savedFactor)
        h.model.customText = "1.6"
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.savedFactor, "1.6")
        XCTAssertEqual(h.saves, ["1.6"], "one run, one save")
        XCTAssertEqual(h.tag.writes, ["1.6 1 a.dng"])

        let next = h.makeModel()
        XCTAssertEqual(next.choice, .custom)
        XCTAssertEqual(next.customText, "1.6")

        h.savedFactor = "2"
        XCTAssertEqual(h.makeModel().choice, .preset(SqueezeFactor(2)!))
        h.savedFactor = "not a factor"
        XCTAssertEqual(h.makeModel().choice, .preset(SqueezeFactor(1.5)!))
    }

    // A run that did not start saves nothing (design 13.9): another run
    // works in the folder, and this one read no file. Until 2026-10-10 the
    // click saved the factor before the run was refused.
    func testARunThatWasRefusedSavesNoFactor() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        let folder = try h.folder("Shoot", files: ["a.dng"])
        await h.load(folder)
        guard case .held(let other) = FolderLock.system.take(folder) else { return XCTFail("the lock of the test") }
        defer { other.release() }

        h.model.customText = "1.6"
        h.model.run()
        await h.runEnds()
        XCTAssertNotNil(h.model.runRefusal)
        XCTAssertEqual(h.saves, [], "the run did not start")
        XCTAssertNil(h.savedFactor)
        XCTAssertEqual(h.makeModel().choice, .preset(SqueezeFactor(1.5)!), "the next launch has the factor of before")

        // The other run ended. This click starts a run, and that run saves.
        other.release()
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.set, 1)
        XCTAssertEqual(h.saves, ["1.6"])
    }

    // A run whose own scan failed tried no file. It saves nothing either.
    func testARunWhoseFolderCouldNotBeReadSavesNoFactor() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))
        h.tag.failReads(true)
        h.model.select(SqueezeFactor(2)!)
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.folderMessages, [FolderText.unreadable])
        XCTAssertEqual(h.saves, [])
    }

    // Remove has no factor of its own to keep.
    func testRemoveSavesNoFactor() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))
        h.model.remove()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.set, 1)
        XCTAssertEqual(h.saves, [])
    }

    // A run that a quit stopped did start, so its factor is saved, once,
    // before the quit path returns: the app ends right after it.
    func testARunThatAQuitStoppedSavesItsFactorBeforeTheQuitPathReturns() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng", "b.dng"]))
        h.tag.writeGate.close()
        h.model.select(SqueezeFactor(2)!)
        h.model.run()
        await h.wait("the first file is in work") { h.tag.writeGate.arrivals == 1 }
        XCTAssertEqual(h.saves, [], "the run has not said yet that it started")

        XCTAssertEqual(h.model.answerQuit(), .afterRun)
        let returned = Flag()
        // What is saved at the moment the quit path returns. Nothing
        // awaits this task, so a quit path that never returns fails the
        // bounded wait below.
        var savedAtTheReturn: [String]?
        Task {
            await h.model.stopRunForQuit()
            savedAtTheReturn = h.saves
            returned.isSet = true
        }
        await h.settle()
        XCTAssertEqual(h.saves, [], "the job is still in its file")
        h.tag.writeGate.open()
        await h.wait("the quit path returns") { returned.isSet }
        XCTAssertEqual(savedAtTheReturn, ["2"])
        await h.settle()
        XCTAssertEqual(h.saves, ["2"], "one run, one save")
    }

    // MARK: The tools

    func testWithNoExiftoolTheWindowSaysSoAndScansNothing() async throws {
        let h = try ModelHarness(hasExiftool: false)
        defer { h.cleanUp() }
        XCTAssertTrue(h.model.exiftoolMissing)
        XCTAssertTrue(h.model.handleDrop([try h.folder("Shoot", files: ["a.dng"])]))
        await h.settle()
        XCTAssertFalse(h.model.isScanning)
        XCTAssertEqual(h.tag.reads, [])
        XCTAssertFalse(h.model.canRun)
    }

    // MARK: The converters (design 13.5)

    private static let adobeIsOptional =
        "Adobe DNG Converter is not installed. It is an optional backup for photos that dnglab cannot match."
    private static let dnglabIsFaster = "dnglab is faster and opens no window. Install it with: brew install dnglab"

    /// A model with these converters, and a folder with one DNG and one
    /// pending ARW loaded in it.
    private func loaded(dnglab: Bool, adobe: Bool, files: [String] = ["a.dng", "b.ARW"]) async throws -> ModelHarness {
        let h = try ModelHarness(dnglab: dnglab ? FakeConverter() : nil, adobe: adobe ? FakeConverter() : nil)
        await h.load(try h.folder("Shoot", files: files))
        return h
    }

    func testWithBothConvertersTheWindowSaysNothingExtra() async throws {
        let h = try await loaded(dnglab: true, adobe: true)
        defer { h.cleanUp() }
        XCTAssertEqual(h.model.countsLine, "1 DNG · 1 ARW to convert")
        XCTAssertNil(h.model.converterAdvice)
        XCTAssertFalse(h.model.arwsCannotConvert)
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")
    }

    func testWithDnglabAloneTheWindowSaysQuietlyThatAdobeIsAnOptionalBackup() async throws {
        let h = try await loaded(dnglab: true, adobe: false)
        defer { h.cleanUp() }
        XCTAssertEqual(h.model.countsLine, "1 DNG · 1 ARW to convert")
        XCTAssertEqual(h.model.converterAdvice, Self.adobeIsOptional)
        XCTAssertFalse(h.model.arwsCannotConvert, "every ARW converts: the line is a quiet one")
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")
        XCTAssertEqual(h.model.folderMessages, [], "the advice is no message that needs attention")
    }

    func testWithAdobeAloneTheWindowSaysQuietlyThatDnglabIsFaster() async throws {
        let h = try await loaded(dnglab: false, adobe: true)
        defer { h.cleanUp() }
        XCTAssertEqual(h.model.countsLine, "1 DNG · 1 ARW to convert")
        XCTAssertEqual(h.model.converterAdvice, Self.dnglabIsFaster)
        XCTAssertFalse(h.model.arwsCannotConvert)
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")
        XCTAssertEqual(h.model.folderMessages, [])
    }

    // The one state in which the lines are no quiet ones: the ARW files
    // wait. The counts line gets the warning symbol and the install line the
    // information symbol with primary text (design 13.5). The model hands
    // over the two lines and `arwsCannotConvert`; only the view decides the
    // symbols, so no model test can pin them.
    func testWithNeitherConverterTheWindowSaysThatTheARWFilesCannotConvertAndHowToInstallDnglab() async throws {
        let h = try await loaded(dnglab: false, adobe: false)
        defer { h.cleanUp() }
        XCTAssertEqual(h.model.countsLine, "1 DNG · 1 ARW cannot be converted: no converter is installed")
        XCTAssertEqual(h.model.converterAdvice, "Install dnglab with: brew install dnglab")
        XCTAssertTrue(h.model.arwsCannotConvert)
        XCTAssertEqual(h.model.runLabel, "Desqueeze 1 photo", "the ARW is not in the count")
        XCTAssertTrue(h.model.canRun, "the DNG still runs")
    }

    // The lines are about the ARW files that wait. With none, nothing shows.
    func testWithNoPendingARWNoLineAboutTheConvertersShowsInAnyState() async throws {
        for (dnglab, adobe) in [(true, true), (true, false), (false, true), (false, false)] {
            let h = try await loaded(dnglab: dnglab, adobe: adobe, files: ["a.dng"])
            defer { h.cleanUp() }
            XCTAssertEqual(h.model.countsLine, "1 DNG", "dnglab \(dnglab), Adobe \(adobe)")
            XCTAssertNil(h.model.converterAdvice, "dnglab \(dnglab), Adobe \(adobe)")
            XCTAssertFalse(h.model.arwsCannotConvert, "dnglab \(dnglab), Adobe \(adobe)")
        }
    }

    // Before the first scan, and with no folder, there is nothing to say.
    func testWithNoFolderThereIsNoLineAboutTheConverters() throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        XCTAssertNil(h.model.converterAdvice)
        XCTAssertFalse(h.model.arwsCannotConvert)
    }

    // The advice goes away when the run has converted the ARW: the scan
    // after the run finds no pending file.
    func testAfterARunThatConvertedTheARWTheAdviceIsGone() async throws {
        let h = try await loaded(dnglab: true, adobe: false)
        defer { h.cleanUp() }
        XCTAssertNotNil(h.model.converterAdvice)

        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.convertedByDnglab, 1)
        XCTAssertEqual(h.model.countsLine, "2 DNG")
        XCTAssertNil(h.model.converterAdvice)
    }

    // dnglab alone, and a frame with no full match (design 13.4). The file
    // is converted. Its note informs, and the result keeps its "done" mark.
    // MARK: The lines under the counts of a result (design 4.4)

    // One ARW has a full match, so dnglab gets it. The other has none, so
    // Adobe DNG Converter gets it. The window then says how many each
    // converted, with the line that the command line tool prints.
    func testAfterARunInWhichBothConvertersWorkedTheResultSaysHowManyEachConverted() async throws {
        let h = try ModelHarness(dnglab: FakeConverter(), adobe: FakeConverter(),
                                 facts: ["a.ARW": FakeFacts.fullMatch])
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.ARW", "b.ARW"]))
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.countsLine, "2 converted · 2 set · 0 skipped · 0 failed")
        XCTAssertEqual(h.model.summary?.convertersLine, "Converted with dnglab: 1. With Adobe DNG Converter: 1.")
    }

    func testAfterARunInWhichOneConverterWorkedTheResultHasNoLineAboutTheConverters() async throws {
        let h = try await loaded(dnglab: false, adobe: true)
        defer { h.cleanUp() }
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.converted, 1)
        XCTAssertNil(h.model.summary?.convertersLine)
    }

    // The Lightroom line is for a run that set a photo. A run that set
    // nothing does not show it, as in the command line tool.
    func testTheLightroomLineShowsOnlyAfterARunThatSetAPhoto() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.set, 1)
        XCTAssertEqual(h.model.summary?.lightroomLine,
                       "Photos already in Lightroom: Metadata › Read Metadata from File.")

        // The second run finds the photo at the factor, and sets nothing.
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.countsLine, "0 set · 1 skipped · 0 failed")
        XCTAssertNil(h.model.summary?.lightroomLine, "a run that set nothing")
    }

    func testAResultWithOnlyNotesOfADNGWithNoFullMatchDoesNotNeedAttention() async throws {
        let h = try ModelHarness(dnglab: FakeConverter(unmatched: .noLensCorrection))
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["b.ARW", "c.ARW"]))

        h.model.run()
        await h.runEnds()
        let summary = try XCTUnwrap(h.model.summary)
        XCTAssertEqual([summary.convertedByDnglab, summary.set, summary.failed, summary.blocked], [2, 2, 0, 0])
        XCTAssertEqual(summary.notes.map(\.kind), [.convertedUnmatched, .convertedUnmatched])
        XCTAssertEqual(summary.notes.map(\.name), ["b.dng", "c.dng"])
        XCTAssertFalse(summary.needsAttention)
        XCTAssertFalse(summary.cancelled)
        XCTAssertEqual(summary.notes.map(AppModel.isInformation), [true, true])
    }

    // Only three kinds of note inform: a DNG with no full match, an
    // original that stays (design 14.3), and a volume that gives no folder
    // lock (design 13.9). Every other kind is a file to look at.
    func testOnlyTheThreeKindsOfNoteThatInformAreInformation() {
        for kind in FileNote.Kind.allCases {
            let note = FileNote(name: "a.dng", kind: kind, message: "A sentence.", detail: nil)
            XCTAssertEqual(AppModel.isInformation(note),
                           kind == .convertedUnmatched || kind == .originalKept || kind == .noFolderLock, "\(kind)")
        }
    }

    // MARK: The launch arguments

    func testSimulateMissingAdobeHidesAdobeDNGConverterAlone() {
        let options = LaunchOptions(arguments: ["simulateMissingAdobe": "YES"])
        XCTAssertTrue(options.hidesAdobe)
        XCTAssertFalse(options.hidesDnglab, "dnglab is there, so a converter is there")
        XCTAssertFalse(options.hidesExiftool)
        XCTAssertNil(options.openFolder)
    }

    func testSimulateMissingDnglabHidesDnglabAlone() {
        let options = LaunchOptions(arguments: ["simulateMissingDnglab": "YES"])
        XCTAssertTrue(options.hidesDnglab)
        XCTAssertFalse(options.hidesAdobe, "Adobe DNG Converter is there, so a converter is there")
        XCTAssertFalse(options.hidesExiftool)
    }

    // The window with exiftool and with neither converter is the two
    // arguments together. No third argument hides both.
    func testTheTwoArgumentsTogetherHideBothConvertersAndNotExiftool() {
        let options = LaunchOptions(arguments: ["simulateMissingAdobe": "YES", "simulateMissingDnglab": "YES"])
        XCTAssertTrue(options.hidesAdobe)
        XCTAssertTrue(options.hidesDnglab)
        XCTAssertFalse(options.hidesExiftool)
    }

    func testSimulateMissingToolsHidesEveryTool() {
        let options = LaunchOptions(arguments: ["simulateMissingTools": "YES"])
        XCTAssertTrue(options.hidesAdobe)
        XCTAssertTrue(options.hidesDnglab)
        XCTAssertTrue(options.hidesExiftool)
    }

    func testWithNoLaunchArgumentNoToolIsHiddenAndNoFolderLoads() {
        let off: [String: Any] = ["simulateMissingTools": "NO", "simulateMissingAdobe": "NO",
                                  "simulateMissingDnglab": "NO"]
        // An argument that the app does not have hides nothing. The app had
        // `-simulateMissingConverter` once.
        let unknown: [String: Any] = ["simulateMissingConverter": "YES"]
        for arguments: [String: Any] in [[:], off, unknown] {
            let options = LaunchOptions(arguments: arguments)
            XCTAssertFalse(options.hidesAdobe)
            XCTAssertFalse(options.hidesDnglab)
            XCTAssertFalse(options.hidesExiftool)
            XCTAssertNil(options.openFolder)
        }
        XCTAssertEqual(LaunchOptions(arguments: ["openFolder": "/tmp/Shoot 1"]).openFolder, "/tmp/Shoot 1")
    }
}

/// A mark that a task sets and the test reads.
@MainActor
private final class Flag {
    var isSet = false
}
