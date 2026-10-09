import DesqueezeCLI
import DesqueezeCore
import Foundation
import XCTest

/// Acts as exiftool and as the converter, on a folder of small files.
///
/// It answers the three exiftool calls of `ScaleTag` from `scales`, and
/// "converts" an ARW by making a file with the DNG's name.
final class FakeTools: ProcessRunner, @unchecked Sendable {
    static let exiftool = URL(fileURLWithPath: "/fake/bin/exiftool")
    static let converter = URL(fileURLWithPath: "/fake/Adobe DNG Converter")

    /// File name to tag value, for example `"A.dng": "1 1"`. No entry is "unknown".
    var scales: [String: String] = [:]
    var failWrites: Set<String> = []
    var commands: [String] = []

    func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        commands.append(([executable.lastPathComponent] + arguments.map { URL(fileURLWithPath: $0).lastPathComponent })
            .joined(separator: " "))
        let file = URL(fileURLWithPath: arguments.last ?? "")
        if executable == Self.converter {
            try Data("converted".utf8).write(to: file.deletingPathExtension().appendingPathExtension("dng"))
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        if arguments.contains("-T") {
            let names = try FileManager.default.contentsOfDirectory(atPath: file.path)
                .filter { $0.lowercased().hasSuffix(".dng") }.sorted()
            let rows = names.map { "\($0)\t\(scales[$0] ?? "-")\t-\n" }.joined()
            return ProcessResult(exitCode: 0, stdout: rows, stderr: "")
        }
        if arguments.first == "-s3" {
            return ProcessResult(exitCode: 0, stdout: (scales[file.lastPathComponent] ?? "") + "\n", stderr: "")
        }
        if failWrites.contains(file.lastPathComponent) {
            return ProcessResult(exitCode: 1, stdout: "    0 image files updated\n",
                                 stderr: "Error: Not a valid TIFF - \(file.path)\n")
        }
        let value = arguments.first { $0.hasPrefix("-SubIFD:DefaultScale=") } ?? ""
        scales[file.lastPathComponent] = String(value.dropFirst("-SubIFD:DefaultScale=".count))
        return ProcessResult(exitCode: 0, stdout: "    1 image files updated\n", stderr: "")
    }
}

/// What one stream got. The tool adds the line end to each write.
final class Lines: @unchecked Sendable {
    /// Each write, as it was made.
    var writes: [String] = []
    var text: String { writes.joined(separator: "\n") }
    var lines: [String] { writes.flatMap { $0.components(separatedBy: "\n") } }
}

/// One temporary folder, the fake tools, and what the tool printed.
final class ToolHarness {
    let base: URL
    let shoot: URL
    let tools = FakeTools()
    let out = Lines()
    let err = Lines()
    let discarded = Lines()
    let cancel = CancelFlag()
    var hasExiftool = true
    var hasConverter = true
    var testBackupFolder: URL?

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("desqueeze-cli-tests-\(UUID().uuidString)")
        shoot = base.appendingPathComponent("Shoot 1")
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shoot.path)
        try? FileManager.default.removeItem(at: base)
    }

    func touch(_ names: String...) throws {
        for name in names { try Data(name.utf8).write(to: shoot.appendingPathComponent(name)) }
    }

    var environment: ToolEnvironment {
        let (out, err, discarded, cancel) = (out, err, discarded, cancel)
        return ToolEnvironment(
            workingFolder: base,
            exiftool: hasExiftool ? FakeTools.exiftool : nil,
            dngConverter: hasConverter ? FakeTools.converter : nil,
            runner: tools,
            backups: FileBackups(trash: { discarded.writes.append($0.lastPathComponent) }),
            testBackupFolder: testBackupFolder,
            interruptFlag: { cancel },
            standardOutput: { out.writes.append($0) },
            standardError: { err.writes.append($0) })
    }

    /// Runs the tool. Returns its exit code.
    @discardableResult
    func run(_ arguments: String...) -> Int32 {
        out.writes = []
        err.writes = []
        return DesqueezeTool.run(arguments, in: environment)
    }

    /// Standard output as one JSON object. Fails when it holds anything else.
    func json(file: StaticString = #filePath, line: UInt = #line) throws -> NSDictionary {
        XCTAssertEqual(out.writes.count, 1, "one write to standard output", file: file, line: line)
        let object = try JSONSerialization.jsonObject(with: Data(out.text.utf8))
        return try XCTUnwrap(object as? NSDictionary, file: file, line: line)
    }
}
