import DesqueezeCore
import Foundation
import MCP

/// Everything a tool call takes from the outside. A test gives its own.
///
/// All file work is in `DesqueezeOperations`, the same entry points as the
/// command line tool's, and the result text is `ReportJSON.text`, so the
/// server and `desqueeze --json` print the same JSON (design 12).
struct ToolEnvironment: Sendable {
    /// Asked at each call, so a call works as soon as exiftool is installed,
    /// with no new start of the server.
    var locator: ToolLocator
    var runner: ProcessRunner
    /// Where a backup goes after a write that passed its check. The program
    /// names it: the Trash in normal use, and the test folder in a test.
    var backups: BackupHandling

    /// Does one tool call, and waits for it. It blocks its thread while
    /// exiftool and the converters run.
    ///
    /// - Returns: the tool result. A report is a success, also when it holds
    ///   files that failed. A call that could give no report is a tool error
    ///   with a sentence, and it changed no file: a folder that could not be
    ///   read, or a run while another run works in the folder.
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
        // The line is the core's, so the command line tool says the same.
        guard let exiftool = locator.exiftool() else { throw ToolFailure(ToolLocator.exiftoolMissingLine) }
        let folder = try self.folder(at: call.folder)
        let operations = DesqueezeOperations(exiftool: exiftool, dnglab: locator.dnglab(),
                                             dngConverter: locator.dngConverter(), runner: runner,
                                             backups: backups)
        switch call {
        case .scan:
            return try ReportJSON.text(try scanned(folder) { try operations.scan(folder) })
        case .run(_, let factor, let convert, let dryRun):
            return try ReportJSON.text(try scanned(folder) {
                // The server never moves an original (design 14.1). The
                // value is written here, and no argument of a tool reaches
                // it: an agent must not be able to remove a user's
                // originals, by request or by mistake.
                try operations.run(folder, factor: factor, convert: convert, trashOriginals: false, dryRun: dryRun,
                                   cancel: cancel, progress: progress)
            })
        case .remove(_, let dryRun):
            // Remove never moves an original, in any front end: the core's
            // `remove` takes no such request (design 14.2).
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
        guard let folder = FolderChoice.folder(at: named) else {
            throw ToolFailure("\(FolderText.unreadable(path: path)). \(FolderChoice.whyNotAFolder(named))")
        }
        return folder
    }

    /// An operation throws when its scan of the folder fails, when another
    /// run works in the folder, and when the lock call of a run failed
    /// (design 13.9). No file was tried then. A lock call that failed is a
    /// folder that could not be read, with the system's words.
    private func scanned<Report>(_ folder: URL, _ work: () throws -> Report) throws -> Report {
        do {
            return try work()
        } catch is FolderLock.Busy {
            // The sentence is the core's, so the window and the command line
            // tool say the same.
            throw ToolFailure(FolderLock.busyMessage)
        } catch {
            var detail = error.localizedDescription
            if case TagError.toolFailed(let text) = error { detail = text }
            throw ToolFailure("\(FolderText.unreadable(path: folder.path)). \(detail)")
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
