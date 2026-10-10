import XCTest

/// Keeps the source of the documentation site honest, with no build of the
/// site. The build needs Xcode's `docc` and takes time, so it is a script,
/// `scripts/build_docs.sh`, and not a test.
///
/// The site is one DocC catalog. Its first page lists every article under
/// `## Topics`, and a page links to another with `<doc:Name>`, where `Name`
/// is the file name of the article with no extension. `docc` reports a link
/// to a page that is not there only as a warning, at build time. These tests
/// find it at test time, and they find two things that `docc` cannot know:
/// a test and a path of the repo that a page quotes, and that are gone.
final class DocsSiteTests: XCTestCase {
    /// The catalog of the module `DesqueezeCore`.
    static let catalog = DocsCheckTests.root.appendingPathComponent("Sources/DesqueezeCore/DesqueezeCore.docc")
    /// The first page of the site. Its title is the module, not an article.
    static let firstPage = "DesqueezeCore"

    // MARK: The checks

    func testEveryArticleInTheTopicsOfTheFirstPageExists() throws {
        let pages = try Self.pages()
        let topics = Self.topics(in: try XCTUnwrap(pages[Self.firstPage], "the first page is missing"))
        XCTAssertFalse(topics.isEmpty, "the first page names no article under Topics")
        for name in topics {
            XCTAssertNotNil(pages[name], "the first page names <doc:\(name)>, and \(name).md is not in the catalog")
        }
    }

    // A page that the first page does not name gets a place that `docc`
    // chooses, outside the two groups for the two readers.
    func testEveryArticleIsInTheTopicsOfTheFirstPage() throws {
        let pages = try Self.pages()
        let topics = Set(Self.topics(in: try XCTUnwrap(pages[Self.firstPage])))
        for name in pages.keys.sorted() where name != Self.firstPage {
            XCTAssertTrue(topics.contains(name), "\(name).md is not under Topics on the first page")
        }
    }

    func testEveryLinkBetweenPagesPointsToAPage() throws {
        let pages = try Self.pages()
        for (page, text) in pages.sorted(by: { $0.key < $1.key }) {
            for name in Self.links(in: text) {
                XCTAssertNotNil(pages[name], "\(page).md links to <doc:\(name)>, and \(name).md is not in the catalog")
            }
        }
    }

    // A page names the test that guards a rule. A test that was renamed
    // would leave the page with a guard that does not exist.
    func testEveryTestThatAPageQuotesExists() throws {
        let tests = try Self.testSources()
        for (page, text) in try Self.pages().sorted(by: { $0.key < $1.key }) {
            for name in Self.quotedTests(in: text) {
                let declaration = name.hasPrefix("test") ? "func \(name)(" : "class \(name)"
                XCTAssertTrue(tests.contains(declaration), "\(page).md quotes `\(name)`, and no test file has \"\(declaration)\"")
            }
        }
    }

    func testEveryPathOfTheRepoThatAPageQuotesExists() throws {
        for (page, text) in try Self.pages().sorted(by: { $0.key < $1.key }) {
            for path in Self.quotedPaths(in: text) {
                XCTAssertTrue(FileManager.default.fileExists(atPath: DocsCheckTests.root.appendingPathComponent(path).path),
                              "\(page).md quotes `\(path)`, and the repo has no such path")
            }
        }
    }

    // MARK: The readers, on text

    func testTheLinkReaderGivesTheNameOfEachArticleWithNoHeading() {
        XCTAssertEqual(Self.links(in: "Read <doc:GettingStarted>, then <doc:Testing#The-fixtures>.\n- <doc:Architecture>"),
                       ["GettingStarted", "Testing", "Architecture"])
        XCTAssertEqual(Self.links(in: "A symbol is no page: ``DesqueezeJob``. A tag is no link: <folder>."), [])
    }

    func testTheTopicsReaderTakesOnlyTheLinksUnderTheTopicsHeading() {
        let page = "# ``Module``\n\nSee <doc:Above>.\n\n## Topics\n\n### A group\n\n- <doc:One>\n- <doc:Two>\n- ``Symbol``\n"
        XCTAssertEqual(Self.topics(in: page), ["One", "Two"])
        XCTAssertEqual(Self.topics(in: "# A page\n\nSee <doc:Above>.\n"), [], "a page with no Topics heading names none")
    }

    func testTheReaderOfQuotedTestsTakesTestFunctionsAndTestClasses() {
        let text = "Guards: `testAFailedCheckRestoresTheBackup`, and `AdobeDriftTests`. Not `Tests/DesqueezeCoreTests/`, "
            + "not `testing`, and not `swift test`."
        XCTAssertEqual(Self.quotedTests(in: text), ["testAFailedCheckRestoresTheBackup", "AdobeDriftTests"])
    }

    func testTheReaderOfQuotedPathsTakesOnlyPathsOfTheRepo() {
        let text = "`README.md`, `docs/architecture.md`, `Sources/DesqueezeCore/AdobeMatch.swift` and `scripts/`. "
            + "Not `/opt/homebrew/bin`, not `build/docs/`, not `MCPServer/.build/release/desqueeze-mcp`, "
            + "not `<name>.dng`, not `fixtures/`, and not `swift build -c release`."
        XCTAssertEqual(Self.quotedPaths(in: text),
                       ["README.md", "docs/architecture.md", "Sources/DesqueezeCore/AdobeMatch.swift", "scripts/"])
    }

    // MARK: Reading

    /// The text of each Markdown file of the catalog, by its name with no
    /// extension.
    static func pages() throws -> [String: String] {
        var pages: [String: String] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: catalog.path) where name.hasSuffix(".md") {
            pages[String(name.dropLast(3))] = try String(contentsOf: catalog.appendingPathComponent(name), encoding: .utf8)
        }
        return pages
    }

    /// The article that each `<doc:Name>` of the text names, in order. A
    /// link to a heading, `<doc:Name#Heading>`, names its page.
    static func links(in text: String) -> [String] {
        text.matches(of: #/<doc:([A-Za-z0-9_-]+)(#[^>]*)?>/#).map { String($0.1) }
    }

    /// The links after the heading `## Topics`. None when there is no such
    /// heading.
    static func topics(in text: String) -> [String] {
        guard let heading = text.range(of: "\n## Topics\n") else { return [] }
        return links(in: String(text[heading.upperBound...]))
    }

    /// Each test function (`testSomething`) and each test class
    /// (`SomethingTests`) that the text quotes in backticks, in order.
    static func quotedTests(in text: String) -> [String] {
        text.matches(of: #/`(test[A-Z][A-Za-z0-9]*|[A-Z][A-Za-z0-9]*Tests)`/#).map { String($0.1) }
    }

    /// Each path of the repo that the text quotes in backticks, in order:
    /// a document at the root, or a path under a folder that is in git. A
    /// build folder, `fixtures/`, and a path with a placeholder are no such
    /// path.
    static func quotedPaths(in text: String) -> [String] {
        let rootFiles: Set = ["README.md", "CLAUDE.md", "AGENTS.md", "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md",
                              "THIRD_PARTY_NOTICES.md", "PROJECT_CHARTER.md", "LICENSE", "Package.swift", "project.yml"]
        let folders = ["Sources/", "Tests/", "docs/", "scripts/", "MCPServer/", "App/", ".github/"]
        return text.matches(of: #/`([A-Za-z0-9_.\/-]+)`/#).map { String($0.1) }.filter { path in
            if rootFiles.contains(path) { return true }
            return folders.contains(where: path.hasPrefix) && !path.contains("/.build/")
        }
    }

    /// Every test file of the three suites, as one text.
    static func testSources() throws -> String {
        var text = ""
        for folder in ["Tests", "MCPServer/Tests", "App/PlateworksDesqueezeTests"] {
            let url = DocsCheckTests.root.appendingPathComponent(folder)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil),
                                      "\(folder) could not be read")
            for case let file as URL in files where file.pathExtension == "swift" {
                text += try String(contentsOf: file, encoding: .utf8)
            }
        }
        return text
    }
}
