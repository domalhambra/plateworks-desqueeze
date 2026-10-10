import XCTest
@testable import DesqueezeCore

final class FolderScanTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws { folder = try makeTemporaryFolder() }
    override func tearDown() { removeTemporaryFolder(folder) }

    func touch(_ name: String) throws {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    func dng(_ name: String, original: String? = nil) -> DNGFile {
        DNGFile(url: folder.appendingPathComponent(name), scale: .noStretch,
                originalRawFileName: original, hasBackup: false)
    }

    func testFindsDNGAndARWInAnyLetterCase() throws {
        for name in ["a.dng", "B.DNG", "c.ARW", "d.arw", "e.jpg", "f.tif"] { try touch(name) }
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs.map(\.lastPathComponent), ["a.dng", "B.DNG"])
        XCTAssertEqual(contents.arws.map(\.lastPathComponent), ["c.ARW", "d.arw"])
    }

    func testReadsTheTopLevelOnly() throws {
        try touch("top.dng")
        try touch("Exports/nested.dng")
        try touch("CaptureOne/Settings/x.ARW")
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs.map(\.lastPathComponent), ["top.dng"])
        XCTAssertEqual(contents.arws, [])
    }

    func testIgnoresHiddenFilesBackupsAndFoldersNamedLikeFiles() throws {
        try touch("real.dng")
        try touch(".hidden.dng")
        try touch("real.dng_original")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("folder.dng"),
                                                withIntermediateDirectories: true)
        try touch("real.ARW")
        try touch(".hidden.ARW")
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs.map(\.lastPathComponent), ["real.dng"])
        // A hidden ARW is no photo of the folder: a run would convert it,
        // and its work file would be `..hidden.desqueeze-work.dng`.
        XCTAssertEqual(contents.arws.map(\.lastPathComponent), ["real.ARW"])
    }

    // A run that ended hard left the hidden work file of x.ARW (design
    // 13.3). The scan does not see it: the ARW is still pending, and the
    // folder has no DNG. So the next run converts the ARW again.
    func testAFolderWithAnARWAndItsLeftoverWorkFileScansAsOnePendingARWAndNoDNG() throws {
        try touch("x.ARW")
        try touch(".x.desqueeze-work.dng")
        let log = CallLog()
        let backups = FakeBackups(log: log)
        let snapshot = try FolderScanner(tag: FakeTag(log: log, backups: backups), backups: backups)
            .snapshot(of: folder)
        XCTAssertEqual(snapshot.dngs, [])
        XCTAssertEqual(snapshot.pendingARWs.map(\.lastPathComponent), ["x.ARW"])
        XCTAssertEqual(snapshot.orphanBackups, [])
        XCTAssertEqual(log.entries, [], "with no DNG, exiftool does not read the folder")
    }

    func testSortsNamesTheWayFinderDoes() throws {
        for name in ["DSC10.dng", "DSC9.dng", "DSC100.dng"] { try touch(name) }
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs.map(\.lastPathComponent), ["DSC9.dng", "DSC10.dng", "DSC100.dng"])
    }

    func testAnARWIsPendingOnlyWhenNoDNGHasItsBaseName() {
        let arws = ["DSC1.ARW", "dsc2.arw", "DSC3.ARW"].map { folder.appendingPathComponent($0) }
        let pending = FolderScan.pending(arws: arws, dngs: [dng("DSC1.dng"), dng("DSC2.DNG")], orphanBackups: [])
        XCTAssertEqual(pending.map(\.lastPathComponent), ["DSC3.ARW"])
    }

    func testARenamedDNGClaimsItsARWThroughOriginalRawFileName() {
        let arws = ["DSC05680.ARW", "DSC05681.ARW"].map { folder.appendingPathComponent($0) }
        let renamed = dng("Renamed on import 0022.dng", original: "dsc05680.arw")
        let pending = FolderScan.pending(arws: arws, dngs: [renamed], orphanBackups: [])
        XCTAssertEqual(pending.map(\.lastPathComponent), ["DSC05681.ARW"])
    }

    // The input every real folder produces: the converter records the name in
    // the camera's own letter case.
    func testOriginalRawFileNameInTheCamerasOwnCaseClaimsItsARW() {
        let arws = ["DSC05680.ARW", "DSC05681.ARW"].map { folder.appendingPathComponent($0) }
        let renamed = dng("Renamed on import 0022.dng", original: "DSC05680.ARW")
        let pending = FolderScan.pending(arws: arws, dngs: [renamed], orphanBackups: [])
        XCTAssertEqual(pending.map(\.lastPathComponent), ["DSC05681.ARW"])
    }

    func testABaseNameWithDotsIsComparedWhole() {
        let arws = ["2026.10.04 a.ARW", "2026.10.04 b.ARW"].map { folder.appendingPathComponent($0) }
        let pending = FolderScan.pending(arws: arws, dngs: [dng("2026.10.04 a.dng")], orphanBackups: [])
        XCTAssertEqual(pending.map(\.lastPathComponent), ["2026.10.04 b.ARW"])
    }

    // The DNG of this ARW is waiting as a backup. A conversion would make a
    // second DNG of the same photo.
    func testAnOrphanBackupClaimsItsARWByBaseName() {
        let arws = ["frame.ARW", "LOUD.arw", "other.ARW"].map { folder.appendingPathComponent($0) }
        let orphans = ["frame.dng_original", "loud.DNG_ORIGINAL"].map { folder.appendingPathComponent($0) }
        let pending = FolderScan.pending(arws: arws, dngs: [], orphanBackups: orphans)
        XCTAssertEqual(pending.map(\.lastPathComponent), ["other.ARW"])
    }

    func testAnOrphanBackupClaimsByItsWholeBaseNameOnly() {
        let arws = ["2026.10.04 a.ARW", "2026.10.04 b.ARW", "frame.ARW"].map { folder.appendingPathComponent($0) }
        let orphans = ["2026.10.04 a.dng_original", "fram.dng_original", "frame2.dng_original"]
            .map { folder.appendingPathComponent($0) }
        let pending = FolderScan.pending(arws: arws, dngs: [], orphanBackups: orphans)
        XCTAssertEqual(pending.map(\.lastPathComponent), ["2026.10.04 b.ARW", "frame.ARW"])
    }

    func testASymlinkIsNotAFile() throws {
        try touch("real.dng")
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("link.dng"),
            withDestinationURL: folder.appendingPathComponent("real.dng"))
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs.map(\.lastPathComponent), ["real.dng"])
    }

    // exiftool renames X.dng to X.dng_original, then its new file to X.dng.
    // When it stops between the two, the backup is the only copy.
    func testABackupWithNoDNGBesideItIsAnOrphan() throws {
        for name in ["gone.dng_original", "LOUD.DNG_ORIGINAL", "DSC10.dng_original", "DSC9.dng_original"] {
            try touch(name)
        }
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.orphanBackups.map(\.lastPathComponent),
                       ["DSC9.dng_original", "DSC10.dng_original", "gone.dng_original", "LOUD.DNG_ORIGINAL"])
        XCTAssertEqual(contents.dngs, [])
        XCTAssertEqual(contents.arws, [])
    }

    func testABackupWithItsDNGBesideItIsNotAnOrphan() throws {
        for name in ["kept.dng", "kept.dng_original", "gone.dng_original"] { try touch(name) }
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs.map(\.lastPathComponent), ["kept.dng"])
        XCTAssertEqual(contents.orphanBackups.map(\.lastPathComponent), ["gone.dng_original"])
    }

    func testOnlyATopLevelVisibleRegularDNGBackupCanBeAnOrphan() throws {
        try touch("gone.dng_original")
        try touch(".hidden.dng_original")
        try touch("Exports/nested.dng_original")
        try touch("frame.ARW_original")
        try touch("notes.txt_original")
        try touch("dng_original")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("folder.dng_original"),
                                                withIntermediateDirectories: true)
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.orphanBackups.map(\.lastPathComponent), ["gone.dng_original"])
    }

    // The scan does not count a folder or a link named X.dng as a DNG, so the
    // backup beside one has no DNG.
    func testABackupBesideAFolderOrALinkNamedLikeItsDNGIsAnOrphan() throws {
        try touch("real.dng")
        try touch("a.dng_original")
        try touch("b.dng_original")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("a.dng"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("b.dng"),
            withDestinationURL: folder.appendingPathComponent("real.dng"))
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs.map(\.lastPathComponent), ["real.dng"])
        XCTAssertEqual(contents.orphanBackups.map(\.lastPathComponent), ["a.dng_original", "b.dng_original"])
    }
}
