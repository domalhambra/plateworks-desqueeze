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

    func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        let call = Call(executable: executable.path, arguments: arguments)
        calls.append(call)
        return handler(call)
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

/// An ordered record of what the fakes were asked to do.
final class CallLog: @unchecked Sendable {
    var entries: [String] = []
}

final class FakeBackups: BackupHandling, @unchecked Sendable {
    let log: CallLog
    var existing: Set<String> = []
    var trashError: Error?
    var restoreError: Error?

    init(log: CallLog) { self.log = log }

    func backupExists(for dng: URL) -> Bool { existing.contains(dng.lastPathComponent) }

    func trashBackup(for dng: URL) throws {
        log.entries.append("trash \(dng.lastPathComponent)")
        if let trashError { throw trashError }
        existing.remove(dng.lastPathComponent)
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
    var failWrites: Set<String> = []
    /// File names whose read-back does not match what was written.
    var wrongReadBack: Set<String> = []
    var onWrite: (() -> Void)?
    private var written: [String: SqueezeFactor] = [:]

    init(log: CallLog, backups: FakeBackups) {
        self.log = log
        self.backups = backups
    }

    func readFolder(_ folder: URL) throws -> [TagRow] {
        log.entries.append("readFolder")
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

    func read(_ file: URL) throws -> (horizontal: Double, vertical: Double)? {
        let name = file.lastPathComponent
        log.entries.append("read \(name)")
        if wrongReadBack.contains(name) { return (1, 1) }
        return written[name].map { ($0.value, 1) }
    }
}

final class FakeConverter: RawConverter, @unchecked Sendable {
    let log: CallLog
    var fail: Set<String> = []

    init(log: CallLog) { self.log = log }

    func convert(_ arw: URL) throws -> URL {
        log.entries.append("convert \(arw.lastPathComponent)")
        if fail.contains(arw.lastPathComponent) { throw ConvertError.failed("made no DNG") }
        return AdobeConverter.outputURL(for: arw)
    }
}
