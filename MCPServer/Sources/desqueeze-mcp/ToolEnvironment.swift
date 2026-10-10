import DesqueezeCore
import Foundation
import MCP

/// Everything a tool call takes from the outside. A test gives its own.
///
/// All file work is in `DesqueezeOperations`, the same entry points as the
/// command line tool's, and the result text is `ReportJSON.text`, so the
/// server and `desqueeze --json` print the same JSON (design 12).
struct ToolEnvironment: Sendable {
    static let missingExiftool =
        "Desqueeze needs exiftool, and it is not installed. Install it with: brew install exiftool"

    /// Asked at each call, so a call works as soon as exiftool is installed,
    /// with no new start of the server.
    var locator: ToolLocator
    var runner: ProcessRunner
    /// Where a backup goes after a write that passed its check. The program
    /// names it: the Trash in normal use, and the test folder in a test.
    var backups: BackupHandling

    /// Does one tool call, and waits for it. It blocks its thread while
    /// exiftool and the converter run.
    ///
    /// - Returns: the tool result. A report is a success, also when it holds
    ///   files that failed. A call that could give no report is a tool error
    ///   with a sentence, and it changed no file.
    func result(of call: ToolCall, cancel: CancelFlag = CancelFlag(),
                progress: (RunProgress) -> Void = { _ in }) -> CallTool.Result {
        do {
            return .report(try perform(call, cancel: cancel, progress: progress))
        } catch let failure as ToolFailure {
            return .refusal(failure.message)
        } catch {
            return .refusal("The report could not be written: \(error.localizedDescription)")
        }
    }

    /// - Returns: the report as JSON text.
    private func perform(_ call: ToolCall, cancel: CancelFlag, progress: (RunProgress) -> Void) throws -> String {
        guard let exiftool = locator.exiftool() else { throw ToolFailure(Self.missingExiftool) }
        let folder = try self.folder(at: call.folder)
        let operations = DesqueezeOperations(exiftool: exiftool, dngConverter: locator.dngConverter(),
                                             runner: runner, backups: backups)
        switch call {
        case .scan:
            return try ReportJSON.text(try scanned(folder) { try operations.scan(folder) })
        case .run(_, let factor, let convert, let dryRun):
            return try ReportJSON.text(try scanned(folder) {
                try operations.run(folder, factor: factor, convert: convert, dryRun: dryRun, cancel: cancel,
                                   progress: progress)
            })
        case .remove(_, let dryRun):
            return try ReportJSON.text(try scanned(folder) {
                try operations.remove(folder, dryRun: dryRun, cancel: cancel, progress: progress)
            })
        }
    }

    /// The window's rule for what a folder is (`FolderChoice`). A link to a
    /// folder is that folder, and the report names the folder. A file, and a
    /// package such as an app or a photo library, are not folders.
    private func folder(at path: String) throws -> URL {
        let named = URL(fileURLWithPath: path, isDirectory: true)
        if let folder = FolderChoice.folder(at: named) { return folder }

        let resolved = named.resolvingSymlinksInPath()
        let why: String
        if !FileManager.default.fileExists(atPath: resolved.path) {
            why = "Nothing is at this path."
        } else if (try? resolved.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
            why = "It is a package, such as an app or a photo library, and not a folder of photos."
        } else {
            why = "It is a file, not a folder."
        }
        throw ToolFailure("This folder could not be read: \(path). \(why)")
    }

    /// An operation throws only when its scan of the folder fails. No file
    /// was tried then.
    private func scanned<Report>(_ folder: URL, _ work: () throws -> Report) throws -> Report {
        do {
            return try work()
        } catch {
            var detail = error.localizedDescription
            if case TagError.toolFailed(let text) = error { detail = text }
            throw ToolFailure("This folder could not be read: \(folder.path). \(detail)")
        }
    }
}

extension CallTool.Result {
    /// A report: one text item, the JSON of `ReportJSON.text`.
    static func report(_ json: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)], isError: false)
    }

    /// A tool error: one text item, a sentence.
    static func refusal(_ sentence: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: sentence, annotations: nil, _meta: nil)], isError: true)
    }
}
