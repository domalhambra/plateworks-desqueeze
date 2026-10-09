import XCTest
@testable import DesqueezeCore

/// Runs the real exiftool and the real Adobe DNG Converter on copies of the
/// two files in `fixtures/`. Skips when a fixture or a tool is absent.
final class IntegrationTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures")

    var folder: URL!
    var exiftool: URL!
    var converterTool: URL!

    override func setUpWithError() throws {
        let locator = ToolLocator()
        let arw = Self.fixtures.appendingPathComponent("sample.ARW")
        let dng = Self.fixtures.appendingPathComponent("sample.dng")
        guard FileManager.default.fileExists(atPath: arw.path),
              FileManager.default.fileExists(atPath: dng.path) else {
            throw XCTSkip("No fixtures. Run scripts/make_fixtures.sh with one ARW file.")
        }
        guard let exiftool = locator.exiftool(), let converterTool = locator.dngConverter() else {
            throw XCTSkip("exiftool or Adobe DNG Converter is not installed.")
        }
        self.exiftool = exiftool
        self.converterTool = converterTool
        folder = try makeTemporaryFolder(named: "Shoot with spaces")
    }

    override func tearDown() {
        if let folder { removeTemporaryFolder(folder) }
    }

    func copyFixture(_ name: String, as newName: String) throws -> URL {
        let destination = folder.appendingPathComponent(newName)
        try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(name), to: destination)
        return destination
    }

    // Tests discard backups for good. The real Trash is checked by hand.
    var backups: FileBackups { FileBackups(trash: { try FileManager.default.removeItem(at: $0) }) }
    var tag: ScaleTag { ScaleTag(exiftool: exiftool) }
    var scanner: FolderScanner { FolderScanner(tag: tag, backups: backups) }
    var job: DesqueezeJob {
        DesqueezeJob(tag: tag, converter: AdobeConverter(executable: converterTool), backups: backups)
    }

    func names(withSuffix suffix: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(suffix) }.sorted()
    }

    func testARealRunConvertsTagsChecksAndClearsTheBackups() throws {
        // "already here.dng" has no ARW. "frame.ARW" has no DNG.
        _ = try copyFixture("sample.dng", as: "already here.dng")
        let arw = try copyFixture("sample.ARW", as: "frame.ARW")
        let arwBefore = try Data(contentsOf: arw)
        let factor = SqueezeFactor(1.5)!

        let first = try scanner.snapshot(of: folder)
        XCTAssertEqual(first.dngs.map(\.name), ["already here.dng"])
        XCTAssertEqual(first.pendingARWs.map(\.lastPathComponent), ["frame.ARW"])

        let summary = job.run(first, factor: factor, convert: true)
        XCTAssertEqual(summary.converted, 1)
        XCTAssertEqual(summary.set, 2)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.notes, [])

        let second = try scanner.snapshot(of: folder)
        XCTAssertEqual(second.dngs.map(\.name), ["already here.dng", "frame.dng"])
        XCTAssertEqual(second.dngs.map(\.horizontal), [1.5, 1.5])
        XCTAssertEqual(second.dngs.map(\.vertical), [1, 1])
        XCTAssertEqual(second.pendingARWs, [])
        XCTAssertEqual(try names(withSuffix: "_original"), [])
        XCTAssertEqual(try names(withSuffix: ".dng"), ["already here.dng", "frame.dng"], "no _1.dng duplicate")
        XCTAssertEqual(try Data(contentsOf: arw), arwBefore, "the ARW must not change")

        let rerun = job.run(second, factor: factor, convert: true)
        XCTAssertEqual(rerun.skipped, 2)
        XCTAssertEqual(rerun.set, 0)
        XCTAssertEqual(rerun.converted, 0)

        let removed = job.run(second, factor: .noStretch, convert: false)
        XCTAssertEqual(removed.set, 2)
        XCTAssertEqual(try scanner.snapshot(of: folder).dngs.map(\.horizontal), [1, 1])
        XCTAssertEqual(try names(withSuffix: "_original"), [])
    }

    func testARenamedDNGStillClaimsItsARW() throws {
        // The fixture DNG was converted from a file named sample.ARW, so its
        // OriginalRawFileName tag is "sample.ARW".
        _ = try copyFixture("sample.dng", as: "261004 Backyard Photos 0022.dng")
        _ = try copyFixture("sample.ARW", as: "sample.ARW")
        let snapshot = try scanner.snapshot(of: folder)
        XCTAssertEqual(snapshot.dngs.first?.originalRawFileName, "sample.ARW")
        XCTAssertEqual(snapshot.pendingARWs, [])
    }
}
