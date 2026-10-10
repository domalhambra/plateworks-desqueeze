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

/// Acts like exiftool on a folder of empty files. `readFolder` gives a row
/// for each file that this fake wrote, with the scale that it wrote, as a
/// real scan reads it. A file that it never wrote has no row: its scale is
/// unknown, and a run writes it.
final class FakeTag: ScaleTagging, @unchecked Sendable {
    /// Holds each write.
    let writeGate = Gate()

    private let lock = NSLock()
    private var readGates: [String: Gate] = [:]
    private var folderReads: [String] = []
    private var fileWrites: [String] = []
    private var written: [String: SqueezeFactor] = [:]
    private var readsFail = false
    private var checked: [String] = []

    /// The name of each DNG that the check before an original moves read
    /// (design 14.2, line 5), in order.
    var originalChecks: [String] {
        lock.lock()
        defer { lock.unlock() }
        return checked
    }

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
        // A row for each file of this folder that was written. A file with
        // no row has an unknown scale, and the job tries its write.
        // Both paths with their links resolved: the scan can name a file
        // through `/private`, and the folder not.
        let here = folder.resolvingSymlinksInPath().path
        return written
            .filter { URL(fileURLWithPath: $0.key).deletingLastPathComponent().resolvingSymlinksInPath().path == here }
            .map { path, factor in
                TagRow(fileName: URL(fileURLWithPath: path).lastPathComponent,
                       scale: Scale(horizontal: factor.value, vertical: 1), originalRawFileName: nil)
            }
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

    /// The DNG names an ARW with its own base name, as each converter
    /// writes it, and holds the scale that this fake wrote.
    func readOriginalCheck(_ dng: URL) throws -> OriginalCheckTags {
        lock.lock()
        defer { lock.unlock() }
        checked.append(dng.lastPathComponent)
        return OriginalCheckTags(originalRawFileName: dng.deletingPathExtension().lastPathComponent + ".ARW",
                                 scale: written[dng.path].map { Scale(horizontal: $0.value, vertical: 1) })
    }
}

/// Backups that are only a list. Nothing goes to the Trash.
final class FakeBackups: BackupHandling, @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    private var files: [String] = []

    /// The name of each DNG whose backup the job discarded, in order.
    var discarded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return names
    }

    /// The name of each file that the job gave to `trashFile`, in order: an
    /// original on its way to the Trash (design 14.2). The file stays where
    /// it is: this fake moves nothing.
    var filesGiven: [String] {
        lock.lock()
        defer { lock.unlock() }
        return files
    }

    func backupExists(for dng: URL) -> Bool { false }

    func trashBackup(for dng: URL) throws {
        lock.lock()
        names.append(dng.lastPathComponent)
        lock.unlock()
    }

    func restoreBackup(for dng: URL) throws {}

    func trashFile(_ file: URL) throws {
        lock.lock()
        files.append(file.lastPathComponent)
        lock.unlock()
    }
}

/// Either converter. It makes a small DNG beside the ARW, and starts no
/// program. The DNG has bytes, as the check before an original moves asks
/// (design 14.2, line 5).
///
/// It follows the first rule of each real converter (design 13.9): an ARW
/// whose name is too long gets no DNG, and the next converter is not tried.
struct FakeConverter: RawConverter {
    /// The rule that kept the DNG from a full match, as dnglab reports it
    /// for a frame that the table does not cover. Nil is a full match.
    var unmatched: AdobeMatch.Rule?
    /// The names of the ARW files whose conversion fails. Such an ARW has no
    /// DNG after the run, so it is still pending.
    var failing: Set<String> = []
    /// Holds each conversion, when a test gives one.
    var gate: Gate?

    func convert(_ arw: URL, facts: ARWFacts) throws -> Conversion {
        gate?.pass()
        if ConverterOutput.nameIsTooLong(for: arw) {
            throw ConvertError.failedForAll("The file name is too long. Shorten it, then run again.")
        }
        if failing.contains(arw.lastPathComponent) { throw ConvertError.failed("The fake cannot read this file.") }
        let dng = ConverterOutput.url(for: arw)
        try Data("a DNG".utf8).write(to: dng)
        return Conversion(dng: dng, unmatched: unmatched)
    }
}

/// The facts of each ARW, as a test sets them. It starts no program.
struct FakeFacts: ARWFactsReading {
    /// The facts of a frame from an adapted lens at ISO 800: a full match,
    /// so dnglab gets the ARW.
    static let fullMatch = ARWFacts(
        model: "ILCE-7SM3", iso: 800, daylightLevels: ARWFacts.DaylightLevels(red: 2597, green: 1024, blue: 1556),
        distortionCorrection: ARWFacts.noCorrectionData, rawFileType: ARWFacts.compressedRaw)

    /// By ARW name. A name with no entry has no facts, and no full match.
    var facts: [String: ARWFacts]

    func read(_ arws: [URL]) -> [String: ARWFacts] { facts }
}

/// One model with its fakes, in temporary folders of its own.
@MainActor
final class ModelHarness {
    let tag = FakeTag()
    let backups = FakeBackups()
    /// What the model saved for the next launch. It is only this variable:
    /// no test reads or writes the defaults of a real app.
    var savedFactor: String?
    /// Every value that a model gave to its one way to save, in order. The
    /// model has no other way: the box of design 14.4 is never saved.
    private(set) var saves: [String] = []
    /// The time of the model's clock. A test moves it.
    var time: TimeInterval = 1_000
    /// Each line that the model said to VoiceOver.
    private(set) var announcements: [String] = []
    /// Each phase of the model, from the first.
    private(set) var phases: [AppModel.RunPhase] = []
    private(set) var model: AppModel!

    private let base: URL
    private let converters: RawConverters
    private let lock: FolderLock
    private var watch: AnyCancellable?

    /// - Parameters:
    ///   - hasExiftool: false gives a model with no tag reader, as on a Mac
    ///     with no exiftool.
    ///   - dnglab: the fake that stands for dnglab. Nil: it is not installed.
    ///   - adobe: the fake that stands for Adobe DNG Converter. Nil: it is
    ///     not installed.
    ///   - facts: the facts of each ARW, by name. Empty: no ARW has facts,
    ///     so none has a full match.
    ///   - lock: the lock that a run takes on the folder. The system's own,
    ///     on a temporary folder, unless a test gives one whose call fails.
    init(hasExiftool: Bool = true, dnglab: FakeConverter? = nil, adobe: FakeConverter? = nil,
         facts: [String: ARWFacts] = [:], lock: FolderLock = .system) throws {
        self.lock = lock
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("desqueeze-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // The reader of the facts is a fake too: no program starts.
        converters = RawConverters(dnglab: dnglab, adobe: adobe, facts: FakeFacts(facts: facts))
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
            tag: hasExiftool ? tag : nil, converters: converters, backups: backups, lock: lock,
            savedFactor: savedFactor,
            saveFactor: { [weak self] in
                self?.savedFactor = $0
                self?.saves.append($0)
            },
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
