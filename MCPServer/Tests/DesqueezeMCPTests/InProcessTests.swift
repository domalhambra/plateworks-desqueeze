import DesqueezeCore
import MCP
import XCTest
@testable import desqueeze_mcp

/// What the program does with its command line and its environment, before
/// it starts a server. These tests call `Program.startup` in the test
/// process: no test starts a server whose backups could go to the Trash.
final class StartupTests: XCTestCase {
    func testAWrongTestVariableStopsTheProgramBeforeItServes() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("startup-\(UUID().uuidString)")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        for value in ["1", "", "relative/folder", file.path, file.path + "/gone"] {
            guard case .stop(let lines, let exitCode) = Program.startup(
                arguments: [], environment: [FileBackups.testFolderVariable: value]) else {
                return XCTFail("\"\(value)\" must stop the program")
            }
            XCTAssertEqual(exitCode, 1, value)
            XCTAssertEqual(lines, [
                "desqueeze-mcp: DESQUEEZE_TEST_BACKUP_FOLDER is set, and its value is not a folder: \"\(value)\". "
                    + "It is for tests only. Unset it, then run again.",
            ])
        }
    }

    func testATestFolderIsSaidOnStandardError() throws {
        let folder = FileManager.default.temporaryDirectory.path
        guard case .serve(_, let notice) = Program.startup(
            arguments: [], environment: [FileBackups.testFolderVariable: folder]) else {
            return XCTFail("a folder that exists must start the server")
        }
        XCTAssertEqual(notice, "Test mode: every file that would go to the Trash goes to \(folder).")
    }

    // In normal use the variable is not set: the backups are the Trash, and
    // the program has nothing to say. Nothing is discarded here.
    func testWithNoVariableTheProgramServesAndSaysNothing() {
        guard case .serve(_, let notice) = Program.startup(arguments: [], environment: ["PATH": "/usr/bin"]) else {
            return XCTFail("no variable must start the server")
        }
        XCTAssertNil(notice)
    }

    func testTheCommandLineIsReadBeforeTheEnvironment() {
        let wrong = [FileBackups.testFolderVariable: "1"]
        guard case .print(let version) = Program.startup(arguments: ["--version"], environment: wrong) else {
            return XCTFail("--version prints")
        }
        XCTAssertEqual(version, "desqueeze-mcp \(DesqueezeVersion.current)")
        guard case .print(let help) = Program.startup(arguments: ["--help"], environment: wrong) else {
            return XCTFail("--help prints")
        }
        XCTAssertEqual(help, Program.help)
        guard case .stop(_, let exitCode) = Program.startup(arguments: ["--json"], environment: wrong) else {
            return XCTFail("an unknown flag stops the program")
        }
        XCTAssertEqual(exitCode, 2, "a usage error, whatever the environment holds")
    }
}

/// A Mac with no exiftool: every tool gives a tool error with the install
/// command, and starts no program. The built server cannot show this on a
/// Mac that has exiftool, so these tests call the handler in the test
/// process, with a locator that finds nothing.
final class MissingExiftoolTests: XCTestCase {
    /// Fails the test when the server starts a program.
    struct NoProgram: ProcessRunner {
        func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
            XCTFail("started \(executable.path)")
            return ProcessResult(exitCode: 1, stdout: "", stderr: "")
        }
    }

    struct MustNotDiscard: Error {}

    var folder: URL!
    var handlers: ToolHandlers!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("desqueeze-mcp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("a photo".utf8).write(to: folder.appendingPathComponent("a.dng"))
        let environment = ToolEnvironment(
            locator: ToolLocator(pathVariable: "/usr/bin:/bin", isExecutable: { _ in false }),
            runner: NoProgram(),
            backups: FileBackups(trash: { _ in throw MustNotDiscard() }))
        handlers = ToolHandlers(environment: environment, queue: CallQueue())
    }

    override func tearDown() {
        guard let folder, folder.lastPathComponent.hasPrefix("desqueeze-mcp-tests-") else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    func testEveryToolGivesTheInstallCommandAndStartsNoProgram() async throws {
        let calls: [(String, [String: Value])] = [
            ("desqueeze_scan", ["folder": .string(folder.path)]),
            ("desqueeze_run", ["folder": .string(folder.path), "factor": 1.5]),
            ("desqueeze_run", ["folder": .string(folder.path), "factor": 1.5, "dry_run": true]),
            ("desqueeze_remove", ["folder": .string(folder.path)]),
        ]
        for (name, arguments) in calls {
            let result = try await handlers.call(CallTool.Parameters(name: name, arguments: arguments)) { step in
                XCTFail("no step is done: \(step)")
            }

            XCTAssertEqual(result.isError, true, name)
            XCTAssertEqual(result.content, [.text(
                text: "Desqueeze needs exiftool, and it is not installed. Install it with: brew install exiftool",
                annotations: nil, _meta: nil)], name)
        }
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("a.dng")), Data("a photo".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["a.dng"])
    }

    // An argument that is wrong is said first: the model can correct it
    // before the user installs anything.
    func testAWrongArgumentIsSaidBeforeTheMissingExiftool() async throws {
        let result = try await handlers.call(CallTool.Parameters(name: "desqueeze_run", arguments: [
            "folder": .string(folder.path),
        ])) { _ in }

        XCTAssertEqual(result.isError, true)
        XCTAssertEqual(result.content, [.text(
            text: "desqueeze_run needs the argument \"factor\": the squeeze factor of the lens, a number from 1 "
                + "to 4, with at most four decimal places. There is no default.",
            annotations: nil, _meta: nil)])
    }
}

/// A run with a progress token, in the test process, with the real exiftool
/// on copies of the fixture in a temporary folder. Its backups go to a
/// second temporary folder, never to the Trash.
final class ProgressOrderTests: XCTestCase {
    var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("desqueeze-mcp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Shoot"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Discarded"),
                                                withIntermediateDirectories: true)
    }

    override func tearDown() {
        guard let base, base.lastPathComponent.hasPrefix("desqueeze-mcp-tests-") else { return }
        try? FileManager.default.removeItem(at: base)
    }

    // The client takes its time with each progress message. The call must
    // not return before the last one is sent: the library writes the result
    // as soon as the call returns, and a step after the result is a step for
    // a request that the client has closed.
    func testEveryStepIsSentBeforeTheCallReturns() async throws {
        let fixture = ServerTestCase.fixtures.appendingPathComponent("sample.dng")
        guard FileManager.default.fileExists(atPath: fixture.path), ToolLocator().exiftool() != nil else {
            throw XCTSkip("No fixture, or no exiftool.")
        }
        let folder = base.appendingPathComponent("Shoot")
        for number in 1...3 {
            try FileManager.default.copyItem(at: fixture, to: folder.appendingPathComponent("\(number).dng"))
        }
        let backups = try FileBackups.fromEnvironment(
            [FileBackups.testFolderVariable: base.appendingPathComponent("Discarded").path]).backups
        let handlers = ToolHandlers(
            environment: ToolEnvironment(locator: ToolLocator(), runner: SystemProcessRunner(), backups: backups),
            queue: CallQueue())
        let sent = Events()

        let result = try await handlers.call(CallTool.Parameters(
            name: "desqueeze_run", arguments: ["folder": .string(folder.path), "factor": 1.5],
            meta: Metadata(progressToken: .string("slow")))) { step in
            try? await Task.sleep(for: .milliseconds(400))
            sent.add("\(Int(step.params.progress)) of \(Int(step.params.total ?? 0)) \(step.params.message ?? "")")
        }

        XCTAssertEqual(sent.all, ["1 of 3 1.dng", "2 of 3 2.dng", "3 of 3 3.dng"],
                       "every step was sent when the call returned")
        XCTAssertEqual(result.isError, false)
    }
}

/// The queue that keeps the tool calls one behind the other.
final class CallQueueTests: XCTestCase {
    func testNoCallStartsAfterTheQueueIsClosed() async {
        let queue = CallQueue()
        let first = await queue.run { 1 }
        XCTAssertEqual(first, 1)
        XCTAssertTrue(queue.isIdle)
        XCTAssertEqual(queue.callsWithNoWork, 0)

        queue.close()
        let second: Int? = await queue.run {
            XCTFail("the queue is closed")
            return 2
        }

        XCTAssertNil(second)
        XCTAssertTrue(queue.isIdle)
        XCTAssertEqual(queue.callsWithNoWork, 1, "the call did no work, so it gets no answer")
    }

    // The client goes away during a call. The call in work goes on to its
    // end. The call that waits behind it does not start.
    func testClosingLetsTheCallInWorkCompleteAndStartsNoCallThatWaits() async {
        let queue = CallQueue()
        let started = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        async let first = queue.run { () -> Int? in
            started.signal()
            gate.wait()
            return 1
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                started.wait()
                continuation.resume()
            }
        }
        async let second: Int? = queue.run {
            XCTFail("the queue was closed before this call started")
            return 2
        }

        queue.close()
        gate.signal()

        let results = await [first, second]
        XCTAssertEqual(results, [1, nil])
        await queue.waitForCallInWork()
        XCTAssertTrue(queue.isIdle)
        XCTAssertEqual(queue.callsWithNoWork, 1)
    }

    // A signal: the queue closes, and the call in work is told to stop. A
    // call that is not in work is not told.
    func testStopTellsTheCallInWorkAndNoOther() async {
        let queue = CallQueue()
        let told = Events()
        let started = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        _ = await queue.run(onStop: { told.add("a call that has completed") }) { 0 }
        async let first = queue.run(onStop: {
            told.add("the call in work")
            stopped.signal()
        }) { () -> Int? in
            started.signal()
            // The work goes on until it is told to stop.
            return stopped.wait(timeout: .now() + 10) == .success ? 1 : -1
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                started.wait()
                continuation.resume()
            }
        }
        async let second: Int? = queue.run(onStop: { told.add("the call that waits") }) {
            XCTFail("the queue was stopped before this call started")
            return 2
        }

        queue.stop()

        let results = await [first, second]
        XCTAssertEqual(results, [1, nil])
        XCTAssertEqual(told.all, ["the call in work"])
        let late: Int? = await queue.run { 3 }
        XCTAssertNil(late, "a stop closes the queue: no call starts after it")
    }

    // Ten calls that arrive at once. Each one fails the test when another
    // is in work.
    func testCallsRunOneAtATime() async {
        final class Log: @unchecked Sendable {
            let lock = NSLock()
            var inWork = 0
            var done: [Int] = []
        }
        let queue = CallQueue()
        let log = Log()

        await withTaskGroup(of: Void.self) { group in
            for number in 0..<10 {
                group.addTask {
                    _ = await queue.run { () -> Int? in
                        log.lock.withLock {
                            log.inWork += 1
                            XCTAssertEqual(log.inWork, 1, "two calls at once")
                        }
                        Thread.sleep(forTimeInterval: 0.01)
                        log.lock.withLock {
                            log.inWork -= 1
                            log.done.append(number)
                        }
                        return number
                    }
                }
            }
        }

        XCTAssertEqual(log.done.sorted(), Array(0..<10), "every call ran, once")
        XCTAssertTrue(queue.isIdle)
    }
}
