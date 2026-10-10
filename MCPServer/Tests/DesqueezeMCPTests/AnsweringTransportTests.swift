import Foundation
import Logging
import MCP
import XCTest
@testable import desqueeze_mcp

/// Stands in for the library's transport of standard input and output.
///
/// Its `send` does what the library's does when the pipe to the client is
/// full: it writes a part of the message, suspends, and writes the rest. It
/// is an actor, as the library's is, so a second `send` can start while the
/// first is suspended.
actor FakePipe: Transport {
    nonisolated let logger = Logger(label: "fake-pipe") { _ in SwiftLogNoOpLogHandler() }
    private let input: AsyncThrowingStream<Data, Swift.Error>
    private let feed: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private let writeTime: Duration
    private let firstSendFails: Bool
    /// Every byte that "standard output" got.
    private var output = Data()
    private(set) var sendsStarted = 0

    /// The client has closed its end: the write fails.
    struct ClosedPipe: Swift.Error {}

    /// - Parameters:
    ///   - writeTime: how long one `send` is suspended.
    ///   - firstSendFails: true makes the first `send` throw after its
    ///     `writeTime`, with nothing written.
    init(writeTime: Duration, firstSendFails: Bool = false) {
        (input, feed) = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        self.writeTime = writeTime
        self.firstSendFails = firstSendFails
    }

    func connect() {}
    func disconnect() {}

    func send(_ data: Data) async throws {
        sendsStarted += 1
        if firstSendFails, sendsStarted == 1 {
            try await Task.sleep(for: writeTime)
            throw ClosedPipe()
        }
        let half = data.count / 2
        output.append(data.prefix(half))
        try await Task.sleep(for: writeTime)
        output.append(data.dropFirst(half))
        output.append(0x0A)
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> { input }

    /// One line from the client.
    nonisolated func read(_ line: String) {
        feed.yield(Data(line.utf8))
    }

    /// The client closes its end: standard input ends.
    nonisolated func endInput() {
        feed.finish()
    }

    /// "Standard output" so far, one item for each line end.
    var lines: [String] {
        var lines = String(decoding: output, as: UTF8.self).components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}

/// What happened in a test, in order.
final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func add(_ event: String) {
        lock.withLock { events.append(event) }
    }

    var all: [String] {
        lock.withLock { events }
    }

    func has(_ event: String) -> Bool {
        all.contains(event)
    }
}

/// The transport between the library and standard input and output, with a
/// stand-in for the pipes. No test here starts a process or reads a folder.
final class AnsweringTransportTests: XCTestCase {
    struct TimedOut: Error, CustomStringConvertible {
        let description: String
    }

    static func request(_ id: Int, _ method: String = "tools/call") -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)"}"#
    }

    static func answer(_ id: Int, text: String = "done") -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"result":{"text":"\#(text)"}}"#
    }

    static let progress = #"{"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}"#

    /// Waits until `condition` holds. No wait in these tests is without a
    /// limit: a transport that hangs fails its test.
    func eventually(_ what: String, timeout: TimeInterval = 5, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            guard Date() < deadline else { throw TimedOut(description: "Not in \(timeout) seconds: \(what)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Does what the library's message loop does: it reads each message, and
    /// it ends when the stream ends. The program ends after that.
    func consume(_ transport: AnsweringTransport, into events: Events) async {
        let stream = await transport.receive()
        Task {
            do {
                for try await _ in stream { events.add("read") }
                events.add("stream ended")
            } catch {
                events.add("stream failed")
            }
        }
    }

    /// Sends `message` and then notes `event`. A send that fails is noted
    /// too, so it fails the test that compares the events.
    static func send(_ message: String, through transport: AnsweringTransport, then event: String,
                     into events: Events) async {
        do {
            try await transport.send(Data(message.utf8))
            events.add(event)
        } catch {
            events.add("send failed: \(error)")
        }
    }

    // MARK: One send at a time

    // The library's `send` suspends in the middle of a message when the pipe
    // is full. A second message that starts then breaks both lines.
    func testASendCompletesBeforeTheNextStarts() async throws {
        let pipe = FakePipe(writeTime: .milliseconds(10))
        let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: CallQueue())
        let messages = (1...8).map { Self.answer($0, text: String(repeating: "x", count: 100 + $0)) } + [Self.progress]

        try await withThrowingTaskGroup(of: Void.self) { group in
            for message in messages {
                group.addTask { try await transport.send(Data(message.utf8)) }
            }
            try await group.waitForAll()
        }

        let lines = await pipe.lines
        XCTAssertEqual(lines.count, messages.count)
        XCTAssertEqual(Set(lines), Set(messages), "each line of standard output is one whole message")
    }

    // A write that fails must hand the pipe over to the next message, as a
    // write that passes does. Without the hand-over, no message is ever
    // written again, and each later send waits for ever.
    func testAfterASendThatFailsTheNextSendStillGoesOut() async throws {
        let pipe = FakePipe(writeTime: .milliseconds(200), firstSendFails: true)
        let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: CallQueue())
        let events = Events()

        Task { await Self.send(Self.answer(1), through: transport, then: "first written", into: events) }
        try await eventually("the first send is in work") { await pipe.sendsStarted == 1 }
        // This one arrives while the first is in work, and waits for it.
        Task { await Self.send(Self.answer(2), through: transport, then: "second written", into: events) }

        try await eventually("the second message is written", timeout: 3) { events.has("second written") }
        XCTAssertEqual(events.all.count, 2, "\(events.all)")
        XCTAssertEqual(events.all.first?.hasPrefix("send failed"), true, "\(events.all)")

        // This one arrives when nothing is in work.
        Task { await Self.send(Self.answer(3), through: transport, then: "third written", into: events) }
        try await eventually("the third message is written", timeout: 3) { events.has("third written") }
        let lines = await pipe.lines
        XCTAssertEqual(lines, [Self.answer(2), Self.answer(3)], "each line is one whole message")
    }

    // MARK: A send in work

    // Standard input closes while a message is on its way to a client that
    // reads slowly. The stream stays open, so the program does not end with
    // half a line written. The first message is an answer. The second is
    // not: no request waits for it.
    func testTheStreamStaysOpenUntilASendInWorkCompletes() async throws {
        for message in [Self.answer(1), Self.progress] {
            let pipe = FakePipe(writeTime: .milliseconds(400))
            let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: CallQueue(),
                                               patience: .milliseconds(40))
            let events = Events()
            await consume(transport, into: events)
            pipe.read(Self.request(1))
            try await eventually("the request is read") { events.has("read") }

            Task { await Self.send(message, through: transport, then: "written", into: events) }
            try await eventually("the send is in work") { await pipe.sendsStarted == 1 }
            pipe.endInput()

            try await eventually("the stream ends, and the message is written") {
                events.has("stream ended") && events.has("written")
            }
            XCTAssertEqual(events.all, ["read", "written", "stream ended"], message)
            let lines = await pipe.lines
            XCTAssertEqual(lines, [message])
        }
    }

    // MARK: A call in work

    // The idle rule. Standard input closes while a call is in work, and the
    // call lasts longer than the transport waits for an answer that no call
    // is working on. The stream stays open until the answer is written.
    func testTheStreamStaysOpenWhileACallIsInWorkLongerThanThePatience() async throws {
        let pipe = FakePipe(writeTime: .milliseconds(1))
        let queue = CallQueue()
        let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: queue, patience: .milliseconds(40))
        let events = Events()
        await consume(transport, into: events)
        pipe.read(Self.request(1))
        try await eventually("the request is read") { events.has("read") }

        Task {
            _ = await queue.run { () -> Int? in
                Thread.sleep(forTimeInterval: 0.4)
                events.add("call done")
                return 1
            }
            await Self.send(Self.answer(1), through: transport, then: "written", into: events)
        }
        try await eventually("the call is in work") { !queue.isIdle }
        pipe.endInput()

        try await eventually("the stream ends") { events.has("stream ended") }
        XCTAssertEqual(events.all, ["read", "call done", "written", "stream ended"])
    }

    // MARK: Standard input closes

    // The end of standard input closes the queue, at once and not after the
    // answers. No test reads a flag of the queue: a call is the question.
    // Before the queue closes, a call does its work. After it, a call does
    // none. The request here gets no answer, so a transport that closed the
    // queue only after the answers would wait for the patience, 30 seconds.
    func testTheEndOfInputClosesTheQueueSoACallThatComesLaterDoesNoWork() async throws {
        let pipe = FakePipe(writeTime: .milliseconds(1))
        let queue = CallQueue()
        let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: queue, patience: .seconds(30))
        let events = Events()
        await consume(transport, into: events)
        pipe.read(Self.request(1))
        try await eventually("the request is read") { events.has("read") }

        pipe.endInput()
        try await eventually("the end of input closes the queue", timeout: 2) {
            await queue.run { 0 } == nil
        }
        // The one call that did no work is the one answer that will not
        // come, so the stream ends now.
        try await eventually("the stream ends", timeout: 2) { events.has("stream ended") }
    }

    /// How long a test gives the transport to see the end of input, when
    /// nothing shows that it has. Far longer than the transport needs.
    static let timeForTheEndOfInput: Duration = .milliseconds(500)

    // The client has gone. The call in work completes and is answered. The
    // call that waits does not start, gets no answer, and does not hold the
    // program open: a wait for the patience, 30 seconds here, fails the test.
    //
    // The transport alone closes the queue here, and it must do so while
    // the first call is in work. A transport that closes the queue only
    // when the queue is idle lets the second call start after the client
    // has gone: this test fails against that (seen 2026-10-10).
    func testAtTheEndOfInputACallThatWaitsDoesNotStart() async throws {
        let pipe = FakePipe(writeTime: .milliseconds(1))
        let queue = CallQueue()
        let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: queue, patience: .seconds(30))
        let events = Events()
        await consume(transport, into: events)
        pipe.read(Self.request(1))
        pipe.read(Self.request(2))
        try await eventually("both requests are read") { events.all == ["read", "read"] }

        let gate = DispatchSemaphore(value: 0)
        Task {
            _ = await queue.run { () -> Int? in
                events.add("first starts")
                gate.wait()
                return 1
            }
            await Self.send(Self.answer(1), through: transport, then: "first answered", into: events)
        }
        try await eventually("the first call is in work") { events.has("first starts") }
        Task {
            let result = await queue.run { () -> Int? in
                events.add("second starts")
                return 2
            }
            events.add(result == nil ? "second did no work" : "second worked")
        }
        pipe.endInput()
        // The first call holds the queue, so no call can ask whether the
        // queue is closed yet. The test does not close it: that is the
        // transport's work, and the thing in test. It gives the transport
        // a fixed time for the end of input, and then lets the first call
        // complete.
        try await Task.sleep(for: Self.timeForTheEndOfInput)
        gate.signal()

        try await eventually("the second call ends") {
            events.has("second did no work") || events.has("second worked")
        }
        XCTAssertFalse(events.has("second starts"), "a call started after the client had gone: \(events.all)")
        XCTAssertTrue(events.has("second did no work"), "\(events.all)")
        try await eventually("the stream ends") { events.has("stream ended") }
        XCTAssertLessThan(try XCTUnwrap(events.all.firstIndex(of: "first answered")),
                          try XCTUnwrap(events.all.firstIndex(of: "stream ended")), "\(events.all)")
        let lines = await pipe.lines
        XCTAssertEqual(lines, [Self.answer(1)])
    }

    // A run that the client cancelled still gives its report: it stops after
    // its current file and says `stopped`. With the end of input right
    // behind the cancel, that answer is written before the stream ends.
    func testACallInWorkThatWasCancelledIsAnsweredBeforeTheStreamEnds() async throws {
        let pipe = FakePipe(writeTime: .milliseconds(1))
        let queue = CallQueue()
        let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: queue, patience: .milliseconds(40))
        let events = Events()
        await consume(transport, into: events)
        pipe.read(Self.request(1))
        try await eventually("the request is read") { events.has("read") }

        let gate = DispatchSemaphore(value: 0)
        Task {
            _ = await queue.run { () -> Int? in
                gate.wait()
                return 1
            }
            await Self.send(Self.answer(1), through: transport, then: "written", into: events)
        }
        try await eventually("the call is in work") { !queue.isIdle }
        pipe.read(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#)
        pipe.endInput()
        try await eventually("the cancel is read") { events.all.filter { $0 == "read" }.count == 2 }

        // Longer than the patience. The call is in work, so the stream is open.
        try await Task.sleep(for: .milliseconds(150))
        let early = events.all
        gate.signal()
        XCTAssertEqual(early, ["read", "read"], "the stream is open while the cancelled call completes its file")

        try await eventually("the stream ends") { events.has("stream ended") }
        XCTAssertEqual(events.all, ["read", "read", "written", "stream ended"])
    }

    // A request that the library never answers does not hold the program
    // open for longer than the patience.
    func testARequestWithNoAnswerHoldsTheStreamOpenForThePatienceOnly() async throws {
        let pipe = FakePipe(writeTime: .milliseconds(1))
        let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: CallQueue(),
                                           patience: .milliseconds(100))
        let events = Events()
        await consume(transport, into: events)
        pipe.read(Self.request(1, "ping"))
        try await eventually("the request is read") { events.has("read") }
        let start = Date()
        pipe.endInput()

        try await eventually("the stream ends") { events.has("stream ended") }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.1, "it waits for the patience")
    }

    // MARK: A signal

    // A signal ends the reading as the end of input does: the answer in
    // work is written, and then the stream ends. Standard input is open.
    func testStopReadingEndsTheStreamAfterTheAnswerInWork() async throws {
        let pipe = FakePipe(writeTime: .milliseconds(200))
        let queue = CallQueue()
        let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: queue, patience: .seconds(30))
        let events = Events()
        await consume(transport, into: events)
        pipe.read(Self.request(1))
        try await eventually("the request is read") { events.has("read") }

        Task { await Self.send(Self.answer(1), through: transport, then: "written", into: events) }
        try await eventually("the send is in work") { await pipe.sendsStarted == 1 }
        await transport.stopReading()

        try await eventually("the stream ends") { events.has("stream ended") }
        XCTAssertEqual(events.all, ["read", "written", "stream ended"])
        let late: Int? = await queue.run { 1 }
        XCTAssertNil(late, "no call starts after a signal")
    }

    // A signal can come before the library has asked for the stream: the
    // watcher is set up before the server starts. The reading that starts
    // after it must end at once. Standard input stays open here, so only
    // the signal can end the stream.
    func testStopReadingBeforeTheReadingStartsStillEndsTheStream() async throws {
        let pipe = FakePipe(writeTime: .milliseconds(1))
        defer { pipe.endInput() }
        let queue = CallQueue()
        let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: queue, patience: .seconds(30))
        let events = Events()

        await transport.stopReading()
        await consume(transport, into: events)

        try await eventually("the stream ends", timeout: 2) { events.has("stream ended") }
        XCTAssertEqual(events.all, ["stream ended"])
        let late: Int? = await queue.run { 1 }
        XCTAssertNil(late, "no call starts after a signal")
    }

    // With nothing in work, the stream ends at once.
    func testStopReadingWithNothingInWorkEndsTheStreamAtOnce() async throws {
        let pipe = FakePipe(writeTime: .milliseconds(1))
        let transport = AnsweringTransport(inner: pipe, logger: pipe.logger, queue: CallQueue(), patience: .seconds(30))
        let events = Events()
        await consume(transport, into: events)

        await transport.stopReading()

        try await eventually("the stream ends", timeout: 2) { events.has("stream ended") }
        XCTAssertEqual(events.all, ["stream ended"])
    }
}
