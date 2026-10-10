import DesqueezeCore
import Foundation
import XCTest

/// Starts the built `desqueeze` as a child process, as a person or an agent
/// does, against a temporary folder that holds copies of the two fixtures.
///
/// The test target depends on the `desqueeze` target, so the package builds
/// the tool before the tests run. The tool is beside the test bundle.
///
/// Backups never go to the real Trash here: every start sets
/// `DESQUEEZE_TEST_BACKUP_FOLDER` to a folder inside the temporary folder.
class BuiltToolTestCase: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures")
    static let testModeLine = "Test mode: every file that would go to the Trash goes to"

    struct Output {
        let stdout: String
        let stderr: String
        let exitCode: Int32

        /// Standard error with no test mode line.
        var messages: [String] {
            stderr.split(separator: "\n").map(String.init).filter { !$0.hasPrefix(BuiltToolTestCase.testModeLine) }
        }

        /// Standard output as exactly one JSON object. `JSONSerialization`
        /// refuses any other text before or after the object.
        func json(file: StaticString = #filePath, line: UInt = #line) throws -> NSDictionary {
            let object = try JSONSerialization.jsonObject(with: Data(stdout.utf8))
            return try XCTUnwrap(object as? NSDictionary, "standard output is not one JSON object", file: file,
                                 line: line)
        }
    }

    var tool: URL!
    var base: URL!
    var folder: URL!
    var discard: URL!

    override func setUpWithError() throws {
        let locator = ToolLocator()
        for name in ["sample.dng", "sample.ARW"] {
            guard FileManager.default.fileExists(atPath: Self.fixtures.appendingPathComponent(name).path) else {
                throw XCTSkip("No fixtures. Run scripts/make_fixtures.sh with one ARW file.")
            }
        }
        guard locator.exiftool() != nil, locator.dngConverter() != nil else {
            throw XCTSkip("exiftool or Adobe DNG Converter is not installed.")
        }
        tool = Bundle(for: BuiltToolTestCase.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("desqueeze")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: tool.path), "no built tool at \(tool.path)")

        // Links resolved, so a path that the tool prints can be compared.
        base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("desqueeze-e2e-\(UUID().uuidString)")
        folder = base.appendingPathComponent("Shoot with spaces")
        discard = base.appendingPathComponent("Discarded backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: discard, withIntermediateDirectories: true)
    }

    override func tearDown() {
        guard let base, base.lastPathComponent.hasPrefix("desqueeze-e2e-") else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: The folder

    @discardableResult
    func copyFixture(_ name: String, as newName: String) throws -> URL {
        let destination = folder.appendingPathComponent(newName)
        try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(name), to: destination)
        return destination
    }

    func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    /// Every file in the folder: its bytes, and when it was last changed.
    func folderState() throws -> [String: [String]] {
        var state: [String: [String]] = [:]
        for name in try names(in: folder) {
            let url = folder.appendingPathComponent(name)
            let changed = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            state[name] = [try Data(contentsOf: url).base64EncodedString(), String(describing: changed)]
        }
        return state
    }

    /// "already here.dng" has no ARW. "frame.ARW" has no DNG.
    func makeShoot() throws {
        try copyFixture("sample.dng", as: "already here.dng")
        try copyFixture("sample.ARW", as: "frame.ARW")
    }

    /// The six counts of a run report, in the order of the design.
    func counts(_ json: NSDictionary) -> [Int] {
        ["converted", "set", "skipped", "blocked", "failed", "unconvertedARWs"].map { json[$0] as? Int ?? -1 }
    }

    /// What a scan reads now: each DNG and its scale.
    func scales() throws -> [String: String] {
        let json = try desqueeze("scan", folder.path, "--json").json()
        var scales: [String: String] = [:]
        for dng in try XCTUnwrap(json["dngs"] as? [NSDictionary]) {
            scales[try XCTUnwrap(dng["name"] as? String)] = dng["scale"] as? String ?? "unknown"
        }
        return scales
    }

    // MARK: The tool

    func process(_ arguments: [String], workingFolder: URL? = nil, environment: [String: String?] = [:]) -> Process {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        var variables = ProcessInfo.processInfo.environment
        variables[FileBackups.testFolderVariable] = discard.path
        for (name, value) in environment { variables[name] = value }
        process.environment = variables
        if let workingFolder { process.currentDirectoryURL = workingFolder }
        process.standardInput = FileHandle.nullDevice
        return process
    }

    /// Starts the tool and waits for it.
    func desqueeze(_ arguments: String..., workingFolder: URL? = nil,
                   environment: [String: String?] = [:]) throws -> Output {
        try finish(process(arguments, workingFolder: workingFolder, environment: environment), started: { _ in })
    }

    /// Runs `process` to its end and reads both streams while it runs.
    ///
    /// - Parameter started: called once the process is up, with a function
    ///   that returns what standard error holds so far.
    func finish(_ process: Process, started: (@escaping () -> String) throws -> Void) throws -> Output {
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let errText = TextBox()
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errText.append(String(decoding: data, as: UTF8.self)) }
        }
        try process.run()
        try started { errText.value }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        err.fileHandleForReading.readabilityHandler = nil
        errText.append(String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        return Output(stdout: String(decoding: outData, as: UTF8.self), stderr: errText.value,
                      exitCode: process.terminationStatus)
    }
}

final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ more: String) {
        lock.lock()
        text += more
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}
