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
    let model = AppModel()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// A quit, or the close of the window, during a run: cancel the run, let
    /// the current file complete, then quit. A quit in the middle of a file
    /// would drop its check, and leave its backup beside it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isRunning else { return .terminateNow }
        Task {
            await model.stopRunForQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
