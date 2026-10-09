import XCTest
@testable import DesqueezeCore

final class ScaleTagTests: XCTestCase {
    let exiftool = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool")
    let folder = URL(fileURLWithPath: "/tmp/Shoot 1")
    var runner: FakeRunner!
    var tag: ScaleTag!

    override func setUp() {
        runner = FakeRunner()
        tag = ScaleTag(exiftool: exiftool, runner: runner)
    }

    func testReadFolderPassesTheExactArguments() throws {
        _ = try tag.readFolder(folder)
        XCTAssertEqual(runner.calls, [FakeRunner.Call(executable: exiftool.path, arguments: [
            "-m", "-T", "-filename", "-SubIFD:DefaultScale", "-OriginalRawFileName", "-ext", "dng", "/tmp/Shoot 1",
        ])])
    }

    func testParseRowsReadsScaleAndOriginalName() {
        let rows = ScaleTag.parseRows("one.dng\t1 1\ta.ARW\nTWO.DNG\t1.5 1\tDSC05680.ARW\n")
        XCTAssertEqual(rows, [
            TagRow(fileName: "one.dng", horizontal: 1, vertical: 1, originalRawFileName: "a.ARW"),
            TagRow(fileName: "TWO.DNG", horizontal: 1.5, vertical: 1, originalRawFileName: "DSC05680.ARW"),
        ])
    }

    func testParseRowsDropsHiddenFilesAndReadsDashAsNoValue() {
        let rows = ScaleTag.parseRows(".hidden.dng\t1 1\ta.ARW\nnotag.dng\t-\t-\n\n")
        XCTAssertEqual(rows, [TagRow(fileName: "notag.dng", horizontal: 1, vertical: 1, originalRawFileName: nil)])
    }

    func testWritePassesTheFactorAsOneArgument() throws {
        runner.handler = { _ in
            ProcessResult(exitCode: 0, stdout: "    1 image files updated\n",
                          stderr: "Warning: Error copying hidden data - /tmp/Shoot 1/one.dng\n")
        }
        try tag.write(SqueezeFactor(1.5)!, to: folder.appendingPathComponent("one.dng"))
        XCTAssertEqual(runner.calls.map(\.arguments), [["-m", "-SubIFD:DefaultScale=1.5 1", "/tmp/Shoot 1/one.dng"]])
    }

    func testWriteThrowsTheErrorLineWhenExiftoolFails() {
        runner.handler = { _ in
            ProcessResult(exitCode: 1,
                          stdout: "    0 image files updated\n    1 files weren't updated due to errors\n",
                          stderr: "Error: Not a valid DNG (looks more like a TXT) - /tmp/Shoot 1/junk.dng\n")
        }
        XCTAssertThrowsError(try tag.write(SqueezeFactor(1.5)!, to: folder.appendingPathComponent("junk.dng"))) {
            XCTAssertEqual($0 as? TagError,
                           .toolFailed("Error: Not a valid DNG (looks more like a TXT) - /tmp/Shoot 1/junk.dng"))
        }
    }

    func testWriteThrowsWhenExitIsZeroButNothingWasUpdated() {
        runner.handler = { _ in ProcessResult(exitCode: 0, stdout: "    0 image files updated\n", stderr: "") }
        XCTAssertThrowsError(try tag.write(SqueezeFactor(2)!, to: folder.appendingPathComponent("one.dng")))
    }

    func testReadPassesTheExactArgumentsAndParsesTheValue() throws {
        runner.handler = { _ in ProcessResult(exitCode: 0, stdout: "1.3333 1\n", stderr: "") }
        let value = try tag.read(folder.appendingPathComponent("one.dng"))
        XCTAssertEqual(runner.calls.map(\.arguments), [["-s3", "-SubIFD:DefaultScale", "/tmp/Shoot 1/one.dng"]])
        XCTAssertEqual(value?.horizontal, 1.3333)
        XCTAssertEqual(value?.vertical, 1)
    }

    func testReadReturnsNilWhenTheTagIsAbsent() throws {
        runner.handler = { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "") }
        XCTAssertNil(try tag.read(folder.appendingPathComponent("one.dng")))
    }
}
