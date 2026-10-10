import Foundation

/// Sets a flag at a signal, so a run stops after its current file.
///
/// The command line tool takes Control-C and a plain `kill` this way. The
/// MCP server takes the signals with which a client stops it (design 12.2).
///
/// exiftool and the converter normally do not get the Control-C. Checked on
/// this Mac (macOS 27): `Process` starts each program as the leader of a
/// process group of its own, so its group id is its own process id and not the
/// tool's. A terminal sends Control-C to the foreground group, which holds the
/// tool and no program that it started. A `SIGINT` sent to the tool's group
/// during a run did not reach the exiftool in work. That write completed, was
/// checked, and its backup was discarded, and the run then saw the flag and
/// stopped.
///
/// "Normally" is the word. A program that is only just starting can still get
/// the signal: `InterruptTests` saw it once in 27 runs under load, when the
/// signal reached an exiftool that was just starting. That file is then
/// reported as failed ("ended by signal 2"), and it is left as it was. Run
/// again to complete it (design 12.1).
///
/// Apple does not document this behavior of `Process`, so `ProcessRunnerTests`
/// pins the group. `InterruptTests` does not pin the group. It pins the
/// result: the run stops after its current file, and no file is damaged.
/// A plain `kill` (SIGTERM) goes to the tool alone, and is taken the same way.
///
/// The signals stay taken for as long as the watcher lives.
public final class InterruptWatcher: @unchecked Sendable {
    public let flag = CancelFlag()
    private var sources: [DispatchSourceSignal] = []

    /// - Parameters:
    ///   - signals: the signals to take, for example `[SIGINT, SIGTERM]`.
    ///   - onFirst: called once, at the first signal.
    public init(signals: [Int32], onFirst: @escaping @Sendable () -> Void) {
        let flag = flag
        // One queue for every signal, so two signals that arrive together
        // cannot both be the first.
        let queue = DispatchQueue(label: "org.plateworks.desqueeze.signals")
        for number in signals {
            // The signal must not end the process. The source still sees it.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                if !flag.isCancelled { onFirst() }
                flag.cancel()
            }
            source.resume()
            sources.append(source)
        }
    }
}
