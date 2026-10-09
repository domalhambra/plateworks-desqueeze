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

    /// Where the one job is, from the click on Run or Remove until the scan
    /// after the run has landed.
    enum RunPhase: Equatable {
        case idle
        /// The job is at work, and Cancel can stop it.
        case running
        /// Cancel was clicked. The job completes its current file.
        case stopping
        /// The job has returned. The scan after the run is in flight.
        case rescanning
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
    /// The newest step that the job completed. Nil before its first step.
    @Published private(set) var progress: RunProgress?
    @Published private(set) var summary: RunSummary?
    @Published private(set) var phase = RunPhase.idle

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
    private static let notAFolder = "Drop a folder"

    init() {
        let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ToolLocator.converterBundleID)
        let locator = ToolLocator(registeredConverterApp: registered)
        // The two launch hooks are read from the launch arguments only. A
        // value that `defaults write` saved must never hide the tools or
        // load a folder (design, section 9).
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        // `-simulateMissingTools YES` on the command line shows the window as
        // it is on a Mac with neither tool. For checks by hand only.
        let simulateMissing = (arguments["simulateMissingTools"] as? NSString)?.boolValue ?? false
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
        if let path = arguments["openFolder"] as? String {
            open(URL(fileURLWithPath: path))
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

    // The words and the counts about the folder are made in `DesqueezeCore`
    // (`FolderText`), so the window and the command line tool cannot say
    // different things. This type only hands them to the view.

    private var converterAvailable: Bool { converter != nil }

    /// For example `216 DNG · 12 ARW to convert`.
    var countsLine: String? { snapshot?.countsLine(converterAvailable: converterAvailable) }

    /// The messages about the loaded folder. All come from the newest scan.
    var folderMessages: [String] {
        if scanFailed { return ["This folder could not be read."] }
        return snapshot?.messages ?? []
    }

    /// The count in the run button: DNG files, plus ARW files that can convert.
    private var runCount: Int { snapshot?.runCount(converterAvailable: converterAvailable) ?? 0 }

    var runLabel: String { FolderText.runLabel(count: runCount) }

    /// The sentence about the ARW files a run left, with the reason when the
    /// converter is missing. Nil when the run left none.
    func unconvertedLine(_ summary: RunSummary) -> String? {
        summary.unconvertedARWsLine(converterAvailable: converterAvailable)
    }

    /// True from the click on Run or Remove until the scan after the run has
    /// landed. So no click can act on counts from before the run.
    var isRunning: Bool { phase != .idle }

    /// True when Cancel has nothing left to do: it was clicked, or the job
    /// has returned. The button then reads "Finishing…" and is off, so a
    /// second click on the same spot cannot start a run.
    var isFinishing: Bool { phase == .stopping || phase == .rescanning }

    /// The line under the progress bar. The job reports a file when its step
    /// is complete, so the name is the last file finished, not the one in
    /// work.
    var progressLine: String {
        switch phase {
        // Before the first step the job is in its scan or in its first
        // file, and this type cannot know which.
        case .stopping: return progress == nil ? "Stopping…" : "Stopping after the current file…"
        case .rescanning: return "Reading the folder…"
        case .idle, .running:
            guard let progress else { return "Starting…" }
            return "\(progress.completed) of \(progress.total) · last finished: \(progress.name)"
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
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func handleDrop(_ urls: [URL]) -> Bool {
        guard !isRunning else { return false }
        guard urls.count == 1, let url = urls.first else {
            dropMessage = Self.notAFolder
            return false
        }
        return open(url)
    }

    /// The one way in for a drop, the Open panel, and `-openFolder`. A link
    /// to a folder is that folder. A file, or a package such as an app or a
    /// photo library, is refused with a message, and the loaded folder stays.
    @discardableResult
    private func open(_ url: URL) -> Bool {
        guard !isRunning else { return false }
        guard let folder = FolderChoice.folder(at: url) else {
            dropMessage = Self.notAFolder
            return false
        }
        load(folder)
        return true
    }

    /// Makes `url` the loaded folder. Everything about the previous folder is
    /// gone at once, so the window never shows its counts under the new name.
    private func load(_ url: URL) {
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
        // A scan only asks whether a backup is there. It moves none.
        let scanner = FolderScanner(tag: ScaleTag(exiftool: exiftool), backups: FileBackups())
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
        start(factor: factor, convert: true, remove: false)
    }

    func remove() {
        guard canRemove else { return }
        start(factor: .noStretch, convert: false, remove: true)
    }

    /// Stops the run after its current file. The click is acknowledged at
    /// once: the phase changes here, not when the job returns.
    func cancel() {
        guard phase == .running, let job else { return }
        job.cancel.cancel()
        phase = .stopping
    }

    /// Makes the custom field the selected factor.
    func selectCustom() {
        guard choice != .custom else { return }
        choice = .custom
        customError = nil
    }

    func select(_ preset: SqueezeFactor) {
        choice = .preset(preset)
        customError = nil
    }

    /// For a quit during a run. Cancels the run and returns when its current
    /// file is complete. Returns at once when no file work is in flight.
    /// The caller must quit next: the window stays as it is, "running".
    func stopRunForQuit() async {
        isQuitting = true
        guard let job else { return }
        job.cancel.cancel()
        if phase == .running { phase = .stopping }
        _ = await job.work.result
    }

    /// - Parameter remove: the intent of the Remove button. The job does not
    ///   guess it from the factor and `convert`.
    private func start(factor: SqueezeFactor, convert: Bool, remove: Bool) {
        guard let folder, let exiftool else { return }
        let runner = DesqueezeJob(
            tag: ScaleTag(exiftool: exiftool),
            converter: converter.map { AdobeConverter(executable: $0) },
            // The window moves a backup to the Trash.
            backups: FileBackups()
        )
        let flag = CancelFlag()
        // The job reports progress from its own thread. A stream keeps the
        // updates in order, and ends when the job returns.
        let (updates, updatesEnd) = AsyncStream.makeStream(of: RunProgress.self)
        let work = Task.detached {
            defer { updatesEnd.finish() }
            // The job scans the folder itself. It gets no counts from here.
            return try runner.run(folder: folder, factor: factor, convert: convert, remove: remove, cancel: flag) {
                updatesEnd.yield($0)
            }
        }
        job = (flag, work)
        phase = .running
        summary = nil
        progress = nil

        Task {
            for await update in updates { progress = update }
            let result = try? await work.value
            job = nil
            // No scan for a window that is about to close: the scan would
            // leave an exiftool process behind the app.
            guard !isQuitting else { return }
            // The job has returned. Cancel has nothing to stop now.
            phase = .rescanning
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
            phase = .idle
        }
    }
}
