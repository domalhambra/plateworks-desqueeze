import Foundation
@testable import DesqueezeCore

/// A `ProcessRunner` that records each call and answers from a closure.
final class FakeRunner: ProcessRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    var calls: [Call] = []
    var handler: (Call) -> ProcessResult = { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "") }

    func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        let call = Call(executable: executable.path, arguments: arguments)
        calls.append(call)
        return handler(call)
    }
}

/// Makes an empty temporary folder inside a new `desqueeze-tests-<id>` folder.
/// The test removes it in `tearDown` with `removeTemporaryFolder`.
func makeTemporaryFolder(named name: String = "Shoot 1") throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("desqueeze-tests-\(UUID().uuidString)")
    let folder = base.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Removes the `desqueeze-tests-<id>` folder that holds `folder`. Does nothing
/// for any other URL, so a wrong argument cannot remove a real folder.
func removeTemporaryFolder(_ folder: URL) {
    let base = folder.deletingLastPathComponent()
    guard base.lastPathComponent.hasPrefix("desqueeze-tests-") else { return }
    try? FileManager.default.removeItem(at: base)
}
