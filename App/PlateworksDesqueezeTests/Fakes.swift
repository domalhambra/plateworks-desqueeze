import Combine
import DesqueezeCore
import Foundation
import XCTest

// The fakes of the window's tests. The core's fakes are in
// `Tests/DesqueezeCoreTests/Fakes.swift`, and an Xcode target cannot see
// them. No fake here starts a tool, and none reaches the Trash.

/// A door that a fake goes through. While it is closed, each caller waits at
/// it, so a test can hold a scan or a run open. `open` lets every caller
/// through, also the ones that come later, so a test that fails cannot hang.
final class Gate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isOpen = true
    private var count = 0

    /// How many callers have come to the gate, open or closed.
    var arrivals: Int {
        condition.lock()
        defer { condition.unlock() }
        return count
    }

    func close() {
        condition.lock()
        isOpen = false
        condition.unlock()
    }

    func open() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }

    /// For the fake: counts the caller, and waits while the gate is closed.
    func pass() {
        condition.lock()
        count += 1
        while !isOpen { condition.wait() }
        condition.unlock()
    }
}

/// Acts like exiftool on a folder of empty files. It knows no tag until it
/// has written one, so the first run writes every DNG.
final class FakeTag: ScaleTagging, @unchecked Sendable {
    /// Holds each write.
    let writeGate = Gate()

    private let lock = NSLock()
    private var readGates: [String: Gate] = [:]
    private var folderReads: [String] = []
    private var fileWrites: [String] = []
    private var written: [String: SqueezeFactor] = [:]
    private var readsFail = false

    /// The gate that holds the read of the folder with this name.
    func readGate(_ folderName: String) -> Gate {
        lock.lock()
        defer { lock.unlock() }
        if let gate = readGates[folderName] { return gate }
        let gate = Gate()
        readGates[folderName] = gate
        return gate
    }

    /// The name of each folder that was read, in order. One for each scan of
    /// a folder that holds a DNG.
    var reads: [String] {
        lock.lock()
        defer { lock.unlock() }
        return folderReads
    }

    /// Each write, in order: `1.5 1 a.dng`.
    var writes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return fileWrites
    }

    /// True makes each read of a folder fail, as when exiftool cannot start.
    func failReads(_ fail: Bool) {
        lock.lock()
        readsFail = fail
        lock.unlock()
    }

    /// Opens every gate, so nothing waits when the test is over.
    func openEveryGate() {
        lock.lock()
        let gates = Array(readGates.values)
        lock.unlock()
        gates.forEach { $0.open() }
        writeGate.open()
    }

    func readFolder(_ folder: URL) throws -> [TagRow] {
        lock.lock()
        folderReads.append(folder.lastPathComponent)
        lock.unlock()
        readGate(folder.lastPathComponent).pass()
        lock.lock()
        defer { lock.unlock() }
        if readsFail { throw TagError.toolFailed("Error: the fake cannot read this folder") }
        // No row: each scale is unknown, and the job tries each write.
        return []
    }

    func write(_ factor: SqueezeFactor, to file: URL) throws {
        lock.lock()
        fileWrites.append("\(factor.tagValue) \(file.lastPathComponent)")
        lock.unlock()
        writeGate.pass()
        lock.lock()
        written[file.path] = factor
        lock.unlock()
    }

    func read(_ file: URL) throws -> Scale? {
        lock.lock()
        defer { lock.unlock() }
        return written[file.path].map { Scale(horizontal: $0.value, vertical: 1) }
    }
}

/// Backups that are only a list. Nothing goes to the Trash.
final class FakeBackups: BackupHandling, @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    /// The name of each DNG whose backup the job discarded, in order.
    var discarded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return names
    }

    func backupExists(for dng: URL) -> Bool { false }

    func trashBackup(for dng: URL) throws {
        lock.lock()
        names.append(dng.lastPathComponent)
        lock.unlock()
    }

    func restoreBackup(for dng: URL) throws {}
}

/// One model with its fakes, in temporary folders of its own.
@MainActor
final class ModelHarness {
    let tag = FakeTag()
    let backups = FakeBackups()
    /// What the model saved for the next launch. It is only this variable:
    /// no test reads or writes the defaults of a real app.
    var savedFactor: String?
    /// The time of the model's clock. A test moves it.
    var time: TimeInterval = 1_000
    /// Each line that the model said to VoiceOver.
    private(set) var announcements: [String] = []
    /// Each phase of the model, from the first.
    private(set) var phases: [AppModel.RunPhase] = []
    private(set) var model: AppModel!

    private let base: URL
    private var watch: AnyCancellable?

    /// - Parameter hasExiftool: false gives a model with no tag reader, as
    ///   on a Mac with no exiftool.
    init(hasExiftool: Bool = true) throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("desqueeze-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        model = makeModel(hasExiftool: hasExiftool)
        watch = model.$phase.removeDuplicates().sink { [weak self] in self?.phases.append($0) }
    }

    /// A model on this harness's fakes, with the factor that the model
    /// before it saved. The first one is `model`.
    ///
    /// The model does not keep the harness. A test that fails can end while
    /// its run is in flight, and that run must find nothing, not crash.
    func makeModel(hasExiftool: Bool = true) -> AppModel {
        AppModel(
            tag: hasExiftool ? tag : nil, converter: nil, backups: backups,
            savedFactor: savedFactor, saveFactor: { [weak self] in self?.savedFactor = $0 },
            now: { [weak self] in self?.time ?? 0 }, announce: { [weak self] in self?.announcements.append($0) })
    }

    func cleanUp() {
        tag.openEveryGate()
        watch = nil
        // Only the folder that this harness made.
        guard base.lastPathComponent.hasPrefix("desqueeze-app-tests-") else { return }
        try? FileManager.default.removeItem(at: base)
    }

    /// Makes a folder that holds one empty file for each name.
    func folder(_ name: String, files: [String] = []) throws -> URL {
        let folder = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files { try touch(file, in: folder) }
        return folder
    }

    func touch(_ name: String, in folder: URL) throws {
        try Data().write(to: folder.appendingPathComponent(name))
    }

    /// Loads `folder` as a drop does, and waits for its scan.
    func load(_ folder: URL, file: StaticString = #filePath, line: UInt = #line) async {
        XCTAssertTrue(model.handleDrop([folder]), "the drop was refused", file: file, line: line)
        await wait("the scan lands", file: file, line: line) { !self.model.isScanning }
    }

    /// Waits for the run to end: the phase is idle again.
    func runEnds(file: StaticString = #filePath, line: UInt = #line) async {
        await wait("the run ends", file: file, line: line) { self.model.phase == .idle }
    }

    /// Lets the model's tasks run until `condition` is true. Fails the test
    /// after five seconds.
    func wait(_ what: String, file: StaticString = #filePath, line: UInt = #line,
              until condition: () -> Bool) async {
        let limit = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < limit else {
                XCTFail("Waited five seconds for this: \(what)", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Gives the model time to do what it must not do. For a test that says
    /// "and then nothing happens".
    func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }
}
