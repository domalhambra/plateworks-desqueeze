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

    @Published private(set) var snapshot: FolderSnapshot?
    @Published private(set) var folderMessage: String?
    @Published var choice: Choice
    @Published var customText: String
    @Published var customError: String?
    @Published private(set) var progress: RunProgress?
    @Published private(set) var summary: RunSummary?
    @Published private(set) var isRunning = false

    let exiftool: URL?
    let converter: URL?

    private var cancelFlag: CancelFlag?
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

    var folderName: String? { snapshot?.folder.lastPathComponent }

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

    /// The count in the run button: DNG files, plus ARW files that can convert.
    var runCount: Int {
        guard let snapshot else { return 0 }
        return snapshot.dngs.count + (converter == nil ? 0 : snapshot.pendingARWs.count)
    }

    var canRun: Bool {
        exiftool != nil && !isRunning && runCount > 0 && snapshot?.isWritable == true
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
            folderMessage = "Drop a folder"
            return false
        }
        load(url)
        return true
    }

    func load(_ folder: URL) {
        summary = nil
        progress = nil
        scan(folder)
    }

    private func scan(_ folder: URL) {
        folderMessage = nil
        guard let exiftool else {
            snapshot = nil
            return
        }
        let scanner = FolderScanner(tag: ScaleTag(exiftool: exiftool))
        Task {
            do {
                let result = try await Task.detached { try scanner.snapshot(of: folder) }.value
                snapshot = result
                if !result.isWritable {
                    folderMessage = "This folder is read-only. Desqueeze cannot change its files."
                }
            } catch {
                snapshot = nil
                folderMessage = "This folder could not be read."
            }
        }
    }

    // MARK: Run

    func run() {
        guard let factor else {
            customError = "Enter a number from 1 to 4, with at most four decimal places."
            return
        }
        customError = nil
        UserDefaults.standard.set(factor.label, forKey: Self.factorKey)
        start(factor: factor, convert: true)
    }

    func remove() {
        start(factor: .noStretch, convert: false)
    }

    func cancel() {
        cancelFlag?.cancel()
    }

    private func start(factor: SqueezeFactor, convert: Bool) {
        guard !isRunning, let snapshot, let exiftool else { return }
        let job = DesqueezeJob(
            tag: ScaleTag(exiftool: exiftool),
            converter: converter.map { AdobeConverter(executable: $0) }
        )
        let flag = CancelFlag()
        cancelFlag = flag
        isRunning = true
        summary = nil
        progress = nil

        Task {
            let result = await Task.detached {
                job.run(snapshot, factor: factor, convert: convert, cancel: flag) { update in
                    Task { @MainActor in self.progress = update }
                }
            }.value
            summary = result
            isRunning = false
            cancelFlag = nil
            scan(snapshot.folder)
        }
    }
}
