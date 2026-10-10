import AppKit
import DesqueezeCore
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

    func testARunSavesItsFactorAndTheNextModelStartsWithIt() async throws {
        let h = try ModelHarness()
        defer { h.cleanUp() }
        await h.load(try h.folder("Shoot", files: ["a.dng"]))
        XCTAssertNil(h.savedFactor)
        h.model.customText = "1.6"
        h.model.run()
        XCTAssertEqual(h.savedFactor, "1.6")
        await h.runEnds()
        XCTAssertEqual(h.tag.writes, ["1.6 1 a.dng"])

        let next = h.makeModel()
        XCTAssertEqual(next.choice, .custom)
        XCTAssertEqual(next.customText, "1.6")

        h.savedFactor = "2"
        XCTAssertEqual(h.makeModel().choice, .preset(SqueezeFactor(2)!))
        h.savedFactor = "not a factor"
        XCTAssertEqual(h.makeModel().choice, .preset(SqueezeFactor(1.5)!))
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
    // wait, so both show as the read-only message shows.
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

    // Only that kind of note informs. Every other kind is a file to look at.
    func testOnlyTheNoteOfADNGWithNoFullMatchIsInformation() {
        for kind in FileNote.Kind.allCases {
            let note = FileNote(name: "a.dng", kind: kind, message: "A sentence.", detail: nil)
            XCTAssertEqual(AppModel.isInformation(note), kind == .convertedUnmatched, "\(kind)")
        }
    }

    // MARK: The launch arguments

    // "The converter" is both converters: dnglab, and Adobe DNG Converter.
    func testSimulateMissingConverterHidesBothConvertersAndNotExiftool() {
        let options = LaunchOptions(arguments: ["simulateMissingConverter": "YES"])
        XCTAssertTrue(options.hidesConverter)
        XCTAssertTrue(options.hidesAdobe)
        XCTAssertTrue(options.hidesDnglab)
        XCTAssertFalse(options.hidesExiftool)
        XCTAssertNil(options.openFolder)
    }

    func testSimulateMissingAdobeHidesAdobeDNGConverterAlone() {
        let options = LaunchOptions(arguments: ["simulateMissingAdobe": "YES"])
        XCTAssertTrue(options.hidesAdobe)
        XCTAssertFalse(options.hidesDnglab)
        XCTAssertFalse(options.hidesConverter, "dnglab is there, so a converter is there")
        XCTAssertFalse(options.hidesExiftool)
    }

    func testSimulateMissingDnglabHidesDnglabAlone() {
        let options = LaunchOptions(arguments: ["simulateMissingDnglab": "YES"])
        XCTAssertTrue(options.hidesDnglab)
        XCTAssertFalse(options.hidesAdobe)
        XCTAssertFalse(options.hidesConverter, "Adobe DNG Converter is there, so a converter is there")
        XCTAssertFalse(options.hidesExiftool)
    }

    func testTheTwoArgumentsTogetherHideBothConverters() {
        let options = LaunchOptions(arguments: ["simulateMissingAdobe": "YES", "simulateMissingDnglab": "YES"])
        XCTAssertTrue(options.hidesConverter)
        XCTAssertFalse(options.hidesExiftool)
    }

    func testSimulateMissingToolsHidesEveryTool() {
        let options = LaunchOptions(arguments: ["simulateMissingTools": "YES"])
        XCTAssertTrue(options.hidesConverter)
        XCTAssertTrue(options.hidesAdobe)
        XCTAssertTrue(options.hidesDnglab)
        XCTAssertTrue(options.hidesExiftool)
    }

    func testWithNoLaunchArgumentNoToolIsHiddenAndNoFolderLoads() {
        let off: [String: Any] = ["simulateMissingConverter": "NO", "simulateMissingTools": "NO",
                                  "simulateMissingAdobe": "NO", "simulateMissingDnglab": "NO"]
        for arguments: [String: Any] in [[:], off] {
            let options = LaunchOptions(arguments: arguments)
            XCTAssertFalse(options.hidesConverter)
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
