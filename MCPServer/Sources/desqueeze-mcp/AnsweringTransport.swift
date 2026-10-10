import Foundation
import Logging
import MCP

/// The library's transport for standard input and output, with what design
/// 12.2 asks of the server and the library does not do:
///
/// - **One message is written at a time.** The library's `send` suspends
///   when the pipe to the client is full, and its actor then lets the next
///   message in. Two messages would share one line, and both would be lost.
///   Here a send completes before the next one starts.
/// - **The program does not end with an answer owed.** The library starts a
///   task for each request and ends its message loop at the end of the
///   stream. Without this type, the program would end as soon as standard
///   input closes, also with a call in work, a request that the library has
///   not yet started, or half an answer written. Here the stream stays open
///   until every answer that will come is written.
/// - **A signal ends the reading as the end of input does.** See
///   `stopReading`.
///
/// When the reading ends, the client has gone, or wants the server gone. The
/// queue of the tool calls closes: the call in work completes and is
/// answered, and a call that waits does not start and gets no answer. A
/// request that needs no queue, such as `tools/list`, is answered.
///
/// The transport sees every message in both directions, so it keeps the ids
/// of the requests that have no answer yet. A request that the client
/// cancelled stays in that list: a run in work that is cancelled stops after
/// its current file and still gives its report, and that answer is written
/// before the program ends. A call that did no work gets no answer. The
/// transport cannot see which id that call had, so it takes their number
/// from the queue: that many ids will stay in the list.
///
/// The rule is a count, and not the exact ids, because the handler of a
/// call cannot say its id. The library (swift-sdk 0.12.1) gives a method
/// handler the parameters of the request and nothing else. The id is in
/// `Server.currentHandlerContext`, and it has `package` access there, so
/// this package cannot read it. When a later version of the library opens
/// it, the handler can report the id of a call that did no work, and the
/// transport can take that id out of the list.
actor AnsweringTransport: Transport {
    /// How long the transport waits for an answer that no call is working
    /// on. Only a request that the library never answers can use this time.
    static let patience: Duration = .seconds(2)

    nonisolated let logger: Logger
    private let inner: any Transport
    private let queue: CallQueue
    private let patience: Duration
    /// One id for each request that was read and has no answer yet.
    private var unanswered: [String] = []
    /// The messages that are being written, and those that wait for it.
    private var sendsInWork = 0
    private var isWriting = false
    private var waitingSends: [CheckedContinuation<Void, Never>] = []
    private var reader: Task<Void, Swift.Error>?
    private var readsNoMore = false

    /// - Parameters:
    ///   - inner: reads and writes the messages. Nil is the library's
    ///     transport for standard input and output. A test gives its own.
    ///   - queue: the queue of the tool calls.
    ///   - patience: see `AnsweringTransport.patience`.
    init(inner: (any Transport)? = nil, logger: Logger, queue: CallQueue,
         patience: Duration = AnsweringTransport.patience) {
        self.logger = logger
        self.queue = queue
        self.patience = patience
        self.inner = inner ?? StdioTransport(logger: logger)
    }

    func connect() async throws {
        try await inner.connect()
    }

    func disconnect() async {
        await inner.disconnect()
    }

    func send(_ data: Data) async throws {
        sendsInWork += 1
        // Also when the write fails: a client that closed its end gets no
        // answer, and the program must not wait for one.
        defer {
            sendsInWork -= 1
            for id in Self.messages(in: data).compactMap(Self.answeredRequest) {
                if let index = unanswered.firstIndex(of: id) { unanswered.remove(at: index) }
            }
        }
        // One at a time, in the order in which they came.
        if isWriting {
            await withCheckedContinuation { waitingSends.append($0) }
        } else {
            isWriting = true
        }
        defer {
            if waitingSends.isEmpty {
                isWriting = false
            } else {
                waitingSends.removeFirst().resume()
            }
        }
        try await inner.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        let (stream, continuation) = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        let reader = Task {
            for try await data in await inner.receive() {
                note(data)
                continuation.yield(data)
            }
        }
        self.reader = reader
        if readsNoMore { reader.cancel() }
        let closer = Task {
            let end = await reader.result
            // Standard input closed, or a signal ended the reading.
            queue.close()
            await waitForAnswers()
            if case .failure(let error) = end, !readsNoMore {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in
            reader.cancel()
            closer.cancel()
        }
        return stream
    }

    /// Reads no more messages, as at the end of standard input. For a
    /// signal: a client stops the server with one (design 12.2). The answer
    /// of the call in work is still written, and then the stream ends.
    func stopReading() {
        readsNoMore = true
        reader?.cancel()
    }

    private func note(_ data: Data) {
        unanswered += Self.messages(in: data).compactMap(Self.request)
    }

    /// Returns when every answer that will come is written.
    private func waitForAnswers() async {
        var idleSince: ContinuousClock.Instant?
        while !Task.isCancelled {
            // A call in work will give an answer. A message on its way to a
            // slow client is work too.
            if queue.isIdle, sendsInWork == 0 {
                // A call that did no work gets no answer, and its id stays
                // in the list.
                if unanswered.count <= queue.callsWithNoWork { return }
                let start = idleSince ?? .now
                idleSince = start
                if .now - start > patience {
                    logger.warning("The server ends. No answer came for: \(unanswered.sorted())")
                    return
                }
            } else {
                idleSince = nil
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: The ids in a message

    /// One line is one message, or a batch: a list of messages.
    private static func messages(in data: Data) -> [[String: Any]] {
        switch try? JSONSerialization.jsonObject(with: data) {
        case let message as [String: Any]: return [message]
        case let batch as [Any]: return batch.compactMap { $0 as? [String: Any] }
        default: return []
        }
    }

    /// An id as text. A string and a number never give the same text.
    private static func key(_ id: Any?) -> String? {
        switch id {
        case let text as String: return "\"\(text)\""
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    /// The id of a request: a message with a method and an id.
    private static func request(_ message: [String: Any]) -> String? {
        message["method"] is String ? key(message["id"]) : nil
    }

    /// The id that an answer answers: a message with an id and no method.
    private static func answeredRequest(_ message: [String: Any]) -> String? {
        message["method"] == nil ? key(message["id"]) : nil
    }
}
