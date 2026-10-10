import DesqueezeCore
import MCP

/// Joins the three tools to the library's server: `tools/list` and
/// `tools/call`.
struct ToolHandlers: Sendable {
    let environment: ToolEnvironment
    let queue: CallQueue

    func register(on server: Server) async {
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: ToolCatalog.all.map(\.tool))
        }
        // The handler holds the server, and the server holds the handler.
        // Both live as long as the program.
        await server.withMethodHandler(CallTool.self) { parameters in
            try await call(parameters) { step in
                // A client that went away gets no progress. The run goes on.
                try? await server.notify(step)
            }
        }
    }

    /// One `tools/call`.
    ///
    /// - Parameter notify: sends one progress message to the client.
    /// - Throws: `MCPError` for a tool that the server does not have, which
    ///   is an error of the protocol. `CancellationError` for a call that was
    ///   cancelled before it started: the library then sends no answer, as
    ///   the protocol says.
    func call(
        _ parameters: CallTool.Parameters,
        notify: @escaping @Sendable (Message<ProgressNotification>) async -> Void
    ) async throws -> CallTool.Result {
        guard let tool = ToolCatalog.definition(named: parameters.name) else {
            throw MCPError.invalidParams("Unknown tool: \(parameters.name)")
        }
        let call: ToolCall
        do {
            call = try ToolCall(tool, arguments: parameters.arguments ?? [:])
        } catch let failure as ToolFailure {
            return .refusal(failure.message)
        }

        // No token, no progress messages.
        let progress = parameters._meta?.progressToken.map { ProgressSender(token: $0, notify: notify) }

        // The library cancels this task when the client sends
        // `notifications/cancelled` for the call. A run in work then stops
        // after its current file, and its report says `stopped`.
        let cancel = CancelFlag()
        let result = await withTaskCancellationHandler {
            await queue.run {
                // Cancelled while it waited: no work.
                cancel.isCancelled ? nil : environment.result(of: call, cancel: cancel) { progress?.step($0) }
            }
        } onCancel: {
            cancel.cancel()
        }

        // Every progress message is written before the result.
        await progress?.finish()
        guard let result else { throw CancellationError() }
        return result
    }
}

/// Sends the steps of one run to the client: one `notifications/progress`
/// for each step, in order.
///
/// The run reports a step on its own thread and does not wait. The steps go
/// through a stream to one task, which sends them.
struct ProgressSender: Sendable {
    private let feed: AsyncStream<RunProgress>.Continuation
    private let sender: Task<Void, Never>

    init(token: ProgressToken, notify: @escaping @Sendable (Message<ProgressNotification>) async -> Void) {
        let (steps, feed) = AsyncStream<RunProgress>.makeStream()
        self.feed = feed
        sender = Task {
            for await step in steps {
                // The total can shrink by one when a conversion fails. The
                // message says what the core reports.
                await notify(ProgressNotification.message(.init(
                    progressToken: token, progress: Double(step.completed), total: Double(step.total),
                    message: step.name)))
            }
        }
    }

    func step(_ progress: RunProgress) {
        feed.yield(progress)
    }

    /// Returns when every step is sent.
    func finish() async {
        feed.finish()
        await sender.value
    }
}
