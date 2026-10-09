import AppKit
import DesqueezeCore
import SwiftUI

/// The window's state. All file work is in `DesqueezeCore`. This type owns
/// the folder, the factor, and the one running job.
@MainActor
final class AppModel: ObservableObject {
    enum Choice: Equatable {
        case preset(SqueezeFactor)
        case custom
    }

    /// The loaded folder. Set at the moment of a load, before its scan.
    @Published private(set) var folder: URL?
    /// What the newest scan of `folder` found. Nil until that scan lands.
    @Published private(set) var snapshot: FolderSnapshot?
    /// True while the newest scan is in flight.
    @Published private(set) var isScanning = false
    /// True when the newest scan of `folder` failed.
    @Published private(set) var scanFailed = false
    /// "Drop a folder", after a wrong drop. It says nothing about the loaded
    /// folder, so it is apart from `folderMessages`.
    @Published private(set) var dropMessage: String?
    @Published var choice: Choice
    @Published var customText: String
    @Published var customError: String?
    @Published private(set) var progress: RunProgress?
    @Published private(set) var summary: RunSummary?
    /// True from the click on Run or Remove until the scan after the run has
    /// landed. So no click can act on counts from before the run.
    @Published private(set) var isRunning = false

    let exiftool: URL?
    let converter: URL?

    /// The job that is in flight: how to stop it, and how to wait for it.
    private var job: (cancel: CancelFlag, work: Task<RunSummary, Error>)?
    /// The number of the newest scan. A scan that lands with an older number
    /// is discarded.
    private var scanNumber = 0
    /// True after a quit has stopped a run. The app is about to end.
    private var isQuitting = false
    private static let factorKey = "lastFactor"

    init() {
        let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ToolLocator.converterBundleID)
        let locator = ToolLocator(registeredConverterApp: registered)
        // `-simulateMissingTools YES` on the command line shows the window as
        // it is on a Mac with neither tool. For checks by hand only.
        let simulateMissing = UserDefaults.standard.bool(forKey: "simulateMissingTools")
        exiftool = simulateMissing ? nil : locator.exiftool()
        converter = simulateMissing ? nil : locator.dngConverter()

        let saved = UserDefaults.standard.string(forKey: Self.factorKey).flatMap { SqueezeFactor(text: $0) }
            ?? SqueezeFactor(1.5)!
        if SqueezeFactor.presets.contains(saved) {
            choice = .preset(saved)
            customText = ""
        } else {
            choice = .custom
            customText = saved.label
        }

        // `-openFolder <path>` on the command line loads a folder at launch.
        // The standard Open panel runs in another process that a test script
        // cannot drive, so checks by hand and by script start here.
        if let path = UserDefaults.standard.string(forKey: "openFolder") {
            load(URL(fileURLWithPath: path))
        }
    }

    // MARK: What the view reads

    var factor: SqueezeFactor? {
        switch choice {
        case .preset(let preset): return preset
        case .custom: return SqueezeFactor(text: customText)
        }
    }

    var folderName: String? { folder?.lastPathComponent }

    /// For example `216 DNG · 12 ARW to convert`.
    var countsLine: String? {
        guard let snapshot else { return nil }
        if snapshot.isEmpty { return "No DNG or ARW files in this folder." }
        var parts = ["\(snapshot.dngs.count) DNG"]
        if !snapshot.pendingARWs.isEmpty {
            parts.append(converter == nil
                ? "\(snapshot.pendingARWs.count) ARW cannot be converted: Adobe DNG Converter is not installed"
                : "\(snapshot.pendingARWs.count) ARW to convert")
        }
        return parts.joined(separator: " · ")
    }

    /// The messages about the loaded folder. All come from the newest scan.
    var folderMessages: [String] {
        if scanFailed { return ["This folder could not be read."] }
        guard let snapshot else { return [] }
        var messages: [String] = []
        if !snapshot.isWritable {
            messages.append("This folder is read-only. Desqueeze cannot change its files.")
        }
        let orphans = snapshot.orphanBackups
        if orphans.count == 1 {
            let backup = orphans[0].lastPathComponent
            let photo = backup.dropLast("_original".count)
            messages.append("1 backup file has no DNG beside it. Rename \(backup) to \(photo) to get the photo back.")
        } else if orphans.count > 1 {
            messages.append("\(orphans.count) backup files have no DNG beside them. "
                + "Rename each one from <name>.dng_original to <name>.dng to get the photos back.")
        }
        return messages
    }

    /// The count in the run button: DNG files, plus ARW files that can convert.
    var runCount: Int {
        guard let snapshot else { return 0 }
        return snapshot.dngs.count + (converter == nil ? 0 : snapshot.pendingARWs.count)
    }

    var runLabel: String {
        switch runCount {
        case 0: return "Desqueeze"
        case 1: return "Desqueeze 1 photo"
        default: return "Desqueeze \(runCount) photos"
        }
    }

    var canRun: Bool { canChangeFiles && runCount > 0 }

    /// Remove never converts, so it needs a DNG.
    var canRemove: Bool { canChangeFiles && snapshot?.dngs.isEmpty == false }

    /// True when the counts are current and the folder accepts a write.
    private var canChangeFiles: Bool {
        !isScanning && !isRunning && snapshot?.isWritable == true
    }

    // MARK: Folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func handleDrop(_ urls: [URL]) -> Bool {
        guard !isRunning else { return false }
        guard urls.count == 1, let url = urls.first,
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            dropMessage = "Drop a folder"
            return false
        }
        load(url)
        return true
    }

    /// Makes `url` the loaded folder. Everything about the previous folder is
    /// gone at once, so the window never shows its counts under the new name.
    func load(_ url: URL) {
        guard !isRunning else { return }
        folder = url
        snapshot = nil
        scanFailed = false
        dropMessage = nil
        summary = nil
        progress = nil
        scan(url)
    }

    /// Starts a scan off the main thread. Scans can overlap: a second folder
    /// can load before the first scan lands. Only the newest scan is applied.
    @discardableResult
    private func scan(_ folder: URL) -> Task<Void, Never> {
        guard let exiftool else { return Task {} }
        scanNumber += 1
        let number = scanNumber
        isScanning = true
        let scanner = FolderScanner(tag: ScaleTag(exiftool: exiftool))
        return Task {
            let result = try? await Task.detached { try scanner.snapshot(of: folder) }.value
            guard number == scanNumber else { return }
            snapshot = result
            scanFailed = result == nil
            isScanning = false
        }
    }

    // MARK: Run

    func run() {
        guard canRun else { return }
        guard let factor else {
            customError = "Enter a number from 1 to 4, with at most four decimal places."
            return
        }
        customError = nil
        UserDefaults.standard.set(factor.label, forKey: Self.factorKey)
        start(factor: factor, convert: true)
    }

    func remove() {
        guard canRemove else { return }
        start(factor: .noStretch, convert: false)
    }

    func cancel() {
        job?.cancel.cancel()
    }

    /// For a quit during a run. Cancels the run and returns when its current
    /// file is complete. Returns at once when no file work is in flight.
    /// The caller must quit next: the window stays as it is, "running".
    func stopRunForQuit() async {
        isQuitting = true
        guard let job else { return }
        job.cancel.cancel()
        _ = await job.work.result
    }

    private func start(factor: SqueezeFactor, convert: Bool) {
        guard let folder, let exiftool else { return }
        let runner = DesqueezeJob(
            tag: ScaleTag(exiftool: exiftool),
            converter: converter.map { AdobeConverter(executable: $0) }
        )
        let flag = CancelFlag()
        // The job reports progress from its own thread. A stream keeps the
        // updates in order, and ends when the job returns.
        let (updates, updatesEnd) = AsyncStream.makeStream(of: RunProgress.self)
        let work = Task.detached {
            defer { updatesEnd.finish() }
            // The job scans the folder itself. It gets no counts from here.
            return try runner.run(folder: folder, factor: factor, convert: convert, cancel: flag) {
                updatesEnd.yield($0)
            }
        }
        job = (flag, work)
        isRunning = true
        summary = nil
        progress = nil

        Task {
            for await update in updates { progress = update }
            let result = try? await work.value
            job = nil
            // No scan for a window that is about to close: the scan would
            // leave an exiftool process behind the app.
            guard !isQuitting else { return }
            if result == nil {
                // The job's own scan failed, so no file was tried.
                snapshot = nil
                scanFailed = true
            } else {
                await scan(folder).value
            }
            // The result and the new counts arrive together.
            summary = result
            progress = nil
            isRunning = false
        }
    }
}
