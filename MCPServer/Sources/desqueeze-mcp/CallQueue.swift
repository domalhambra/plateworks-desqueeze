import Foundation
import os

/// Runs one tool call at a time.
///
/// One run works in a folder at a time (design 13.9). The core holds that
/// rule with a lock on the folder, and a second run in the folder would be
/// a tool error. So a call that arrives while another runs waits for it,
/// and two calls of one client never meet in a folder.
///
/// The work runs on a serial dispatch queue, which has a thread of its own.
/// A run blocks its thread while exiftool and a converter work. On a
/// thread of the Swift concurrency pool, that would hold up the library's
/// message loop, and a cancel or a ping could not be read.
///
/// The queue closes when the client goes away: at the end of standard input,
/// and at a signal. A call that waits then does not start. A call that
/// changes files must not run for nobody.
final class CallQueue: Sendable {
    private struct State {
        /// The calls in work and the calls that wait.
        var calls = 0
        var isClosed = false
        var callsWithNoWork = 0
        /// Tells the call in work to stop. Nil when no call is in work.
        var stopCallInWork: (@Sendable () -> Void)?
    }

    private let queue = DispatchQueue(label: "org.plateworks.desqueeze.mcp.calls")
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// True when no call is in work and none waits.
    var isIdle: Bool {
        state.withLock { $0.calls == 0 }
    }

    /// How many calls ended with no work done: `run` gave nil. Such a call
    /// gets no answer, so the transport does not wait for one.
    var callsWithNoWork: Int {
        state.withLock { $0.callsWithNoWork }
    }

    /// Does `work` after every call that is in the queue already.
    ///
    /// - Parameters:
    ///   - onStop: called by `stop` while `work` runs. It tells the work to
    ///     end early.
    ///   - work: nil from it means that it did nothing.
    /// - Returns: what `work` gave. Nil when the queue is closed: `work` did
    ///   not start.
    func run<Result: Sendable>(
        onStop: @escaping @Sendable () -> Void = {}, _ work: @escaping @Sendable () -> Result?
    ) async -> Result? {
        state.withLock { $0.calls += 1 }
        return await withCheckedContinuation { continuation in
            queue.async {
                // One step with `stop`: the call does not start, or `stop`
                // reaches it.
                let starts = self.state.withLock { state -> Bool in
                    guard !state.isClosed else { return false }
                    state.stopCallInWork = onStop
                    return true
                }
                let result = starts ? work() : nil
                self.state.withLock { state in
                    state.stopCallInWork = nil
                    state.calls -= 1
                    if result == nil { state.callsWithNoWork += 1 }
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// No call starts after this. The call in work goes on to its end.
    func close() {
        state.withLock { $0.isClosed = true }
    }

    /// Closes the queue, and tells the call in work to stop.
    func stop() {
        let stop = state.withLock { state -> (@Sendable () -> Void)? in
            state.isClosed = true
            return state.stopCallInWork
        }
        stop?()
    }

    /// Returns when the call in work has completed, so the program can end
    /// and no file is left half done. A closed queue then has no work.
    func waitForCallInWork() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { continuation.resume() }
        }
    }
}
