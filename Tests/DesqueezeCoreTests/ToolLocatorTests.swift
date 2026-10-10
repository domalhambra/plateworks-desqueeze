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

    // dnglab is found as exiftool is (design 13.5).
    func testDnglabCandidateOrder() {
        let found = locator(path: "/usr/bin:/opt/tools:/usr/local/bin", present: [])
        XCTAssertEqual(found.dnglabCandidates, [
            "/opt/homebrew/bin/dnglab", "/usr/local/bin/dnglab", "/usr/bin/dnglab", "/opt/tools/dnglab",
        ])
        XCTAssertEqual(locator(path: "bin:.:~/bin::/opt/tools", present: []).dnglabCandidates, [
            "/opt/homebrew/bin/dnglab", "/usr/local/bin/dnglab", "/opt/tools/dnglab",
        ])
    }

    func testDnglabTakesTheFirstExecutableCandidate() {
        let found = locator(path: "/opt/tools", present: ["/usr/local/bin/dnglab", "/opt/tools/dnglab",
                                                          "/opt/homebrew/bin/exiftool"])
        XCTAssertEqual(found.dnglab()?.path, "/usr/local/bin/dnglab")
        XCTAssertEqual(found.exiftool()?.path, "/opt/homebrew/bin/exiftool")
    }

    func testConverterPrefersTheRegisteredApp() {
        let registered = URL(fileURLWithPath: "/Somewhere/Apps/Adobe DNG Converter.app")
        let binary = "/Contents/MacOS/Adobe DNG Converter"
        let found = locator(registered: registered, present: [
            registered.path + binary, "/Applications/Adobe DNG Converter.app" + binary,
        ])
        XCTAssertEqual(found.dngConverter()?.path, registered.path + binary)
    }

    func testMissingToolsReturnNil() {
        let found = locator(path: "/usr/bin", present: [])
        XCTAssertNil(found.exiftool())
        XCTAssertNil(found.dnglab())
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

    // The command line tool and the MCP server say the sentence and the
    // command on one line. The line is made once, here.
    func testTheOneLineForAMissingExiftoolIsTheSentenceThenTheInstallCommand() {
        XCTAssertEqual(ToolLocator.exiftoolMissingLine,
                       "Desqueeze needs exiftool, and it is not installed. Install it with: brew install exiftool")
        XCTAssertEqual(ToolLocator.exiftoolMissingLine,
                       "\(ToolLocator.exiftoolMissing) Install it with: \(ToolLocator.exiftoolInstallCommand)")
    }

    // The install line of dnglab is made once. The advice, the help of the
    // tool and the MCP descriptions say it.
    func testTheInstallLineOfDnglabIsTheSentenceThenTheInstallCommand() {
        XCTAssertEqual(ToolLocator.dnglabInstallLine, "Install dnglab with: brew install dnglab")
        XCTAssertEqual(ToolLocator.dnglabInstallLine, "Install dnglab with: \(ToolLocator.dnglabInstallCommand)")
    }

    func testTheStandardConverterAppIsListedOnce() {
        let registered = URL(fileURLWithPath: "/Applications/Adobe DNG Converter.app/")
        XCTAssertEqual(locator(registered: registered, present: []).converterApps,
                       ["/Applications/Adobe DNG Converter.app"])
    }
}
