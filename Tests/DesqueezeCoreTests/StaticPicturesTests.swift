import XCTest

/// The pictures of a page, for a reader with no JavaScript.
///
/// `docc` writes the text of each page a second time, into a `noscript`
/// element, for a browser with no JavaScript and for a search engine. Its
/// `picture` element there is wrong in two ways: each `source` has a `src`,
/// which a browser ignores in a `picture`, and that `src` holds the path of
/// the checkout in small letters, not the address of the file in the site.
/// The `img` has no `src` at all. So such a reader gets no picture.
///
/// `scripts/fix_static_pictures.py` corrects that after `docc convert`.
/// These tests give it a small site in a temporary folder. They need no
/// build of the real site.
final class StaticPicturesTests: XCTestCase {
    /// The page that `docc` writes for one picture with a light and a dark
    /// variant, at `documentation/module/page/index.html`.
    static let brokenPage = """
        <html><body><noscript><p>Text.</p><picture>\
        <source media="(prefers-color-scheme: light)" src="../../../users/somebody/work/a repo/sources/module/module.docc/resources/window-result@2x.png"/>\
        <source media="(prefers-color-scheme: dark)" src="../../../users/somebody/work/a repo/sources/module/module.docc/resources/window-result~dark@2x.png"/>\
        <img alt="The window after a run." decoding="async" loading="lazy"/></picture></noscript></body></html>
        """

    func testEachSourceGetsTheAddressOfItsFileAndTheImageGetsTheLightOne() throws {
        let site = try Self.site(page: Self.brokenPage,
                                 pictures: ["window-result@2x.png", "window-result~dark@2x.png"])
        let result = try Self.fix(site)
        XCTAssertEqual(result.status, 0, result.words)

        let page = try Self.page(of: site)
        let light = "../../../images/org.example.Module/window-result@2x.png"
        let dark = "../../../images/org.example.Module/window-result~dark@2x.png"
        XCTAssertTrue(page.contains(#"<source media="(prefers-color-scheme: light)" srcset="\#(light) 2x"/>"#), page)
        XCTAssertTrue(page.contains(#"<source media="(prefers-color-scheme: dark)" srcset="\#(dark) 2x"/>"#), page)
        XCTAssertTrue(page.contains(#"<img src="\#(light)" srcset="\#(light) 2x" alt="The window after a run." decoding="async" loading="lazy"/>"#), page)
        XCTAssertFalse(page.contains("somebody"), "the path of the checkout is still in the page")
        XCTAssertTrue(page.contains("<p>Text.</p>"), "the text beside the picture changed")
    }

    // The file system of a Mac does not tell `Window.png` from `window.png`,
    // and a web server does. So the address has the name as the site has it.
    func testTheAddressHasTheNameAsTheSiteWritesIt() throws {
        let site = try Self.site(page: Self.brokenPage,
                                 pictures: ["Window-Result@2x.png", "Window-Result~dark@2x.png"])
        XCTAssertEqual(try Self.fix(site).status, 0)
        let page = try Self.page(of: site)
        XCTAssertTrue(page.contains(#"srcset="../../../images/org.example.Module/Window-Result@2x.png 2x""#), page)
    }

    // docc writes the dark variant first for some pictures. The `img` is
    // what a reader with no `picture` support gets, so it takes the light one.
    func testTheImageTakesTheLightVariantWhenTheDarkOneIsFirst() throws {
        let darkFirst = """
            <html><body><noscript><picture>\
            <source media="(prefers-color-scheme: dark)" src="../../../users/somebody/module.docc/resources/a~dark.png"/>\
            <source media="(prefers-color-scheme: light)" src="../../../users/somebody/module.docc/resources/a.png"/>\
            <img alt="A."/></picture></noscript></body></html>
            """
        let site = try Self.site(page: darkFirst, pictures: ["a.png", "a~dark.png"])
        XCTAssertEqual(try Self.fix(site).status, 0)
        let page = try Self.page(of: site)
        XCTAssertTrue(page.contains(#"<img src="../../../images/org.example.Module/a.png" alt="A."/>"#), page)
    }

    // A picture with one variant has no `source`. docc gives its `img` the
    // wrong address directly.
    func testAPictureWithOneVariantGetsItsAddressOnTheImage() throws {
        let single = """
            <html><body><noscript><picture>\
            <img alt="One." src="../../../users/somebody/module.docc/resources/single shot@2x.png"/></picture></noscript></body></html>
            """
        let site = try Self.site(page: single, pictures: ["Single Shot@2x.png"])
        let result = try Self.fix(site)
        XCTAssertEqual(result.status, 0, result.words)
        let page = try Self.page(of: site)
        // The space is written as %20: a space ends an address in `srcset`.
        let address = "../../../images/org.example.Module/Single%20Shot@2x.png"
        XCTAssertTrue(page.contains(#"<img alt="One." src="\#(address)" srcset="\#(address) 2x"/>"#), page)
        XCTAssertFalse(page.contains("somebody"), page)
        let second = try Self.fix(site)
        XCTAssertEqual(second.status, 0, second.words)
        XCTAssertEqual(try Self.page(of: site), page, "a second run changed the page")
    }

    // The script reads and corrects each page before it writes the first
    // one. A fault on a later page must leave an earlier page as docc made it.
    func testAFaultOnALaterPageLeavesAnEarlierPageUnchanged() throws {
        let site = try Self.site(page: Self.brokenPage,
                                 pictures: ["window-result@2x.png", "window-result~dark@2x.png"])
        let later = site.appendingPathComponent("documentation/module/zzz")
        try FileManager.default.createDirectory(at: later, withIntermediateDirectories: true)
        let faulty = Self.brokenPage.replacingOccurrences(of: "window-result", with: "no-such-file")
        try faulty.write(to: later.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let result = try Self.fix(site)
        XCTAssertEqual(result.status, 1, result.words)
        XCTAssertTrue(result.words.contains("documentation/module/zzz/index.html"), result.words)
        XCTAssertEqual(try Self.page(of: site), Self.brokenPage)
    }

    func testASecondRunChangesNothing() throws {
        let site = try Self.site(page: Self.brokenPage,
                                 pictures: ["window-result@2x.png", "window-result~dark@2x.png"])
        XCTAssertEqual(try Self.fix(site).status, 0)
        let first = try Self.page(of: site)
        let second = try Self.fix(site)
        XCTAssertEqual(second.status, 0, second.words)
        XCTAssertEqual(try Self.page(of: site), first)
    }

    // A later `docc` can write the picture correctly. Then the script has
    // nothing to do, and it must not fail.
    func testAPageThatIsCorrectAlreadyPasses() throws {
        let good = """
            <html><body><noscript><picture>\
            <source media="(prefers-color-scheme: dark)" srcset="../../../images/org.example.Module/a~dark.png"/>\
            <img src="../../../images/org.example.Module/a.png" alt="A."/></picture></noscript></body></html>
            """
        let site = try Self.site(page: good, pictures: ["a.png", "a~dark.png"])
        let result = try Self.fix(site)
        XCTAssertEqual(result.status, 0, result.words)
        XCTAssertEqual(try Self.page(of: site), good)
    }

    func testAPictureWithNoFileInTheSiteStopsTheScript() throws {
        let site = try Self.site(page: Self.brokenPage, pictures: ["window-result@2x.png"])
        let result = try Self.fix(site)
        XCTAssertEqual(result.status, 1, result.words)
        XCTAssertTrue(result.words.contains("window-result~dark@2x.png"), result.words)
        XCTAssertEqual(try Self.page(of: site), Self.brokenPage, "a script that stops must change no page")
    }

    func testTwoFilesWithOneNameStopTheScript() throws {
        let site = try Self.site(page: Self.brokenPage,
                                 pictures: ["window-result@2x.png", "window-result~dark@2x.png"])
        let other = site.appendingPathComponent("images/org.example.Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data().write(to: other.appendingPathComponent("window-result@2x.png"))
        let result = try Self.fix(site)
        XCTAssertEqual(result.status, 1, result.words)
        XCTAssertTrue(result.words.contains("more than one"), result.words)
    }

    // MARK: The small site

    static func site(page: String, pictures: [String]) throws -> URL {
        let site = FileManager.default.temporaryDirectory
            .appendingPathComponent("static pictures \(UUID().uuidString)")
        let pageFolder = site.appendingPathComponent("documentation/module/page")
        let images = site.appendingPathComponent("images/org.example.Module")
        try FileManager.default.createDirectory(at: pageFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try page.write(to: pageFolder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        for name in pictures {
            try Data().write(to: images.appendingPathComponent(name))
        }
        return site
    }

    static func page(of site: URL) throws -> String {
        try String(contentsOf: site.appendingPathComponent("documentation/module/page/index.html"), encoding: .utf8)
    }

    static func fix(_ site: URL) throws -> (status: Int32, words: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "scripts/fix_static_pictures.py", site.path]
        process.currentDirectoryURL = DocsCheckTests.root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let words = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, words)
    }

    override func tearDown() {
        let temporary = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temporary.path)) ?? []
        for name in names where name.hasPrefix("static pictures ") {
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent(name))
        }
    }
}
