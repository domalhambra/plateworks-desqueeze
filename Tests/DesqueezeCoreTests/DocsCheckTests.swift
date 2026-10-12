import DesqueezeCore
import XCTest

/// The documentation standard's check, run with the package suite.
///
/// `docs/README.md` must list every document under `docs/`, every path the
/// guide and the docs quote must exist, and `CLAUDE.md` must stay under its
/// token budget. The check is `scripts/docs_check.py`, a copy of the check
/// that the documentation standard defines. Only its header comment differs,
/// and its checks are not edited here. This test only runs it.
final class DocsCheckTests: XCTestCase {
    /// Tests/DesqueezeCoreTests/DocsCheckTests.swift -> repo root.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testDocsAreIndexedAndEveryQuotedPathExists() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "scripts/docs_check.py", Self.root.path,
            "--require", "docs/decisions.md",
            "--require", "docs/architecture.md",
            "--require", "docs/changing-things.md",
            // Gitignored. Present only after scripts/make_fixtures.sh.
            "--known-absent", "fixtures/",
        ]
        process.currentDirectoryURL = Self.root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let report = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "docs_check.py reported findings:\n\(report)")
    }

    // The changelog's newest entry is the version that the tools print. A
    // version that is cut in one place and not in the other fails here.
    func testTheNewestChangelogEntryIsTheCurrentVersion() throws {
        let changelog = try String(contentsOf: Self.root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        XCTAssertEqual(Self.newestVersion(in: changelog), DesqueezeVersion.current,
                       "CHANGELOG.md and DesqueezeVersion.current must hold the same number")
    }

    // The reader itself: an "Unreleased" heading is no version, and the
    // first version heading wins.
    func testTheChangelogReaderTakesTheFirstVersionHeading() {
        XCTAssertEqual(Self.newestVersion(in: "# Changelog\n\n## [Unreleased]\n\n## [0.2.0] - 2027-01-01\n\n## [0.1.0]\n"),
                       "0.2.0")
        XCTAssertEqual(Self.newestVersion(in: "## [0.1.0] - Unreleased\n"), "0.1.0")
        XCTAssertNil(Self.newestVersion(in: "# Changelog\n\n## [Unreleased]\n"))
    }

    // The privacy page of the documentation site (design 16.5). A reader
    // must see how old its statements are, and whom to ask. The first page
    // must say where it is: the site has no footer for such a link.
    func testThePrivacyPageHasItsDateItsContactAndALinkFromTheFirstPage() throws {
        let catalog = Self.root.appendingPathComponent("Sources/DesqueezeCore/DesqueezeCore.docc")
        let page = try String(contentsOf: catalog.appendingPathComponent("Privacy.md"), encoding: .utf8)
        let firstPage = try String(contentsOf: catalog.appendingPathComponent("DesqueezeCore.md"), encoding: .utf8)

        XCTAssertNotNil(page.range(of: #"(?m)^Last updated [0-9]{4}-[0-9]{2}-[0-9]{2}\.$"#, options: .regularExpression),
                        "Privacy.md needs a line of its own with an ISO date: \"Last updated 2026-10-12.\"")
        XCTAssertTrue(page.contains("[dom@plateworks.org](mailto:dom@plateworks.org)"),
                      "Privacy.md must give the contact in full, as a mailto link")
        // The list under Topics is held by `DocsSiteTests`. This is the
        // sentence in the text, above that list.
        let text = firstPage.components(separatedBy: "\n## Topics\n")[0]
        XCTAssertTrue(text.contains("<doc:Privacy>"),
                      "the text of the first page, DesqueezeCore.md, must link to <doc:Privacy>")
    }

    /// The version of the first heading of the form `## [1.2.3]`, the form
    /// that "Keep a Changelog" gives each entry. Nil when there is none.
    static func newestVersion(in changelog: String) -> String? {
        for line in changelog.split(separator: "\n") {
            guard line.hasPrefix("## ["), let end = line.firstIndex(of: "]") else { continue }
            let version = String(line[line.index(line.startIndex, offsetBy: 4)..<end])
            if version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil { return version }
        }
        return nil
    }
}
