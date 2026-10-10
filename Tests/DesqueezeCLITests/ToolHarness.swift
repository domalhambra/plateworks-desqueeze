import DesqueezeCLI
import DesqueezeCore
import Foundation
import XCTest

/// Acts as exiftool and as both converters, on a folder of small files.
///
/// It answers the three exiftool calls of `ScaleTag` from `scales`, the read
/// of the ARW facts from `facts`, and the two exiftool calls of the dnglab
/// match from what the match wrote. It "converts" an ARW by making the file
/// that the program was told to write: the work file, for both converters.
final class FakeTools: ProcessRunner, @unchecked Sendable {
    static let exiftool = URL(fileURLWithPath: "/fake/bin/exiftool")
    static let dnglab = URL(fileURLWithPath: "/fake/bin/dnglab")
    static let converter = URL(fileURLWithPath: "/fake/Adobe DNG Converter")
    /// The facts of a frame from an adapted lens at ISO 800: a full match.
    static let adapted = "ILCE-7SM3\t800\t2597 1024 1556\t255\t2"
    /// The facts of a frame from a lens that reports itself: only rule 4 fails.
    static let lens = "ILCE-7SM3\t80\t2496 1024 1617\t17\t2"

    /// File name to tag value, for example `"A.dng": "1 1"`. No entry is "unknown".
    var scales: [String: String] = [:]
    /// ARW name to the five cells of its facts row. No entry is a row of
    /// dashes: exiftool could not read the file.
    var facts: [String: String] = [:]
    var failWrites: Set<String> = []
    /// DNG name to what the check before an original moves reads as
    /// `OriginalRawFileName` (design 14.2, line 5). No entry is the name of
    /// an ARW with the base name of the DNG, as each converter writes it.
    var originalNames: [String: String] = [:]
    var commands: [String] = []
    /// DNG name to the values that the dnglab match wrote, in order.
    private var matched: [String: [String]] = [:]

    func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        commands.append(([executable.lastPathComponent] + arguments.map { URL(fileURLWithPath: $0).lastPathComponent })
            .joined(separator: " "))
        let file = URL(fileURLWithPath: arguments.last ?? "")
        if executable == Self.converter {
            // Adobe DNG Converter writes in the folder that follows `-d`,
            // under the name that follows `-o`. With no `-o` the name is
            // `<base>.dng`, as the real converter does it.
            let folder = arguments.firstIndex(of: "-d").map { URL(fileURLWithPath: arguments[$0 + 1]) }
                ?? file.deletingLastPathComponent()
            let name = arguments.firstIndex(of: "-o").map { arguments[$0 + 1] }
                ?? file.deletingPathExtension().lastPathComponent + ".dng"
            try Data("converted".utf8).write(to: folder.appendingPathComponent(name))
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        if executable == Self.dnglab {
            try Data("converted by dnglab".utf8).write(to: file)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        if arguments.contains("-IFD0:Model") {
            let rows = arguments.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).lastPathComponent }
                .map { "\($0)\t\(facts[$0] ?? "-\t-\t-\t-\t-")\n" }.joined()
            return ProcessResult(exitCode: 0, stdout: rows, stderr: "")
        }
        if arguments.contains("-overwrite_original") {
            matched[file.lastPathComponent] = arguments.filter { $0.contains("=") }
                .map { String($0[$0.index(after: $0.firstIndex(of: "=")!)...]) }
            return ProcessResult(exitCode: 0, stdout: "    1 image files updated\n", stderr: "")
        }
        if arguments.dropLast() == ["-m", "-n", "-T", "-IFD0:OriginalRawFileName", "-SubIFD:DefaultScale"] {
            // The check of a DNG before its original moves. A converter
            // writes no stretch, so a DNG with no entry holds "1 1".
            let name = originalNames[file.lastPathComponent]
                ?? file.deletingPathExtension().lastPathComponent + ".ARW"
            return ProcessResult(exitCode: 0, stdout: "\(name)\t\(scales[file.lastPathComponent] ?? "1 1")\n",
                                 stderr: "")
        }
        if arguments.contains("-T"), !arguments.contains("-ext") {
            let row = (matched[file.lastPathComponent] ?? []).joined(separator: "\t")
            return ProcessResult(exitCode: 0, stdout: row + "\n", stderr: "")
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
    /// Adobe DNG Converter is installed.
    var hasConverter = true
    /// dnglab is installed. Off, so a test that does not name it runs as on
    /// a Mac with Adobe DNG Converter alone.
    var hasDnglab = false
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
            dnglab: hasDnglab ? FakeTools.dnglab : nil,
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
        run(arguments)
    }

    @discardableResult
    func run(_ arguments: [String]) -> Int32 {
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
