import Foundation
@testable import DesqueezeCore

/// A `ProcessRunner` that records each call and answers from a closure.
final class FakeRunner: ProcessRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    var calls: [Call] = []
    var handler: (Call) -> ProcessResult = { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "") }
    /// Thrown after the handler ran, as when a signal ends a program that
    /// has already written part of its output.
    var failure: Error?

    func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        let call = Call(executable: executable.path, arguments: arguments)
        calls.append(call)
        let result = handler(call)
        if let failure { throw failure }
        return result
    }
}

/// Makes an empty temporary folder inside a new `desqueeze-tests-<id>` folder.
/// The test removes it in `tearDown` with `removeTemporaryFolder`.
func makeTemporaryFolder(named name: String = "Shoot 1") throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("desqueeze-tests-\(UUID().uuidString)")
    let folder = base.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Removes the `desqueeze-tests-<id>` folder that holds `folder`. Does nothing
/// for any other URL, so a wrong argument cannot remove a real folder.
func removeTemporaryFolder(_ folder: URL) {
    let base = folder.deletingLastPathComponent()
    guard base.lastPathComponent.hasPrefix("desqueeze-tests-") else { return }
    try? FileManager.default.removeItem(at: base)
}

/// An error with a fixed description, so a test can assert the exact text.
struct NamedError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

/// An ordered record of what the fakes were asked to do.
final class CallLog: @unchecked Sendable {
    var entries: [String] = []
}

final class FakeBackups: BackupHandling, @unchecked Sendable {
    let log: CallLog
    var existing: Set<String> = []
    var trashError: Error?
    var restoreError: Error?
    /// Set when `trashFile` must fail, as when the Trash refuses.
    var trashFileError: Error?

    init(log: CallLog) { self.log = log }

    func backupExists(for dng: URL) -> Bool { existing.contains(dng.lastPathComponent) }

    func trashBackup(for dng: URL) throws {
        log.entries.append("trash \(dng.lastPathComponent)")
        if let trashError { throw trashError }
        existing.remove(dng.lastPathComponent)
    }

    func trashFile(_ file: URL) throws {
        log.entries.append("trashFile \(file.lastPathComponent)")
        if let trashFileError { throw trashFileError }
    }

    func restoreBackup(for dng: URL) throws {
        log.entries.append("restore \(dng.lastPathComponent)")
        if let restoreError { throw restoreError }
        existing.remove(dng.lastPathComponent)
    }
}

/// Acts like exiftool: a good write leaves a backup, a bad write leaves none.
final class FakeTag: ScaleTagging, @unchecked Sendable {
    let log: CallLog
    let backups: FakeBackups
    var rows: [TagRow] = []
    var readFolderError: Error?
    var failWrites: Set<String> = []
    /// File names whose read-back does not match what was written.
    var wrongReadBack: Set<String> = []
    /// File names whose read-back throws, as when exiftool cannot start.
    var failReads: Set<String> = []
    /// File names whose read-back finds no tag.
    var noReadBack: Set<String> = []
    var onWrite: (() -> Void)?
    private var written: [String: SqueezeFactor] = [:]

    init(log: CallLog, backups: FakeBackups) {
        self.log = log
        self.backups = backups
    }

    func readFolder(_ folder: URL) throws -> [TagRow] {
        log.entries.append("readFolder")
        if let readFolderError { throw readFolderError }
        return rows
    }

    func write(_ factor: SqueezeFactor, to file: URL) throws {
        let name = file.lastPathComponent
        log.entries.append("write \(factor.tagValue) \(name)")
        onWrite?()
        if failWrites.contains(name) { throw TagError.toolFailed("Error: write failed") }
        written[name] = factor
        backups.existing.insert(name)
    }

    func read(_ file: URL) throws -> Scale? {
        let name = file.lastPathComponent
        log.entries.append("read \(name)")
        if failReads.contains(name) { throw TagError.toolFailed("Error: read failed") }
        if noReadBack.contains(name) { return nil }
        if wrongReadBack.contains(name) { return .noStretch }
        return written[name].map { Scale(horizontal: $0.value, vertical: 1) }
    }
}

final class FakeConverter: RawConverter, @unchecked Sendable {
    let log: CallLog
    var fail: Set<String> = []
    /// ARW names whose failed conversion also left a partial DNG.
    var failWithPartial: Set<String> = []
    /// What a failed conversion names as its partial DNG, in place of the
    /// output of the ARW. A correct converter never does this.
    var reportedPartial: URL?
    var onConvert: (() -> Void)?

    init(log: CallLog) { self.log = log }

    func convert(_ arw: URL, facts: ARWFacts) throws -> Conversion {
        log.entries.append("convert \(arw.lastPathComponent)")
        onConvert?()
        if fail.contains(arw.lastPathComponent) { throw ConvertError.failed("made no DNG") }
        if failWithPartial.contains(arw.lastPathComponent) {
            throw ConvertError.failed("Adobe DNG Converter returned 1.",
                                      partial: reportedPartial ?? AdobeConverter.outputURL(for: arw))
        }
        return Conversion(dng: AdobeConverter.outputURL(for: arw), unmatched: nil)
    }
}
