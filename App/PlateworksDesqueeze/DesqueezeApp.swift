import SwiftUI

@main
struct DesqueezeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Desqueeze", id: "main") {
            ContentView()
                .environmentObject(delegate.model)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The delegate owns the model, so a quit can reach the running job.
    let model = AppModel.live()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// A quit, or the close of the window, during a run: cancel the run, let
    /// the current file complete, then quit. A quit in the middle of a file
    /// would drop its check, and leave its backup beside it.
    ///
    /// A second request can come while the first waits: Command-Q twice, or
    /// the close of the window and then a quit. The model gives `afterRun`
    /// to one request only, so the app gets exactly one reply.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch model.answerQuit() {
        case .now:
            return .terminateNow
        case .alreadyWaiting:
            return .terminateLater
        case .afterRun:
            Task {
                await model.stopRunForQuit()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    /// Files that another app added show in the counts (design, section 5).
    /// AppKit calls this for `NSApplication.didBecomeActiveNotification`.
    func applicationDidBecomeActive(_ notification: Notification) {
        model.appBecameActive()
    }
}
