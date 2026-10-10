import Foundation
@testable import DesqueezeCore

/// The fakes of one job test, and short ways to build a folder state.
final class JobHarness {
    let folder = URL(fileURLWithPath: "/tmp/Shoot 1")
    let log = CallLog()
    let backups: FakeBackups
    let tag: FakeTag
    /// Adobe DNG Converter. Its log entries start with "convert".
    let converter: FakeConverter
    /// dnglab. Its log entries start with "dnglab".
    let dnglab: FakeConverter
    let facts: FakeFacts
    /// The disk, as the fifth step of a run asks it (design 14.2).
    let files: FakeFiles

    init() {
        backups = FakeBackups(log: log)
        tag = FakeTag(log: log, backups: backups)
        converter = FakeConverter(log: log)
        dnglab = FakeConverter(log: log, label: "dnglab", name: "dnglab", reportsTheMatch: true)
        facts = FakeFacts(log: log)
        files = FakeFiles(log: log)
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

    /// - Parameters:
    ///   - withConverter: Adobe DNG Converter is installed.
    ///   - withDnglab: dnglab is installed. Off by default, so a test that
    ///     does not name it runs as on a Mac with Adobe's converter alone.
    func converters(withConverter: Bool = true, withDnglab: Bool = false) -> RawConverters {
        RawConverters(dnglab: withDnglab ? dnglab : nil, adobe: withConverter ? converter : nil, facts: facts)
    }

    func job(withConverter: Bool = true, withDnglab: Bool = false) -> DesqueezeJob {
        let files = files
        return DesqueezeJob(tag: tag, converters: converters(withConverter: withConverter, withDnglab: withDnglab),
                            backups: backups, fileRecord: { files.record(atPath: $0) })
    }
}
