import XCTest
@testable import DesqueezeCore

final class ToolLocatorTests: XCTestCase {
    func locator(path: String? = nil, registered: URL? = nil, present: Set<String>) -> ToolLocator {
        ToolLocator(pathVariable: path, registeredConverterApp: registered, isExecutable: { present.contains($0) })
    }

    func testExiftoolCandidateOrder() {
        let found = locator(path: "/usr/bin:/opt/tools:/usr/local/bin", present: [])
        XCTAssertEqual(found.exiftoolCandidates, [
            "/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool",
            "/usr/bin/exiftool", "/opt/tools/exiftool",
        ])
    }

    func testExiftoolTakesTheFirstExecutableCandidate() {
        let found = locator(path: "/opt/tools", present: ["/usr/local/bin/exiftool", "/opt/tools/exiftool"])
        XCTAssertEqual(found.exiftool()?.path, "/usr/local/bin/exiftool")
    }

    func testConverterPrefersTheRegisteredApp() {
        let registered = URL(fileURLWithPath: "/Users/x/Apps/Adobe DNG Converter.app")
        let binary = "/Contents/MacOS/Adobe DNG Converter"
        let found = locator(registered: registered, present: [
            registered.path + binary, "/Applications/Adobe DNG Converter.app" + binary,
        ])
        XCTAssertEqual(found.dngConverter()?.path, registered.path + binary)
    }

    func testMissingToolsReturnNil() {
        let found = locator(path: "/usr/bin", present: [])
        XCTAssertNil(found.exiftool())
        XCTAssertNil(found.dngConverter())
    }

    func testRelativePathEntriesAreNotCandidates() {
        let found = locator(path: "bin:.:~/bin::/opt/tools", present: [])
        XCTAssertEqual(found.exiftoolCandidates, [
            "/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/opt/tools/exiftool",
        ])
    }

    // The window and the command line tool both say these words (design,
    // sections 6 and 8).
    func testTheWordsForAMissingExiftool() {
        XCTAssertEqual(ToolLocator.exiftoolMissing, "Desqueeze needs exiftool, and it is not installed.")
        XCTAssertEqual(ToolLocator.exiftoolInstallCommand, "brew install exiftool")
    }

    func testTheStandardConverterAppIsListedOnce() {
        let registered = URL(fileURLWithPath: "/Applications/Adobe DNG Converter.app/")
        XCTAssertEqual(locator(registered: registered, present: []).converterApps,
                       ["/Applications/Adobe DNG Converter.app"])
    }
}
