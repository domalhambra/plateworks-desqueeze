import Foundation
import os

/// Runs one tool call at a time.
///
/// The job assumes one run in a folder at a time: two at once can give false
/// notes (design 12.2). A call that arrives while another runs waits for it.
///
/// The work runs on a serial dispatch queue, which has a thread of its own.
/// A run blocks its thread while exiftool and the converter work. On a
/// thread of the Swift concurrency pool, that would hold up the library's
/// message loop, and a cancel or a ping could not be read.
final class CallQueue: Sendable {
    private struct State {
        /// The calls in work and the calls that wait.
        var calls = 0
        var isClosed = false
    }

    private let queue = DispatchQueue(label: "org.plateworks.desqueeze.mcp.calls")
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// True when no call is in work and none waits.
    var isIdle: Bool {
        state.withLock { $0.calls == 0 }
    }

    /// Does `work` after every call that is in the queue already.
    ///
    /// - Returns: what `work` gave. Nil when the queue is closed: `work` did
    ///   not start.
    func run<Result: Sendable>(_ work: @escaping @Sendable () -> Result?) async -> Result? {
        state.withLock { $0.calls += 1 }
        return await withCheckedContinuation { continuation in
            queue.async {
                let result = self.state.withLock { $0.isClosed } ? nil : work()
                self.state.withLock { $0.calls -= 1 }
                continuation.resume(returning: result)
            }
        }
    }

    /// Waits for the call in work and for each call that waits, then closes
    /// the queue. No call starts after this returns, so the program can end
    /// and no file is left half done.
    func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.state.withLock { $0.isClosed = true }
                continuation.resume()
            }
        }
    }
}
