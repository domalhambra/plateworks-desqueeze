import AppKit
import DesqueezeCore
import XCTest

/// The box "Move the original ARW files to the Trash" (design 14.4). Each
/// test has its own model, on fakes and on temporary folders. The fake
/// backups keep a list: no file moves, and nothing reaches the Trash.
@MainActor
final class OriginalsModelTests: XCTestCase {
    private var afterTheDoubleClickTime: TimeInterval { NSEvent.doubleClickInterval + 0.01 }

    /// A model with Adobe DNG Converter, and a folder loaded in it.
    ///
    /// - Parameter failing: the ARW files that the converter cannot convert.
    ///   After a run, such an ARW is still pending, so the box still shows.
    private func loaded(files: [String] = ["a.dng", "b.ARW"], adobe: Bool = true,
                        failing: Set<String> = [], gate: Gate? = nil) async throws -> ModelHarness {
        let h = try ModelHarness(adobe: adobe ? FakeConverter(failing: failing, gate: gate) : nil)
        await h.load(try h.folder("Shoot", files: files))
        return h
    }

    // MARK: When the box shows

    func testTheBoxIsOffAtTheStartAndDoesNotShowWithNoFolder() throws {
        let h = try ModelHarness(adobe: FakeConverter())
        defer { h.cleanUp() }
        XCTAssertFalse(h.model.trashOriginals)
        XCTAssertFalse(h.model.showsTrashOriginals)
        XCTAssertNil(h.model.trashOriginalsLine)
        h.model.setTrashOriginals(true)
        XCTAssertFalse(h.model.trashOriginals, "a box that does not show cannot be ticked")
    }

    func testTheBoxShowsForAFolderWithAPendingARWThatCanConvertAndIsOff() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        XCTAssertTrue(h.model.showsTrashOriginals)
        XCTAssertTrue(h.model.canChangeTrashOriginals)
        XCTAssertFalse(h.model.trashOriginals)
        XCTAssertNil(h.model.trashOriginalsLine, "the line shows only while the box is on")
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")
    }

    func testTheBoxDoesNotShowWithNoPendingARW() async throws {
        let h = try await loaded(files: ["a.dng", "b.dng"])
        defer { h.cleanUp() }
        XCTAssertFalse(h.model.showsTrashOriginals)
        h.model.setTrashOriginals(true)
        XCTAssertFalse(h.model.trashOriginals)
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")
    }

    // With no converter the ARW cannot convert, so no original can move.
    func testTheBoxDoesNotShowWhenNoConverterIsInstalled() async throws {
        let h = try await loaded(adobe: false)
        defer { h.cleanUp() }
        XCTAssertEqual(h.model.snapshot?.pendingARWs.count, 1)
        XCTAssertFalse(h.model.showsTrashOriginals)
        h.model.setTrashOriginals(true)
        XCTAssertFalse(h.model.trashOriginals)
    }

    // A run converts nothing in a read-only folder.
    func testTheBoxDoesNotShowForAReadOnlyFolder() async throws {
        let h = try ModelHarness(adobe: FakeConverter())
        defer { h.cleanUp() }
        let folder = try h.folder("Shoot", files: ["b.ARW"])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        await h.load(folder)
        XCTAssertEqual(h.model.snapshot?.isWritable, false)
        XCTAssertFalse(h.model.showsTrashOriginals)
        h.model.setTrashOriginals(true)
        XCTAssertFalse(h.model.trashOriginals)
    }

    /// A name that no converter takes: its base has 223 letters, one more
    /// than a conversion can name its files for (design 13.9).
    private let tooLong = String(repeating: "n", count: 223) + ".ARW"

    // The only pending ARW cannot convert, so the run can move no original.
    // The run button still takes the file: its note says what to do.
    func testTheBoxDoesNotShowWhenTheOnlyPendingARWHasANameThatIsTooLong() async throws {
        let h = try await loaded(files: ["a.dng", tooLong])
        defer { h.cleanUp() }
        XCTAssertEqual(h.model.snapshot?.pendingARWs.map(\.lastPathComponent), [tooLong])
        XCTAssertFalse(h.model.showsTrashOriginals)
        XCTAssertFalse(h.model.canChangeTrashOriginals)
        h.model.setTrashOriginals(true)
        XCTAssertFalse(h.model.trashOriginals)
        XCTAssertNil(h.model.trashOriginalsLine)
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")
        XCTAssertTrue(h.model.canRun)

        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.notes.map(\.detail), ["The file name is too long. Shorten it, then run again."])
        XCTAssertEqual(h.backups.filesGiven, [])
    }

    // One ARW can convert and one cannot: the line and the button count
    // the one that the run can move, and the run moves that one.
    func testTheLineAndTheButtonCountOnlyTheARWFilesThatCanConvert() async throws {
        let h = try await loaded(files: ["a.dng", "b.ARW", tooLong])
        defer { h.cleanUp() }
        XCTAssertTrue(h.model.showsTrashOriginals)
        h.model.setTrashOriginals(true)
        XCTAssertEqual(h.model.trashOriginalsLine,
                       "1 original ARW file goes to the Trash after its DNG file passes the check.")
        XCTAssertEqual(h.model.runLabel, "Desqueeze 3 photos, move 1 ARW to Trash")

        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.backups.filesGiven, ["b.ARW"])
        XCTAssertEqual(h.model.summary?.originalsLine, "Originals moved to the Trash: 1 of 1.")
        XCTAssertEqual(h.model.summary?.failed, 1)
        // The ARW that cannot convert is still pending, and it is no
        // original that a run can move: the box does not show.
        XCTAssertEqual(h.model.snapshot?.pendingARWs.map(\.lastPathComponent), [tooLong])
        XCTAssertFalse(h.model.showsTrashOriginals)
        XCTAssertFalse(h.model.trashOriginals)
    }

    // MARK: The line under the box, and the label of the Run button

    func testWhileTheBoxIsOnTheLineAndTheButtonSayWhatTheRunWillDoForOne() async throws {
        let h = try await loaded(files: ["a.dng", "b.ARW"])
        defer { h.cleanUp() }
        h.model.setTrashOriginals(true)
        XCTAssertTrue(h.model.trashOriginals)
        XCTAssertEqual(h.model.trashOriginalsLine,
                       "1 original ARW file goes to the Trash after its DNG file passes the check.")
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos, move 1 ARW to Trash")

        h.model.setTrashOriginals(false)
        XCTAssertNil(h.model.trashOriginalsLine)
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")
    }

    func testWhileTheBoxIsOnTheLineAndTheButtonSayWhatTheRunWillDoForMany() async throws {
        let h = try await loaded(files: ["a.dng", "b.ARW", "c.ARW", "d.ARW"])
        defer { h.cleanUp() }
        h.model.setTrashOriginals(true)
        XCTAssertEqual(h.model.trashOriginalsLine,
                       "3 original ARW files go to the Trash after their DNG files pass the check.")
        XCTAssertEqual(h.model.runLabel, "Desqueeze 4 photos, move 3 ARW to Trash")
        // The words are the core's.
        XCTAssertEqual(h.model.trashOriginalsLine, FolderText.trashOriginalsLine(count: 3))
        XCTAssertEqual(h.model.runLabel, FolderText.runLabel(count: 4, originalsToTrash: 3))
    }

    // MARK: The run gets the box, and the box is off after it

    // The first break to try: the option is treated as on when it is off.
    func testWithTheBoxOffARunGivesNoARWToTheTrash() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.converted, 1)
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(h.tag.originalChecks, [])
        XCTAssertEqual(h.model.summary?.trashOriginals, false)
        XCTAssertNil(h.model.summary?.originalsLine)
        XCTAssertEqual(h.announcements, ["1 converted · 2 set · 0 skipped · 0 failed"])
    }

    func testWithTheBoxOnARunMovesTheOriginalAndTheBoxIsOffAfterIt() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        h.model.setTrashOriginals(true)

        h.model.run()
        XCTAssertTrue(h.model.trashOriginals, "the box shows what the run in work does")
        XCTAssertFalse(h.model.canChangeTrashOriginals, "and it cannot change during the run")
        h.model.setTrashOriginals(false)
        XCTAssertTrue(h.model.trashOriginals)
        await h.runEnds()

        XCTAssertEqual(h.backups.filesGiven, ["b.ARW"])
        XCTAssertEqual(h.tag.originalChecks, ["b.dng"])
        XCTAssertFalse(h.model.trashOriginals, "off after every run")
        XCTAssertEqual(h.model.summary?.originalsLine, "Originals moved to the Trash: 1 of 1.")
        // VoiceOver hears the counts, then the line of the core.
        XCTAssertEqual(h.announcements,
                       ["1 converted · 2 set · 0 skipped · 0 failed. Originals moved to the Trash: 1 of 1."])
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")

        // The next run moves nothing: the box was not ticked again.
        let shoot = try XCTUnwrap(h.model.folder)
        try h.touch("c.ARW", in: shoot)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertTrue(h.model.showsTrashOriginals)
        XCTAssertFalse(h.model.trashOriginals)
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.summary?.converted, 1)
        XCTAssertEqual(h.backups.filesGiven, ["b.ARW"], "no second original")
    }

    // One ARW cannot convert, so it is still pending after the run, and the
    // box still shows. It must be off: nothing but the end of the run turns
    // it off here.
    func testTheBoxIsOffAfterARunThatLeftAPendingARWAndStillShows() async throws {
        let h = try await loaded(files: ["a.dng", "b.ARW", "bad.ARW"], failing: ["bad.ARW"])
        defer { h.cleanUp() }
        h.model.setTrashOriginals(true)
        XCTAssertEqual(h.model.runLabel, "Desqueeze 3 photos, move 2 ARW to Trash")

        h.model.run()
        await h.runEnds()

        XCTAssertEqual(h.model.summary?.failed, 1)
        XCTAssertEqual(h.backups.filesGiven, ["b.ARW"], "the ARW whose conversion failed stays")
        XCTAssertEqual(h.model.summary?.originalsLine, "Originals moved to the Trash: 1 of 1.")
        XCTAssertEqual(h.model.snapshot?.pendingARWs.map(\.lastPathComponent), ["bad.ARW"])
        XCTAssertTrue(h.model.showsTrashOriginals, "the box still shows")
        XCTAssertFalse(h.model.trashOriginals, "and it is off after the run")
        XCTAssertEqual(h.model.runLabel, "Desqueeze 3 photos")
    }

    func testTheBoxIsOffAfterACancelledRun() async throws {
        let h = try await loaded(files: ["a.dng", "b.ARW", "c.ARW"])
        defer { h.cleanUp() }
        h.model.setTrashOriginals(true)
        h.tag.writeGate.close()
        h.model.run()
        await h.wait("the first tag is in work") { h.tag.writeGate.arrivals == 1 }
        h.time += afterTheDoubleClickTime
        h.model.cancel()
        h.tag.writeGate.open()
        await h.runEnds()

        XCTAssertEqual(h.model.summary?.cancelled, true)
        XCTAssertEqual(h.backups.filesGiven, [], "a cancel before the fifth step moves nothing")
        XCTAssertFalse(h.model.trashOriginals, "off after a run that was cancelled")
        XCTAssertEqual(h.announcements.last, "2 converted · 1 set · 0 skipped · 0 failed · stopped. "
            + "Originals moved to the Trash: 0 of 2.")
    }

    // The cancel comes during the first conversion. The second ARW is not
    // converted, so it is still pending, and the box still shows. It must be
    // off.
    func testTheBoxIsOffAfterARunThatWasCancelledDuringAConversion() async throws {
        let gate = Gate()
        let h = try await loaded(files: ["b.ARW", "c.ARW"], gate: gate)
        defer {
            gate.open()
            h.cleanUp()
        }
        h.model.setTrashOriginals(true)
        gate.close()
        h.model.run()
        await h.wait("the first conversion is in work") { gate.arrivals == 1 }
        h.time += afterTheDoubleClickTime
        h.model.cancel()
        gate.open()
        await h.runEnds()

        XCTAssertEqual(h.model.summary?.cancelled, true)
        XCTAssertEqual(h.model.summary?.converted, 1)
        XCTAssertEqual(h.backups.filesGiven, [], "no original moves after a cancel")
        XCTAssertEqual(h.model.snapshot?.pendingARWs.map(\.lastPathComponent), ["c.ARW"])
        XCTAssertTrue(h.model.showsTrashOriginals, "the box still shows")
        XCTAssertFalse(h.model.trashOriginals, "and it is off after the cancelled run")
    }

    // The run's own scan fails, so the run did no work.
    func testTheBoxIsOffAfterARunThatFailed() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        h.model.setTrashOriginals(true)
        h.tag.failReads(true)
        h.model.run()
        await h.runEnds()
        XCTAssertNil(h.model.summary)
        XCTAssertFalse(h.model.trashOriginals)
        XCTAssertEqual(h.backups.filesGiven, [])
    }

    // Another run holds the folder, so this one did not start.
    func testTheBoxIsOffAfterARunThatDidNotStart() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        let folder = try XCTUnwrap(h.model.folder)
        guard case .held(let other) = FolderLock.system.take(folder) else { return XCTFail("the lock of the test") }
        defer { other.release() }
        h.model.setTrashOriginals(true)
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.model.folderMessages, [FolderLock.busyMessage])
        XCTAssertTrue(h.model.showsTrashOriginals)
        XCTAssertFalse(h.model.trashOriginals)
        XCTAssertEqual(h.backups.filesGiven, [])
    }

    // The Remove button is not affected: it moves no original.
    func testRemoveMovesNoOriginalWithTheBoxOn() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        h.model.setTrashOriginals(true)
        h.model.remove()
        await h.runEnds()
        XCTAssertEqual(h.tag.writes, ["1 1 a.dng"])
        XCTAssertEqual(h.backups.filesGiven, [])
        XCTAssertEqual(h.model.summary?.trashOriginals, false)
        XCTAssertNil(h.model.summary?.originalsLine)
        XCTAssertFalse(h.model.trashOriginals, "off after every run, and Remove is one")
    }

    // MARK: Another folder, and a scan of the same folder

    func testTheBoxIsOffWhenAnotherFolderLoadsAndWhenTheSameFolderLoadsAgain() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        let shoot = try XCTUnwrap(h.model.folder)
        h.model.setTrashOriginals(true)

        await h.load(try h.folder("Other", files: ["x.ARW", "y.ARW"]))
        XCTAssertTrue(h.model.showsTrashOriginals, "the new folder has pending ARW files too")
        XCTAssertFalse(h.model.trashOriginals)
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")

        h.model.setTrashOriginals(true)
        await h.load(shoot)
        XCTAssertFalse(h.model.trashOriginals)
        h.model.setTrashOriginals(true)
        await h.load(shoot)
        XCTAssertFalse(h.model.trashOriginals, "also for the folder that was loaded already")
    }

    // A scan of the same folder when the app becomes active again does not
    // change the box. While that scan is in work, the box cannot change.
    func testAScanOfTheSameFolderKeepsTheBoxAndTheBoxCannotChangeDuringIt() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        let shoot = try XCTUnwrap(h.model.folder)
        h.model.setTrashOriginals(true)

        try h.touch("c.ARW", in: shoot)
        h.tag.readGate("Shoot").close()
        h.model.appBecameActive()
        XCTAssertTrue(h.model.isScanning)
        XCTAssertTrue(h.model.trashOriginals, "the scan does not change the box")
        XCTAssertFalse(h.model.canChangeTrashOriginals)
        h.model.setTrashOriginals(false)
        XCTAssertTrue(h.model.trashOriginals, "and the box cannot change while a scan is in work")
        XCTAssertFalse(h.model.canRun, "no run starts on counts that are not current")
        h.tag.readGate("Shoot").open()
        await h.wait("the scan lands") { !h.model.isScanning }

        XCTAssertTrue(h.model.trashOriginals, "kept by a scan of the same folder")
        XCTAssertEqual(h.model.trashOriginalsLine,
                       "2 original ARW files go to the Trash after their DNG files pass the check.")
        XCTAssertEqual(h.model.runLabel, "Desqueeze 3 photos, move 2 ARW to Trash")

        // The same model with the box off: the scan leaves it off.
        h.model.setTrashOriginals(false)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertFalse(h.model.trashOriginals)
    }

    // The folder has no pending ARW after the scan: the box does not show,
    // so it is off.
    func testAScanThatFindsNoPendingARWTurnsTheBoxOff() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        let shoot = try XCTUnwrap(h.model.folder)
        h.model.setTrashOriginals(true)

        // Another program converts the ARW: its DNG claims it.
        try h.touch("b.dng", in: shoot)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertEqual(h.model.snapshot?.pendingARWs.count, 0)
        XCTAssertFalse(h.model.showsTrashOriginals)
        XCTAssertFalse(h.model.trashOriginals)
        XCTAssertEqual(h.model.runLabel, "Desqueeze 2 photos")
    }

    func testAScanThatFailsTurnsTheBoxOff() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        h.model.setTrashOriginals(true)
        h.tag.failReads(true)
        h.model.appBecameActive()
        await h.wait("the scan lands") { !h.model.isScanning }
        XCTAssertNil(h.model.snapshot)
        XCTAssertFalse(h.model.trashOriginals)
    }

    // MARK: Never saved, and no launch argument

    func testTheBoxIsNeverSavedAndTheNextModelStartsWithItOff() async throws {
        let h = try await loaded()
        defer { h.cleanUp() }
        h.model.setTrashOriginals(true)
        XCTAssertEqual(h.saves, [], "a click on the box saves nothing")
        h.model.run()
        await h.runEnds()
        XCTAssertEqual(h.saves, ["1.5"], "a run saves its factor, and nothing else")
        XCTAssertEqual(h.savedFactor, "1.5")

        // The next launch: a model from what the last one saved.
        let next = h.makeModel()
        XCTAssertFalse(next.trashOriginals)
        XCTAssertFalse(next.showsTrashOriginals)
    }

    // No launch argument turns the box on: the launch options have no such
    // field, and an argument with a likely name changes nothing.
    func testNoLaunchArgumentTurnsTheBoxOn() {
        let options = LaunchOptions(arguments: ["trashOriginals": "YES", "moveOriginals": "YES",
                                                "openFolder": "/tmp/Shoot 1"])
        XCTAssertEqual(options, LaunchOptions(arguments: ["openFolder": "/tmp/Shoot 1"]))
        let fields = Mirror(reflecting: options).children.compactMap(\.label).sorted()
        XCTAssertEqual(fields, ["hidesAdobe", "hidesDnglab", "hidesExiftool", "openFolder"])
    }

    // MARK: What VoiceOver hears

    func testTheAnnouncementHasTheLineOfTheCoreOnlyAfterARunThatWasAskedToMoveTheOriginals() {
        var summary = RunSummary()
        summary.convertedByDnglab = 12
        summary.set = 12
        XCTAssertEqual(AppModel.announcement(summary), "12 converted · 12 set · 0 skipped · 0 failed")
        summary.trashOriginals = true
        summary.originalsInTrash = 11
        XCTAssertEqual(AppModel.announcement(summary),
                       "12 converted · 12 set · 0 skipped · 0 failed. Originals moved to the Trash: 11 of 12.")
        XCTAssertEqual(AppModel.announcement(summary), "\(summary.countsLine). \(summary.originalsLine ?? "")")
    }
}
