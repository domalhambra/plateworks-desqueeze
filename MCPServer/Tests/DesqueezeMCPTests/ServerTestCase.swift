import DesqueezeCore
import Foundation
import XCTest

/// What a `tools/call` gave.
struct ToolResult {
    let isError: Bool
    /// The one text item of the result.
    let text: String
    /// The `params` of each `notifications/progress` that came before the result.
    let progress: [[String: Any]]

    /// The text as one JSON object.
    func json(file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try XCTUnwrap(object as? [String: Any], "the result text is not one JSON object", file: file,
                             line: line)
    }
}

/// Starts the built `desqueeze-mcp`, as Claude Code does, against a temporary
/// folder that can hold copies of the two fixtures.
///
/// The test target depends on the `desqueeze-mcp` target, so the package
/// builds the server before the tests run. The server is beside the test
/// bundle.
///
/// Backups never go to the real Trash here: every server gets
/// `DESQUEEZE_TEST_BACKUP_FOLDER`, set to a folder inside the temporary folder.
class ServerTestCase: XCTestCase {
    /// `fixtures/` at the root of the repository, four levels above this file.
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures")
    static let toolNames = ["desqueeze_scan", "desqueeze_run", "desqueeze_remove"]

    var executable: URL!
    var base: URL!
    var folder: URL!
    var discard: URL!
    /// Every server that the test started. `tearDown` ends each one.
    var servers: [ServerProcess] = []

    override func setUpWithError() throws {
        // A write to a server that has ended must fail the test, not end the
        // test process.
        signal(SIGPIPE, SIG_IGN)
        executable = Bundle(for: ServerTestCase.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("desqueeze-mcp")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path),
                      "no built server at \(executable.path)")

        // Links resolved, so a path that the server prints can be compared.
        base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("desqueeze-mcp-tests-\(UUID().uuidString)")
        folder = base.appendingPathComponent("Shoot with spaces")
        discard = base.appendingPathComponent("Discarded backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: discard, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for server in servers {
            server.stop()
            // Requirement 8, for every test: standard output is the protocol.
            for line in server.outputLines { XCTAssertTrue(Self.isJSONRPC(line), "not a JSON-RPC line: \(line)") }
        }
        servers = []
        guard let base, base.lastPathComponent.hasPrefix("desqueeze-mcp-tests-") else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: base)
    }

    /// True for one JSON object that says `"jsonrpc": "2.0"`.
    static func isJSONRPC(_ line: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
              let message = object as? [String: Any] else { return false }
        return message["jsonrpc"] as? String == "2.0"
    }

    // MARK: Skips

    func requireExiftool() throws {
        guard ToolLocator().exiftool() != nil else { throw XCTSkip("exiftool is not installed.") }
    }

    func requireFixturesAndTools() throws {
        for name in ["sample.dng", "sample.ARW"] {
            guard FileManager.default.fileExists(atPath: Self.fixtures.appendingPathComponent(name).path) else {
                throw XCTSkip("No fixtures. Run scripts/make_fixtures.sh with one ARW file.")
            }
        }
        let locator = ToolLocator()
        guard locator.exiftool() != nil, locator.dngConverter() != nil else {
            throw XCTSkip("exiftool or Adobe DNG Converter is not installed.")
        }
    }

    // MARK: The folder

    @discardableResult
    func copyFixture(_ name: String, as newName: String) throws -> URL {
        let destination = folder.appendingPathComponent(newName)
        try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(name), to: destination)
        return destination
    }

    /// "already here.dng" has no ARW. "frame.ARW" has no DNG.
    func makeShoot() throws {
        try copyFixture("sample.dng", as: "already here.dng")
        try copyFixture("sample.ARW", as: "frame.ARW")
    }

    /// True when dnglab gets the fixture ARW on this Mac (design 13.4):
    /// dnglab is installed, and the frame has a full match. The fixture can
    /// be any Sony ARW, so the answer comes from the frame itself, through
    /// the product's own reader. Adobe DNG Converter gets every other
    /// frame: `requireFixturesAndTools` skips without it. The read changes
    /// no file.
    ///
    /// This expectation is taken from the product: `ARWFactsReader` reads
    /// the facts, and `AdobeMatch` says whether they are a full match. So a
    /// test that uses it pins the choice and the wiring: the built server
    /// gives the ARW to the converter that the core's rule names, and its
    /// report says so. It does not pin the match itself. That is pinned in
    /// the core's tests: the table test,
    /// `AdobeMatchTests.testTheTableIsTheDataFile`, and the drift check,
    /// `AdobeDriftTests`.
    func dnglabConvertsTheFixture() -> Bool {
        let locator = ToolLocator()
        guard locator.dnglab() != nil, let exiftool = locator.exiftool() else { return false }
        let arw = Self.fixtures.appendingPathComponent("sample.ARW")
        return AdobeMatch.match(ARWFactsReader(exiftool: exiftool).read([arw])["sample.ARW"] ?? .none).isFull
    }

    /// `count` DNG files and no ARW: `1.dng`, `2.dng`, and so on.
    func makeDNGs(_ count: Int) throws {
        for number in 1...count { try copyFixture("sample.dng", as: "\(number).dng") }
    }

    func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    /// Every file in `directory`: its size, when it was last changed, and
    /// its bytes.
    func state(of directory: URL) throws -> [String: [String]] {
        var state: [String: [String]] = [:]
        for name in try names(in: directory) {
            let url = directory.appendingPathComponent(name)
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
            let bytes = values.isDirectory == true ? "folder" : try Data(contentsOf: url).base64EncodedString()
            state[name] = [String(describing: values.fileSize), String(describing: values.contentModificationDate),
                           bytes]
        }
        return state
    }

    /// The same work as the server's, done in the test process: the core
    /// with the tools where `ToolLocator` finds them. Its backups function
    /// fails, so this object can never discard a file.
    func operations() throws -> DesqueezeOperations {
        struct MustNotDiscard: Error {}
        let locator = ToolLocator()
        return DesqueezeOperations(
            exiftool: try XCTUnwrap(locator.exiftool()), dnglab: locator.dnglab(),
            dngConverter: locator.dngConverter(),
            backups: FileBackups(trash: { _ in throw MustNotDiscard() }))
    }

    /// What a scan in the test process reads now: each DNG and its scale.
    func scales() throws -> [String: String] {
        var scales: [String: String] = [:]
        for dng in try operations().scan(folder).dngs { scales[dng.name] = dng.scale ?? "unknown" }
        return scales
    }

    // MARK: The server

    /// Starts the server. It does not say hello to it.
    func launch(_ arguments: [String] = [], environment: [String: String?] = [:]) throws -> ServerProcess {
        var variables = ProcessInfo.processInfo.environment
        variables[FileBackups.testFolderVariable] = discard.path
        for (name, value) in environment { variables[name] = value }
        let server = try ServerProcess(executable: executable, arguments: arguments, environment: variables)
        servers.append(server)
        return server
    }

    /// Starts the server and opens the session: `initialize`, then
    /// `notifications/initialized`.
    func start() throws -> ServerProcess {
        let server = try launch()
        _ = try initialize(server)
        return server
    }

    /// - Returns: the result of `initialize`.
    func initialize(_ server: ServerProcess) throws -> [String: Any] {
        let result = try server.result(of: "initialize", [
            "protocolVersion": "2025-06-18",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "desqueeze-mcp-tests", "version": "1"],
        ])
        try server.notify("notifications/initialized")
        return result
    }

    /// The `params` of a `tools/call`.
    func toolCall(_ name: String, _ arguments: [String: Any], progressToken: String? = nil) -> [String: Any] {
        var params: [String: Any] = ["name": name, "arguments": arguments]
        if let progressToken { params["_meta"] = ["progressToken": progressToken] }
        return params
    }

    /// Reads the answer to a `tools/call`. Each message before it must be a
    /// progress message.
    func toolResult(_ server: ServerProcess, id: Int, timeout: TimeInterval = ServerProcess.longWait,
                    file: StaticString = #filePath, line: UInt = #line) throws -> ToolResult {
        let (answer, earlier) = try server.answer(to: id, timeout: timeout)
        return try toolResult(answer, earlier: earlier, file: file, line: line)
    }

    func toolResult(_ answer: [String: Any], earlier: [[String: Any]], file: StaticString = #filePath,
                    line: UInt = #line) throws -> ToolResult {
        let result = try XCTUnwrap(answer["result"] as? [String: Any], "no result: \(answer)", file: file, line: line)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]], file: file, line: line)
        XCTAssertEqual(content.count, 1, "one content item", file: file, line: line)
        XCTAssertEqual(content.first?["type"] as? String, "text", file: file, line: line)
        var progress: [[String: Any]] = []
        for message in earlier {
            XCTAssertEqual(message["method"] as? String, "notifications/progress", "\(message)", file: file,
                           line: line)
            progress.append(message["params"] as? [String: Any] ?? [:])
        }
        return ToolResult(
            isError: try XCTUnwrap(result["isError"] as? Bool, "isError is not in the result", file: file, line: line),
            text: try XCTUnwrap(content.first?["text"] as? String, file: file, line: line),
            progress: progress)
    }

    /// Sends a `tools/call` and reads its answer.
    func call(_ server: ServerProcess, _ name: String, _ arguments: [String: Any], progressToken: String? = nil,
              timeout: TimeInterval = ServerProcess.longWait, file: StaticString = #filePath,
              line: UInt = #line) throws -> ToolResult {
        let id = try server.send("tools/call", toolCall(name, arguments, progressToken: progressToken))
        return try toolResult(server, id: id, timeout: timeout, file: file, line: line)
    }

    /// The six counts of a run report, in the order of the design.
    func counts(_ json: [String: Any]) -> [Int] {
        ["converted", "set", "skipped", "blocked", "failed", "unconvertedARWs"].map { json[$0] as? Int ?? -1 }
    }
}
