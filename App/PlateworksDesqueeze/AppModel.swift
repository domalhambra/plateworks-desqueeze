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
    @Published private(set) var snapshot: FolderSnapshot? {
        // The box of design 14.4 is on only while it shows. A folder with
        // no pending ARW that can convert turns it off.
        didSet { if trashOriginals, !showsTrashOriginals { trashOriginals = false } }
    }
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
    /// Why the last click on Run or Remove started no run: another run works
    /// in the folder (design 13.9). The sentence is the core's.
    ///
    /// It goes at the next click that starts a run, when another folder
    /// loads, and when a scan of the folder fails. The last one is the rule
    /// "one state, one message": a folder that could not be read is the
    /// newer event, so the window shows that, and VoiceOver hears that.
    @Published private(set) var runRefusal: String?
    /// The detail line under "This folder could not be read.": the system's
    /// words for a lock call that failed, so the click on Run or Remove
    /// started no run (design 13.9, the last row of the table). The command
    /// line tool and the MCP server show the same words. The words are the
    /// core's (`FolderLock.Failed`).
    ///
    /// Nil in every other state. It goes when a scan of the folder lands,
    /// when another folder loads, and at the next click that starts a run:
    /// each of those is newer than the click that failed.
    @Published private(set) var folderMessageDetail: String?
    @Published private(set) var phase = RunPhase.idle
    /// The box "Move the original ARW files to the Trash" (design 14.4).
    ///
    /// It is off at every launch, when a folder loads, and after every run,
    /// also a run that was cancelled, that failed, or that did not start.
    /// It is never saved, and no launch argument turns it on: only
    /// `setTrashOriginals` does, from a click on the box. A scan of the
    /// loaded folder does not change it, unless the folder then has no
    /// pending ARW that can convert.
    @Published private(set) var trashOriginals = false

    /// Reads and writes the tag. Nil when exiftool is not installed.
    private let tag: ScaleTagging?
    /// dnglab and Adobe DNG Converter, each nil when it is not installed.
    /// With neither, the DNG files still run.
    private let converters: RawConverters
    private let backups: BackupHandling
    /// The lock that keeps a second run out of the folder (design 13.9).
    private let lock: FolderLock
    /// Keeps the factor of a run for the next launch.
    private let saveFactor: @MainActor (String) -> Void
    /// The factor of the run in flight, until the job says whether the run
    /// started. Nil for Remove, and when no run is in flight.
    private var factorToSave: String?
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
    ///   - lock: the lock that a run takes on the folder. The app gives the
    ///     system's. A test gives one whose call fails.
    ///   - savedFactor: the factor of the last run, as `saveFactor` got it.
    ///     Nil, or text that is no factor, gives 1.5.
    ///   - saveFactor: keeps the factor of a run for the next launch.
    ///   - now: the time in seconds, from any fixed start.
    ///   - announce: says one line to VoiceOver.
    init(
        tag: ScaleTagging?, converters: RawConverters, backups: BackupHandling, lock: FolderLock,
        savedFactor: String?, saveFactor: @escaping @MainActor (String) -> Void,
        now: @escaping @MainActor () -> TimeInterval, announce: @escaping @MainActor (String) -> Void
    ) {
        self.tag = tag
        self.converters = converters
        self.backups = backups
        self.lock = lock
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
    /// converted, and the view gives it the warning symbol. The install line
    /// gets the information symbol with primary text (design 13.5). In every
    /// other state the two are quiet lines.
    var arwsCannotConvert: Bool { snapshot?.pendingARWs.isEmpty == false && !converterAvailable }

    /// True for a note that only informs: the DNG that dnglab made with no
    /// full match (design 13.4). That file is converted, and the result
    /// keeps its "done" mark (`RunSummary.needsAttention`). Every other
    /// kind of note is about a file to look at.
    ///
    /// An original that stays in the folder is information too (design
    /// 14.3): the run did its work, and the note says why the ARW is there.
    /// So is the note of a volume that gives no folder lock (design 13.9):
    /// the run went on, and nothing failed.
    nonisolated static func isInformation(_ note: FileNote) -> Bool {
        note.kind == .convertedUnmatched || note.kind == .originalKept || note.kind == .noFolderLock
    }

    /// The messages about the loaded folder. They come from the newest
    /// scan, and from a click on Run or Remove that started no run. A scan
    /// that failed is the only message: it has taken `runRefusal` away.
    /// `folderMessageDetail` is the detail line under them, when there is
    /// one.
    var folderMessages: [String] {
        if scanFailed { return [FolderText.unreadable] }
        return (runRefusal.map { [$0] } ?? []) + (snapshot?.messages ?? [])
    }

    /// The count in the run button: DNG files, plus ARW files that can convert.
    private var runCount: Int { snapshot?.runCount(converterAvailable: converterAvailable) ?? 0 }

    /// `Desqueeze N photos`, and while the box is on `Desqueeze N photos,
    /// move M ARW to Trash` (design 14.4). The core makes both.
    var runLabel: String {
        FolderText.runLabel(count: runCount, originalsToTrash: trashOriginals ? originalsCount : 0)
    }

    // MARK: The originals (design 14.4)

    /// The pending ARW files of the loaded folder that a run can convert,
    /// and so the originals that a run can move. 0 for a folder that is
    /// read-only: a run converts nothing there.
    private var originalsCount: Int {
        guard let snapshot, snapshot.isWritable else { return 0 }
        return snapshot.convertibleARWs(converterAvailable: converterAvailable)
    }

    /// True when the loaded folder has a pending ARW that can convert. The
    /// box shows only then. In every other state it is not shown, and it is
    /// off.
    var showsTrashOriginals: Bool { originalsCount > 0 }

    /// False while a run or a scan is in work: the box then cannot change.
    var canChangeTrashOriginals: Bool { showsTrashOriginals && !isScanning && !isRunning }

    /// The click on the box. It does nothing while the box does not show,
    /// and while a run or a scan is in work.
    func setTrashOriginals(_ on: Bool) {
        guard canChangeTrashOriginals else { return }
        trashOriginals = on
    }

    /// The line under the box while it is on: what the run will do with
    /// the originals. The core makes it. Nil while the box is off.
    var trashOriginalsLine: String? {
        trashOriginals ? FolderText.trashOriginalsLine(count: originalsCount) : nil
    }

    /// What VoiceOver hears when a run ends: the counts, and after a run
    /// that was asked to move the originals, the core's line with the two
    /// counts of design 14.3.
    nonisolated static func announcement(_ summary: RunSummary) -> String {
        [summary.countsLine, summary.originalsLine].compactMap { $0 }.joined(separator: ". ")
    }

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
        runRefusal = nil
        folderMessageDetail = nil
        progress = nil
        // Also for the folder that was loaded already: a box that stays on
        // from an earlier folder is the way this option can move files that
        // the person wants (design 14.1).
        trashOriginals = false
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
            // One state, one message. The folder could not be read, and
            // that is newer than the refusal of an earlier click.
            if scanFailed { runRefusal = nil }
            // This scan is newer than a lock call that failed. Its own
            // failure has no words of the system to show.
            folderMessageDetail = nil
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
            // The rule and the hint about a comma are the core's, so the
            // command line tool says the same.
            customError = "Enter \(SqueezeFactor.ruleText).\(SqueezeFactor.hint(for: customText))"
            return
        }
        customError = nil
        // The factor is the only thing that the window saves, and only for
        // a run that started (`keepTheFactor`). The box of design 14.4 is
        // never saved.
        start(factor: factor, convert: true, trashOriginals: trashOriginals, remove: false, saves: factor.label)
    }

    /// Saves the factor of the run in flight, once, when its job gave a
    /// result: the run started. A run that did not start saves nothing:
    /// another run works in the folder, or the folder could not be read, so
    /// no file was tried. The next launch then has the factor of the last
    /// run that worked.
    private func keepTheFactor(of outcome: Result<RunSummary, Error>) {
        guard let factor = factorToSave else { return }
        factorToSave = nil
        if case .success = outcome { saveFactor(factor) }
    }

    /// Remove never moves an original, whatever the box says (design 14.2).
    func remove() {
        guard canRemove else { return }
        start(factor: .noStretch, convert: false, trashOriginals: false, remove: true, saves: nil)
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
        // The app ends when this returns, so the factor is saved here, and
        // not left to the task of `start`, which can come too late.
        keepTheFactor(of: await job.work.result)
    }

    /// - Parameters:
    ///   - trashOriginals: the box, as it is at the click on Run. The job
    ///     gets this value, and a change of the box after the click does not
    ///     reach it.
    ///   - remove: the intent of the Remove button. The job does not guess
    ///     it from the factor and `convert`.
    ///   - saves: the factor to keep for the next launch when the run has
    ///     started (`keepTheFactor`). Nil for Remove, which has no factor
    ///     of its own.
    private func start(factor: SqueezeFactor, convert: Bool, trashOriginals: Bool, remove: Bool, saves: String?) {
        guard let folder, let tag else { return }
        factorToSave = saves
        let runner = DesqueezeJob(tag: tag, converters: converters, backups: backups, lock: lock)
        let flag = CancelFlag()
        // The job reports progress from its own thread. A stream keeps the
        // updates in order, and ends when the job returns.
        let (updates, updatesEnd) = AsyncStream.makeStream(of: RunProgress.self)
        let work = Task.detached {
            defer { updatesEnd.finish() }
            // The job scans the folder itself. It gets no counts from here.
            return try runner.run(folder: folder, factor: factor, convert: convert, trashOriginals: trashOriginals,
                                  remove: remove, cancel: flag) {
                updatesEnd.yield($0)
            }
        }
        job = (flag, work, now())
        phase = .running
        summary = nil
        runRefusal = nil
        folderMessageDetail = nil
        progress = nil

        Task {
            for await update in updates { progress = update }
            let outcome = await work.result
            keepTheFactor(of: outcome)
            let result = try? outcome.get()
            // Another run works in the folder: in the command line tool, the
            // MCP server, or a second window. This run did not start.
            var refused = false
            if case .failure(let error) = outcome, error is FolderLock.Busy { refused = true }
            job = nil
            // The box is off after every run: one that completed, one that
            // was cancelled, one that failed, and one that did not start
            // (design 14.4). The next run moves no original unless the
            // person ticks the box again.
            self.trashOriginals = false
            // No scan for a window that is about to close: the scan would
            // leave an exiftool process behind the app.
            guard !isQuitting else { return }
            // The job has returned. Cancel has nothing to stop now.
            phase = .rescanning
            if result == nil, !refused {
                // The job's own scan failed, or its lock call did (design
                // 13.9). No file was tried.
                snapshot = nil
                scanFailed = true
                // For the lock call, the system's words go on the detail
                // line, as the command line tool shows them. The scan after
                // this run does not start, so nothing takes them away here.
                if case .failure(let error) = outcome, let failed = error as? FolderLock.Failed {
                    folderMessageDetail = failed.localizedDescription
                }
            } else {
                // Also after a refusal: the other run changes the folder,
                // and a scan is allowed while it works.
                await scan(folder).value
            }
            // The result and the new counts arrive together.
            summary = result
            // The scan after a refusal can fail. The folder could not be
            // read then, and that is the newer event: the window shows it
            // alone, so the refusal is not kept behind it.
            runRefusal = refused && !scanFailed ? FolderLock.busyMessage : nil
            progress = nil
            phase = .idle
            // VoiceOver hears the counts. The result line is new on the
            // screen, and nothing else says so.
            // With no result, the run did not start, or its own scan failed.
            // The window shows the sentence that VoiceOver hears: the
            // refusal, or "could not be read" when the newest scan failed.
            // After a run that was asked to move the originals, it hears
            // the core's line with the two counts too (design 14.4).
            announce(result.map(Self.announcement) ?? runRefusal ?? FolderText.unreadable)
        }
    }
}

// MARK: The app's own model

extension AppModel {
    /// The key of the saved factor in the app's defaults.
    private static let factorKey = "lastFactor"

    /// The model of the app itself: the tools inside the app or on this Mac,
    /// the Trash, the saved factor, the system's clock, and VoiceOver.
    static func live() -> AppModel {
        // The launch hooks are read from the launch arguments only. A value
        // that `defaults write` saved must never hide a tool or load a
        // folder (design, section 9).
        let options = LaunchOptions(
            arguments: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain))
        // The three programs come from one function, which the tests call
        // too: the copies inside the app first, then the Mac, less what a
        // launch hook hides (design 15.4). This method only gives it the
        // facts of this process.
        let tools = WindowTools.find(
            bundle: Bundle.main.bundleURL, options: options,
            registeredConverterApp: NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: ToolLocator.converterBundleID),
            pathVariable: ProcessInfo.processInfo.environment["PATH"],
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
        // dnglab converts each photo that it can match, and Adobe DNG
        // Converter, when it is installed, converts the others. Both need
        // exiftool: with none, the window can do nothing.
        // The window moves a backup to the Trash, and the leftover work file
        // of a run that ended hard (design 13.3).
        let backups = FileBackups.systemTrash
        let converters = tools.exiftool.map {
            RawConverters(exiftool: $0, dnglab: tools.dnglab, adobe: tools.adobe, backups: backups)
        }
        let model = AppModel(
            tag: tools.exiftool.map { ScaleTag(exiftool: $0) },
            converters: converters ?? .none,
            backups: backups,
            lock: .system,
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
    /// no Adobe DNG Converter. `-simulateMissingTools` hides it too.
    var hidesAdobe: Bool
    /// `-simulateMissingDnglab YES` shows the window as it is on a Mac with
    /// no dnglab. `-simulateMissingTools` hides it too. Both arguments
    /// together show the window as it is with exiftool and with neither
    /// converter.
    var hidesDnglab: Bool
    /// `-openFolder <path>` loads a folder at launch. The standard Open panel
    /// runs in another process that a test script cannot drive, so checks by
    /// hand and by script start here.
    var openFolder: String?

    /// - Parameter arguments: the argument domain of the defaults, and no
    ///   other domain.
    init(arguments: [String: Any]) {
        func isOn(_ key: String) -> Bool { (arguments[key] as? NSString)?.boolValue ?? false }
        hidesExiftool = isOn("simulateMissingTools")
        hidesAdobe = hidesExiftool || isOn("simulateMissingAdobe")
        hidesDnglab = hidesExiftool || isOn("simulateMissingDnglab")
        openFolder = arguments["openFolder"] as? String
    }
}
