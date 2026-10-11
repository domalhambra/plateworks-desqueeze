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

    // MARK: The programs inside the app (design 15.4)

    static let bundledExiftool = "/Somewhere/Desqueeze.app/Contents/Resources/exiftool/exiftool"
    static let bundledDnglab = "/Somewhere/Desqueeze.app/Contents/Helpers/dnglab"
    static let perl = "/usr/bin/perl"

    /// A locator as the downloaded app makes it: with the two places in its
    /// bundle.
    func bundleLocator(path: String? = nil, present: Set<String>) -> ToolLocator {
        ToolLocator(pathVariable: path, bundledExiftool: URL(fileURLWithPath: Self.bundledExiftool),
                    bundledDnglab: URL(fileURLWithPath: Self.bundledDnglab), isExecutable: { present.contains($0) })
    }

    // The versions in the bundle are the tested ones, so a copy from
    // Homebrew does not win over them.
    func testTheBundleComesFirst() {
        let found = bundleLocator(path: "/opt/tools", present: [
            Self.bundledExiftool, Self.bundledDnglab, Self.perl,
            "/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/opt/tools/exiftool",
            "/opt/homebrew/bin/dnglab", "/usr/local/bin/dnglab", "/opt/tools/dnglab",
        ])
        XCTAssertEqual(found.exiftool()?.path, Self.bundledExiftool)
        XCTAssertEqual(found.dnglab()?.path, Self.bundledDnglab)
    }

    // A build from source, the command line tool and the MCP server give
    // no place. Nothing changes for them.
    func testWithNoPlaceGivenTheOrderIsAsBefore() {
        let present: Set<String> = [Self.bundledExiftool, Self.bundledDnglab, Self.perl,
                                    "/usr/local/bin/exiftool", "/opt/tools/exiftool",
                                    "/usr/local/bin/dnglab", "/opt/tools/dnglab"]
        let found = locator(path: "/usr/bin:/opt/tools", present: present)
        XCTAssertEqual(found.exiftool()?.path, "/usr/local/bin/exiftool")
        XCTAssertEqual(found.dnglab()?.path, "/usr/local/bin/dnglab")
        XCTAssertEqual(found.exiftoolCandidates, [
            "/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool", "/opt/tools/exiftool",
        ])
        XCTAssertEqual(found.dnglabCandidates, [
            "/opt/homebrew/bin/dnglab", "/usr/local/bin/dnglab", "/usr/bin/dnglab", "/opt/tools/dnglab",
        ])
        // The places of a bundle add no candidate to the old order.
        let inBundle = bundleLocator(path: "/usr/bin:/opt/tools", present: present)
        XCTAssertEqual(inBundle.exiftoolCandidates, found.exiftoolCandidates)
        XCTAssertEqual(inBundle.dnglabCandidates, found.dnglabCandidates)
    }

    // The exiftool of the bundle is a Perl script that starts with
    // `#!/usr/bin/perl`. With no Perl there, it cannot work.
    func testTheExiftoolOfTheBundleIsTakenOnlyWithTheSystemPerl() {
        XCTAssertEqual(ToolLocator.systemPerl, "/usr/bin/perl")
        let noPerl = bundleLocator(present: [Self.bundledExiftool, Self.bundledDnglab, "/usr/local/bin/exiftool"])
        XCTAssertEqual(noPerl.exiftool()?.path, "/usr/local/bin/exiftool", "the old order, with no Perl of macOS")
        // dnglab is a program of its own. It needs no Perl.
        XCTAssertEqual(noPerl.dnglab()?.path, Self.bundledDnglab)

        let nothingElse = bundleLocator(present: [Self.bundledExiftool, Self.bundledDnglab])
        XCTAssertNil(nothingElse.exiftool(), "no Perl of macOS, and no other exiftool")

        // A Perl at another place does not count: the script names one path.
        let otherPerl = bundleLocator(path: "/opt/tools", present: [Self.bundledExiftool, "/opt/tools/perl",
                                                                     "/opt/homebrew/bin/perl"])
        XCTAssertNil(otherPerl.exiftool())
    }

    func testAPlaceThatCannotBeRunFallsThrough() {
        // A build from source gives the two places too, and has no file
        // there.
        let found = bundleLocator(path: "/opt/tools", present: [
            Self.perl, "/opt/homebrew/bin/exiftool", "/opt/tools/exiftool", "/opt/tools/dnglab",
        ])
        XCTAssertEqual(found.exiftool()?.path, "/opt/homebrew/bin/exiftool")
        XCTAssertEqual(found.dnglab()?.path, "/opt/tools/dnglab")

        // Each program falls through by itself.
        let onlyDnglab = bundleLocator(present: [Self.bundledDnglab, Self.perl, "/usr/local/bin/exiftool"])
        XCTAssertEqual(onlyDnglab.exiftool()?.path, "/usr/local/bin/exiftool")
        XCTAssertEqual(onlyDnglab.dnglab()?.path, Self.bundledDnglab)
        let onlyExiftool = bundleLocator(present: [Self.bundledExiftool, Self.perl, "/usr/local/bin/dnglab"])
        XCTAssertEqual(onlyExiftool.exiftool()?.path, Self.bundledExiftool)
        XCTAssertEqual(onlyExiftool.dnglab()?.path, "/usr/local/bin/dnglab")

        let nothing = bundleLocator(present: [Self.perl])
        XCTAssertNil(nothing.exiftool())
        XCTAssertNil(nothing.dnglab())
    }

    // Adobe DNG Converter is never inside the app (design 15.1).
    func testTheBundleGivesNoPlaceForAdobeDNGConverter() {
        let found = bundleLocator(present: [Self.bundledExiftool, Self.bundledDnglab, Self.perl])
        XCTAssertEqual(found.converterApps, ["/Applications/Adobe DNG Converter.app"])
        XCTAssertNil(found.dngConverter())
    }

    func testTheStandardConverterAppIsListedOnce() {
        let registered = URL(fileURLWithPath: "/Applications/Adobe DNG Converter.app/")
        XCTAssertEqual(locator(registered: registered, present: []).converterApps,
                       ["/Applications/Adobe DNG Converter.app"])
    }
}
