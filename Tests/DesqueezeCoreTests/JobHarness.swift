import Foundation
@testable import DesqueezeCore

/// The fakes of one job test, and short ways to build a folder state.
final class JobHarness {
    let folder = URL(fileURLWithPath: "/tmp/Shoot 1")
    let log = CallLog()
    let backups: FakeBackups
    let tag: FakeTag
    let converter: FakeConverter

    init() {
        backups = FakeBackups(log: log)
        tag = FakeTag(log: log, backups: backups)
        converter = FakeConverter(log: log)
    }

    /// - Parameter horizontal: the scale the scan read. Nil is "unknown".
    func dng(_ name: String, at horizontal: Double? = 1) -> DNGFile {
        DNGFile(url: folder.appendingPathComponent(name),
                scale: horizontal.map { Scale(horizontal: $0, vertical: 1) },
                originalRawFileName: nil, hasBackup: backups.existing.contains(name))
    }

    func snapshot(dngs: [DNGFile] = [], pending: [String] = [], orphans: [String] = [],
                  writable: Bool = true) -> FolderSnapshot {
        FolderSnapshot(folder: folder, dngs: dngs,
                       pendingARWs: pending.map { folder.appendingPathComponent($0) },
                       orphanBackups: orphans.map { folder.appendingPathComponent($0) }, isWritable: writable)
    }

    func job(withConverter: Bool = true) -> DesqueezeJob {
        DesqueezeJob(tag: tag, converter: withConverter ? converter : nil, backups: backups)
    }
}
