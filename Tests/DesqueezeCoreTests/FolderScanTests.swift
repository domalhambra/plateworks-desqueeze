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
        DNGFile(url: folder.appendingPathComponent(name), horizontal: 1, vertical: 1,
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
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs.map(\.lastPathComponent), ["real.dng"])
    }

    func testSortsNamesTheWayFinderDoes() throws {
        for name in ["DSC10.dng", "DSC9.dng", "DSC100.dng"] { try touch(name) }
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs.map(\.lastPathComponent), ["DSC9.dng", "DSC10.dng", "DSC100.dng"])
    }

    func testAnARWIsPendingOnlyWhenNoDNGHasItsBaseName() {
        let arws = ["DSC1.ARW", "dsc2.arw", "DSC3.ARW"].map { folder.appendingPathComponent($0) }
        let pending = FolderScan.pending(arws: arws, dngs: [dng("DSC1.dng"), dng("DSC2.DNG")])
        XCTAssertEqual(pending.map(\.lastPathComponent), ["DSC3.ARW"])
    }

    func testARenamedDNGClaimsItsARWThroughOriginalRawFileName() {
        let arws = ["DSC05680.ARW", "DSC05681.ARW"].map { folder.appendingPathComponent($0) }
        let renamed = dng("261004 Backyard Photos 0022.dng", original: "dsc05680.arw")
        let pending = FolderScan.pending(arws: arws, dngs: [renamed])
        XCTAssertEqual(pending.map(\.lastPathComponent), ["DSC05681.ARW"])
    }

    // The input every real folder produces: the converter records the name in
    // the camera's own letter case.
    func testOriginalRawFileNameInTheCamerasOwnCaseClaimsItsARW() {
        let arws = ["DSC05680.ARW", "DSC05681.ARW"].map { folder.appendingPathComponent($0) }
        let renamed = dng("261004 Backyard Photos 0022.dng", original: "DSC05680.ARW")
        let pending = FolderScan.pending(arws: arws, dngs: [renamed])
        XCTAssertEqual(pending.map(\.lastPathComponent), ["DSC05681.ARW"])
    }

    func testABaseNameWithDotsIsComparedWhole() {
        let arws = ["2026.10.04 a.ARW", "2026.10.04 b.ARW"].map { folder.appendingPathComponent($0) }
        let pending = FolderScan.pending(arws: arws, dngs: [dng("2026.10.04 a.dng")])
        XCTAssertEqual(pending.map(\.lastPathComponent), ["2026.10.04 b.ARW"])
    }

    func testASymlinkIsNotAFile() throws {
        try touch("real.dng")
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("link.dng"),
            withDestinationURL: folder.appendingPathComponent("real.dng"))
        let contents = try FolderScan.contents(of: folder)
        XCTAssertEqual(contents.dngs.map(\.lastPathComponent), ["real.dng"])
    }
}
