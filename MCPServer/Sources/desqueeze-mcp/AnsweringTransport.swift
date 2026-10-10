import Foundation
import Logging
import MCP

/// The library's transport for standard input and output, with one addition:
/// when standard input closes, the stream of messages stays open until every
/// request that was read has its answer written.
///
/// The library starts a task for each request and ends its message loop at
/// the end of the stream. Without this type, the program would end as soon
/// as standard input closes, also with a call in work or a request that the
/// library has not yet started. `desqueeze-mcp < requests.txt` would answer
/// nothing.
///
/// The transport sees every message in both directions, so it keeps the ids
/// of the requests that have no answer yet. A request that the client
/// cancelled is taken out: the library may send no answer for it. The call
/// queue still completes a cancelled run before the program ends.
actor AnsweringTransport: Transport {
    /// How long the transport waits for an answer that no call is working
    /// on. Only a request that the library never answers can use this time.
    static let patience: Duration = .seconds(2)

    nonisolated let logger: Logger
    private let base: StdioTransport
    private let isIdle: @Sendable () -> Bool
    private var unanswered: Set<String> = []

    /// - Parameter isIdle: true when no tool call is in work and none waits.
    init(logger: Logger, isIdle: @escaping @Sendable () -> Bool) {
        self.logger = logger
        self.isIdle = isIdle
        base = StdioTransport(logger: logger)
    }

    func connect() async throws {
        try await base.connect()
    }

    func disconnect() async {
        await base.disconnect()
    }

    func send(_ data: Data) async throws {
        // Also when the write fails: a client that closed its end gets no
        // answer, and the program must not wait for one.
        defer { unanswered.subtract(Self.messages(in: data).compactMap(Self.answeredRequest)) }
        try await base.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        let (stream, continuation) = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        let reader = Task {
            do {
                for try await data in await base.receive() {
                    note(data)
                    continuation.yield(data)
                }
                // Standard input closed.
                await waitForAnswers()
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in reader.cancel() }
        return stream
    }

    private func note(_ data: Data) {
        for message in Self.messages(in: data) {
            if let id = Self.request(message) { unanswered.insert(id) }
            if let id = Self.cancelledRequest(message) { unanswered.remove(id) }
        }
    }

    private func waitForAnswers() async {
        var idleSince: ContinuousClock.Instant?
        while !unanswered.isEmpty, !Task.isCancelled {
            if isIdle() {
                let start = idleSince ?? .now
                idleSince = start
                if .now - start > Self.patience {
                    logger.warning("Standard input closed. No answer came for: \(unanswered.sorted())")
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

    private static func cancelledRequest(_ message: [String: Any]) -> String? {
        guard message["method"] as? String == "notifications/cancelled" else { return nil }
        return key((message["params"] as? [String: Any])?["requestId"])
    }
}
