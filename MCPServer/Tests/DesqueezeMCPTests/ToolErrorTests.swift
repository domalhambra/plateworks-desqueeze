import DesqueezeCore
import XCTest

/// Each tool error of design 12.2: `isError` is true, the text is a plain
/// sentence and not JSON, and no file changed.
///
/// These tests need exiftool, because a server with no exiftool gives that
/// error first. They need no photo: the folder holds two small files, and a
/// call that reached a tool by mistake would change them or fail on them.
final class ToolErrorTests: ServerTestCase {
    var server: ServerProcess!
    var before: [String: [String]] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        try requireExiftool()
        try Data("a photo".utf8).write(to: folder.appendingPathComponent("a.dng"))
        try Data("a raw photo".utf8).write(to: folder.appendingPathComponent("b.ARW"))
        before = try state(of: folder)
        server = try start()
    }

    /// Calls the tool, and checks that the call is a tool error that changed
    /// nothing. Returns the sentence.
    func refused(_ name: String, _ arguments: [String: Any], file: StaticString = #filePath,
                 line: UInt = #line) throws -> String {
        let result = try call(server, name, arguments, progressToken: "none", timeout: ServerProcess.shortWait,
                              file: file, line: line)
        XCTAssertTrue(result.isError, "isError must be true: \(result.text)", file: file, line: line)
        XCTAssertEqual(result.progress.count, 0, "no step was done", file: file, line: line)
        XCTAssertFalse(result.text.hasPrefix("{"), "a sentence, not JSON", file: file, line: line)
        XCTAssertTrue(result.text.hasSuffix("."), "a whole sentence: \(result.text)", file: file, line: line)
        XCTAssertEqual(try state(of: folder), before, "no file changed", file: file, line: line)
        XCTAssertEqual(try names(in: discard), [], file: file, line: line)
        return result.text
    }

    // MARK: The folder

    func testARelativeFolderIsRefused() throws {
        for path in ["Shoot with spaces", "./photos", "~/Pictures", ".", ""] {
            for (name, arguments) in calls(folder: path) {
                let text = try refused(name, arguments)
                XCTAssertTrue(text.contains("absolute path"), "\(name) \(path): \(text)")
            }
        }
    }

    func testAFolderThatDoesNotExistIsRefused() throws {
        let missing = base.appendingPathComponent("No such folder").path
        for (name, arguments) in calls(folder: missing) {
            let text = try refused(name, arguments)
            XCTAssertEqual(text, "This folder could not be read: \(missing). Nothing is at this path.", name)
        }
    }

    func testAFileIsRefused() throws {
        let file = folder.appendingPathComponent("a.dng").path
        for (name, arguments) in calls(folder: file) {
            let text = try refused(name, arguments)
            XCTAssertEqual(text, "This folder could not be read: \(file). It is a file, not a folder.", name)
        }
    }

    func testAPackageIsRefused() throws {
        let package = base.appendingPathComponent("Thing.app")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("a photo".utf8).write(to: package.appendingPathComponent("inside.dng"))
        for (name, arguments) in calls(folder: package.path) {
            let text = try refused(name, arguments)
            XCTAssertTrue(text.hasPrefix("This folder could not be read: \(package.path). It is a package"),
                          "\(name): \(text)")
        }
        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent("inside.dng")), Data("a photo".utf8))
    }

    /// The three tools, each with `folder` and with what else it needs.
    func calls(folder path: String) -> [(String, [String: Any])] {
        [("desqueeze_scan", ["folder": path]),
         ("desqueeze_run", ["folder": path, "factor": 1.5]),
         ("desqueeze_run", ["folder": path, "factor": 1.5, "dry_run": true]),
         ("desqueeze_remove", ["folder": path])]
    }

    // MARK: The factor

    func testARunWithNoFactorIsRefused() throws {
        let text = try refused("desqueeze_run", ["folder": folder.path])
        XCTAssertTrue(text.contains("factor"), text)
        XCTAssertTrue(text.contains("There is no default"), text)
    }

    func testAFactorThatIsNotANumberIsRefused() throws {
        let wrong: [Any] = ["1.5", "", true, NSNull(), [1.5], ["value": 1.5]]
        for value in wrong {
            let text = try refused("desqueeze_run", ["folder": folder.path, "factor": value])
            XCTAssertTrue(text.contains("factor") && text.contains("must be a number"), "\(value): \(text)")
        }
    }

    // A JSON number has no comma, so "1,5" can only come as text. The
    // refusal then adds the core's words about the period, as the command
    // line tool and the window do.
    func testAFactorWithACommaIsRefusedWithTheHintAboutThePeriod() throws {
        XCTAssertEqual(try refused("desqueeze_run", ["folder": folder.path, "factor": "1,5"]),
                       "The argument \"factor\" must be a number, such as 1.5. Text in quotes is not a number. "
                           + "Use a period for the decimal point.")
        XCTAssertEqual(try refused("desqueeze_run", ["folder": folder.path, "factor": "1.5"]),
                       "The argument \"factor\" must be a number, such as 1.5. Text in quotes is not a number.")
    }

    func testAFactorOutsideTheRuleIsRefused() throws {
        // Below 1, above 4, and more than four decimal places.
        let wrong: [Any] = [0, 0.5, 0.9999, 4.0001, 5, -1.5, 1e9, 1.33333, 1.00001, 2.123456789]
        for value in wrong {
            let text = try refused("desqueeze_run", ["folder": folder.path, "factor": value, "dry_run": true])
            XCTAssertTrue(text.hasPrefix("The factor must be a number from 1 to 4, with at most four decimal places."),
                          "\(value): \(text)")
            XCTAssertTrue(text.contains(" It was "), "the wording of the tool, from the core: \(text)")
        }
        // The same sentence as the command line tool's, with the text as given.
        XCTAssertEqual(try refused("desqueeze_run", ["folder": folder.path, "factor": 5, "dry_run": true]),
                       "The factor must be a number from 1 to 4, with at most four decimal places. It was \"5\".")
        XCTAssertEqual(try refused("desqueeze_run", ["folder": folder.path, "factor": 1.33333, "dry_run": true]),
                       "The factor must be a number from 1 to 4, with at most four decimal places. It was \"1.33333\".")
    }

    // MARK: The arguments

    func testAnUnknownArgumentIsRefused() throws {
        let scan = try refused("desqueeze_scan", ["folder": folder.path, "factor": 1.5])
        XCTAssertTrue(scan.contains("\"factor\""), scan)
        let run = try refused("desqueeze_run", ["folder": folder.path, "factor": 1.5, "dryRun": true])
        XCTAssertTrue(run.contains("\"dryRun\"") && run.contains("dry_run"), "it names the arguments it has: \(run)")
        let remove = try refused("desqueeze_remove", ["folder": folder.path, "convert": false])
        XCTAssertTrue(remove.contains("\"convert\""), remove)
    }

    func testAnArgumentOfTheWrongTypeIsRefused() throws {
        let folderTexts = [
            try refused("desqueeze_scan", ["folder": 5]),
            try refused("desqueeze_scan", ["folder": [folder.path]]),
            try refused("desqueeze_remove", ["folder": true]),
        ]
        for text in folderTexts { XCTAssertTrue(text.contains("\"folder\" must be text"), text) }

        let flagTexts = [
            try refused("desqueeze_run", ["folder": folder.path, "factor": 1.5, "dry_run": "true"]),
            try refused("desqueeze_run", ["folder": folder.path, "factor": 1.5, "convert": 0]),
            try refused("desqueeze_remove", ["folder": folder.path, "dry_run": 1]),
            try refused("desqueeze_remove", ["folder": folder.path, "dry_run": NSNull()]),
        ]
        for text in flagTexts { XCTAssertTrue(text.contains("must be true or false"), text) }
    }

    func testAMissingFolderArgumentIsRefused() throws {
        for name in Self.toolNames {
            let text = try refused(name, name == "desqueeze_run" ? ["factor": 1.5] : [:])
            XCTAssertTrue(text.contains("\"folder\""), "\(name): \(text)")
        }
        // No `arguments` at all.
        let id = try server.send("tools/call", ["name": "desqueeze_scan"])
        XCTAssertTrue(try toolResult(server, id: id, timeout: ServerProcess.shortWait).isError)
    }

    // MARK: A scan that cannot run

    // The folder is there, and it cannot be listed. The scan fails, so every
    // tool gives a tool error, and no file is tried.
    func testAScanThatCannotRunIsAToolError() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        for (name, arguments) in calls(folder: folder.path) {
            let result = try call(server, name, arguments, timeout: ServerProcess.shortWait)
            XCTAssertTrue(result.isError, "\(name): \(result.text)")
            XCTAssertTrue(result.text.hasPrefix("This folder could not be read: \(folder.path). "), result.text)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        XCTAssertEqual(try state(of: folder), before, "no file changed")
    }

    // MARK: One run in a folder at a time (design 13.9)

    // The test process holds the lock that a run takes, as the command line
    // tool or the window does while it works in the folder. The server is
    // another process, so this is the real case.
    func testARunWhileAnotherRunWorksInTheFolderIsAToolErrorAndAScanAndADryRunAreNot() throws {
        let sentence = "Another Desqueeze run is working in this folder. Wait for it to end, then run again."
        guard case .held(let other) = FolderLock.system.take(folder) else { return XCTFail("the lock of the test") }
        defer { other.release() }

        XCTAssertEqual(try refused("desqueeze_run", ["folder": folder.path, "factor": 1.5]), sentence)
        XCTAssertEqual(try refused("desqueeze_run", ["folder": folder.path, "factor": 1.5, "convert": false]), sentence)
        XCTAssertEqual(try refused("desqueeze_remove", ["folder": folder.path]), sentence)

        // A scan and a dry run change no file, so they take no lock.
        let allowed: [(String, [String: Any])] = [
            ("desqueeze_scan", ["folder": folder.path]),
            ("desqueeze_run", ["folder": folder.path, "factor": 1.5, "dry_run": true]),
            ("desqueeze_remove", ["folder": folder.path, "dry_run": true]),
        ]
        for (name, arguments) in allowed {
            let result = try call(server, name, arguments, timeout: ServerProcess.shortWait)
            XCTAssertFalse(result.isError, "\(name): \(result.text)")
        }
        XCTAssertEqual(try state(of: folder), before, "no file changed")

        // The other run ended. The call is a report now, not a refusal: the
        // file is no DNG, so the report holds one file that failed.
        other.release()
        let result = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.5, "convert": false],
                              timeout: ServerProcess.shortWait)
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try result.json()["failed"] as? Int, 1)
        XCTAssertEqual(try state(of: folder), before, "a write that failed leaves the file as it was")
    }

    // After every refusal, the server still works.
    func testTheServerGoesOnAfterAToolError() throws {
        _ = try refused("desqueeze_run", ["folder": folder.path])
        XCTAssertTrue(try server.result(of: "ping").isEmpty)
        XCTAssertEqual(try (server.result(of: "tools/list")["tools"] as? [Any])?.count, 3)
    }
}
