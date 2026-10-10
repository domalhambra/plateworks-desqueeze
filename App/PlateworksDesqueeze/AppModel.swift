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
    @Published private(set) var choice: Choice
    /// What the custom field holds. A change selects the custom factor.
    @Published var customText: String {
        didSet { if customText != oldValue { chooseCustom() } }
    }
    @Published private(set) var customError: String?
    /// The newest step that the job completed. Nil before its first step.
    @Published private(set) var progress: RunProgress?
    @Published private(set) var summary: RunSummary?
    @Published private(set) var phase = RunPhase.idle

    /// Reads and writes the tag. Nil when exiftool is not installed.
    private let tag: ScaleTagging?
    /// dnglab and Adobe DNG Converter, each nil when it is not installed.
    /// With neither, the DNG files still run.
    private let converters: RawConverters
    private let backups: BackupHandling
    /// Keeps the factor of a run for the next launch.
    private let saveFactor: @MainActor (String) -> Void
    /// The time in seconds, from any fixed start.
    private let now: @MainActor () -> TimeInterval
    /// Says one line to VoiceOver.
    private let announce: @MainActor (String) -> Void

    /// The job that is in flight: how to stop it, how to wait for it, and
    /// the time of the click that started it.
    private var job: (cancel: CancelFlag, work: Task<RunSummary, Error>, started: TimeInterval)?
    /// The number of the newest scan. A scan that lands with an older number
    /// is discarded.
    private var scanNumber = 0
    /// True after a quit request met a run in flight. The app is about to
    /// end. Only `answerQuit` sets it.
    private var isQuitting = false
    private static let notAFolder = "Drop a folder"

    /// Everything from the outside comes in here, and nothing has a default:
    /// no caller reaches exiftool, the Trash, or the saved settings by
    /// leaving an argument out. The app passes the real ones (`live`). A test
    /// passes its own.
    ///
    /// - Parameters:
    ///   - tag: nil when exiftool is not installed. The window then only
    ///     says so.
    ///   - converters: dnglab and Adobe DNG Converter, each nil when it is
    ///     not installed, and the reader of the ARW facts.
    ///   - backups: where a backup goes after a write that passed its check.
    ///   - savedFactor: the factor of the last run, as `saveFactor` got it.
    ///     Nil, or text that is no factor, gives 1.5.
    ///   - saveFactor: keeps the factor of a run for the next launch.
    ///   - now: the time in seconds, from any fixed start.
    ///   - announce: says one line to VoiceOver.
    init(
        tag: ScaleTagging?, converters: RawConverters, backups: BackupHandling,
        savedFactor: String?, saveFactor: @escaping @MainActor (String) -> Void,
        now: @escaping @MainActor () -> TimeInterval, announce: @escaping @MainActor (String) -> Void
    ) {
        self.tag = tag
        self.converters = converters
        self.backups = backups
        self.saveFactor = saveFactor
        self.now = now
        self.announce = announce

        let saved = savedFactor.flatMap { SqueezeFactor(text: $0) } ?? SqueezeFactor(1.5)!
        if SqueezeFactor.presets.contains(saved) {
            choice = .preset(saved)
            customText = ""
        } else {
            choice = .custom
            customText = saved.label
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

    /// True when exiftool is not installed. The window can do nothing then.
    var exiftoolMissing: Bool { tag == nil }

    // The words and the counts about the folder are made in `DesqueezeCore`
    // (`FolderText`), so the window and the command line tool cannot say
    // different things. This type only hands them to the view.

    /// True when one converter or the other is installed, so a pending ARW
    /// can convert.
    private var converterAvailable: Bool { converters.canConvert }

    /// For example `216 DNG · 12 ARW to convert`. With neither converter:
    /// `216 DNG · 12 ARW cannot be converted: no converter is installed`.
    var countsLine: String? { snapshot?.countsLine(converterAvailable: converterAvailable) }

    /// The one line about the converters, for a folder with a pending ARW
    /// (design 13.5). Nil when both are installed, and when no ARW is
    /// pending. With one converter it is a quiet line: every ARW converts.
    var converterAdvice: String? {
        snapshot?.converterAdvice(dnglabInstalled: converters.dnglab != nil, adobeInstalled: converters.adobe != nil)
    }

    /// True when the folder has a pending ARW and neither converter is
    /// installed. The counts line then says that the ARW files cannot be
    /// converted, and it and the advice show as the read-only message
    /// shows. In every other state the two are quiet lines.
    var arwsCannotConvert: Bool { snapshot?.pendingARWs.isEmpty == false && !converterAvailable }

    /// True for a note that only informs: the DNG that dnglab made with no
    /// full match (design 13.4). That file is converted, and the result
    /// keeps its "done" mark (`RunSummary.needsAttention`). Every other
    /// kind of note is about a file to look at.
    nonisolated static func isInformation(_ note: FileNote) -> Bool { note.kind == .convertedUnmatched }

    /// The messages about the loaded folder. All come from the newest scan.
    var folderMessages: [String] {
        if scanFailed { return [FolderText.unreadable] }
        return snapshot?.messages ?? []
    }

    /// The count in the run button: DNG files, plus ARW files that can convert.
    private var runCount: Int { snapshot?.runCount(converterAvailable: converterAvailable) ?? 0 }

    var runLabel: String { FolderText.runLabel(count: runCount) }

    /// The sentence about the ARW files a run left, with the reason when
    /// neither converter is installed. Nil when the run left none.
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

    /// False during a run: a drop is refused then, so the drop zone must not
    /// show that it would take one.
    var acceptsDrop: Bool { !isRunning }

    func handleDrop(_ urls: [URL]) -> Bool {
        guard acceptsDrop else { return false }
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
        guard acceptsDrop else { return false }
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
        guard let tag else { return Task {} }
        scanNumber += 1
        let number = scanNumber
        isScanning = true
        // A scan only asks whether a backup is there. It moves none.
        let scanner = FolderScanner(tag: tag, backups: backups)
        return Task {
            let result = try? await Task.detached { try scanner.snapshot(of: folder) }.value
            guard number == scanNumber else { return }
            snapshot = result
            scanFailed = result == nil
            isScanning = false
        }
    }

    /// For the moment the app becomes active again. Another app can have
    /// put files in the folder, so the loaded folder is scanned again. The
    /// result of the last run stays. Nothing starts while a run or a scan is
    /// in work: each of those ends with new counts.
    func appBecameActive() {
        guard let folder, !isRunning, !isScanning else { return }
        scan(folder)
    }

    // MARK: Run

    func run() {
        guard canRun else { return }
        guard let factor else {
            customError = "Enter \(SqueezeFactor.ruleText)."
            return
        }
        customError = nil
        saveFactor(factor.label)
        start(factor: factor, convert: true, remove: false)
    }

    func remove() {
        guard canRemove else { return }
        start(factor: .noStretch, convert: false, remove: true)
    }

    /// Stops the run after its current file. The click is acknowledged at
    /// once: the phase changes here, not when the job returns.
    ///
    /// A call inside the system's double-click time of the start does
    /// nothing. The Cancel button is in the place of the Run button, so the
    /// second click of a double-click on Run lands here. Escape in that time
    /// does nothing too.
    func cancel() {
        guard phase == .running, let job else { return }
        guard now() - job.started >= NSEvent.doubleClickInterval else { return }
        job.cancel.cancel()
        phase = .stopping
    }

    /// Makes the custom field the selected factor. For a focus in the field.
    func selectCustom() {
        guard choice != .custom else { return }
        chooseCustom()
    }

    /// The custom field is the selected factor, and what it said about the
    /// text before is gone.
    private func chooseCustom() {
        choice = .custom
        customError = nil
    }

    func select(_ preset: SqueezeFactor) {
        choice = .preset(preset)
        customError = nil
    }

    /// What a quit request must do next.
    enum QuitAnswer: Equatable {
        /// No run is in flight. Quit now.
        case now
        /// A run is in flight. Call `stopRunForQuit`, then quit.
        case afterRun
        /// An earlier request waits for the run already. Start nothing, and
        /// answer nothing: that request quits the app.
        case alreadyWaiting
    }

    /// Answers a quit request. A quit can be asked for a second time while
    /// the first waits for the run: Command-Q twice, or the close of the
    /// window and then a quit. Only one request may get `afterRun`, so the
    /// app gets its one reply.
    func answerQuit() -> QuitAnswer {
        guard !isQuitting else { return .alreadyWaiting }
        guard isRunning else { return .now }
        isQuitting = true
        return .afterRun
    }

    /// For a quit during a run. Cancels the run and returns when its current
    /// file is complete. Returns at once when no file work is in flight.
    /// The caller must quit next: the window stays as it is, "running".
    /// `answerQuit` has set the quit flag before this runs, as the app
    /// delegate calls it first. This method never sets it.
    func stopRunForQuit() async {
        guard let job else { return }
        job.cancel.cancel()
        if phase == .running { phase = .stopping }
        _ = await job.work.result
    }

    /// - Parameter remove: the intent of the Remove button. The job does not
    ///   guess it from the factor and `convert`.
    private func start(factor: SqueezeFactor, convert: Bool, remove: Bool) {
        guard let folder, let tag else { return }
        let runner = DesqueezeJob(tag: tag, converters: converters, backups: backups)
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
        job = (flag, work, now())
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
            // VoiceOver hears the counts. The result line is new on the
            // screen, and nothing else says so.
            // With no result, the run's own scan failed, and the window shows
            // the sentence of an unreadable folder.
            announce(result?.countsLine ?? FolderText.unreadable)
        }
    }
}

// MARK: The app's own model

extension AppModel {
    /// The key of the saved factor in the app's defaults.
    private static let factorKey = "lastFactor"

    /// The model of the app itself: the tools on this Mac, the Trash, the
    /// saved factor, the system's clock, and VoiceOver.
    static func live() -> AppModel {
        // The launch hooks are read from the launch arguments only. A value
        // that `defaults write` saved must never hide a tool or load a
        // folder (design, section 9).
        let options = LaunchOptions(
            arguments: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain))
        let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ToolLocator.converterBundleID)
        let locator = ToolLocator(registeredConverterApp: registered)
        let exiftool = options.hidesExiftool ? nil : locator.exiftool()
        // dnglab converts first. Adobe DNG Converter is the optional backup.
        // Both need exiftool: with none, the window can do nothing.
        // The window moves a backup to the Trash, and the leftover work file
        // of a run that ended hard (design 13.3).
        let backups = FileBackups.systemTrash
        let converters = exiftool.map {
            RawConverters(exiftool: $0, dnglab: options.hidesDnglab ? nil : locator.dnglab(),
                          adobe: options.hidesAdobe ? nil : locator.dngConverter(), backups: backups)
        }
        let model = AppModel(
            tag: exiftool.map { ScaleTag(exiftool: $0) },
            converters: converters ?? .none,
            backups: backups,
            savedFactor: UserDefaults.standard.string(forKey: factorKey),
            saveFactor: { UserDefaults.standard.set($0, forKey: factorKey) },
            now: { ProcessInfo.processInfo.systemUptime },
            announce: announceToVoiceOver
        )
        if let path = options.openFolder { model.open(URL(fileURLWithPath: path)) }
        return model
    }

    /// An announcement needs an element of the app. The main window is nil
    /// while another app is in front, and a run can end then.
    private static func announceToVoiceOver(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app.mainWindow ?? app.windows.first ?? app, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// The launch hooks, for checks by hand only (design, section 9).
struct LaunchOptions: Equatable {
    /// `-simulateMissingTools YES` shows the window as it is on a Mac with
    /// no tool: no exiftool and no converter. A Mac can have exiftool in two
    /// places, so a rename of one proves nothing.
    var hidesExiftool: Bool
    /// `-simulateMissingAdobe YES` shows the window as it is on a Mac with
    /// no Adobe DNG Converter. `-simulateMissingConverter` and
    /// `-simulateMissingTools` hide it too.
    var hidesAdobe: Bool
    /// `-simulateMissingDnglab YES` shows the window as it is on a Mac with
    /// no dnglab. `-simulateMissingConverter` and `-simulateMissingTools`
    /// hide it too.
    var hidesDnglab: Bool
    /// True when both converters are hidden. `-simulateMissingConverter YES`
    /// does that: the window as it is on a Mac with exiftool and with no
    /// converter.
    var hidesConverter: Bool { hidesAdobe && hidesDnglab }
    /// `-openFolder <path>` loads a folder at launch. The standard Open panel
    /// runs in another process that a test script cannot drive, so checks by
    /// hand and by script start here.
    var openFolder: String?

    /// - Parameter arguments: the argument domain of the defaults, and no
    ///   other domain.
    init(arguments: [String: Any]) {
        func isOn(_ key: String) -> Bool { (arguments[key] as? NSString)?.boolValue ?? false }
        hidesExiftool = isOn("simulateMissingTools")
        let hidesBoth = hidesExiftool || isOn("simulateMissingConverter")
        hidesAdobe = hidesBoth || isOn("simulateMissingAdobe")
        hidesDnglab = hidesBoth || isOn("simulateMissingDnglab")
        openFolder = arguments["openFolder"] as? String
    }
}
