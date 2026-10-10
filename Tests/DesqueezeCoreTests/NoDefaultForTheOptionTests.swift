import XCTest

/// The option that moves the originals has no default value (design 14.6,
/// invariant 1): every caller states it.
///
/// No behavioral test can hold that rule. With `trashOriginals: Bool = true`
/// in `DesqueezeJob.run(folder:)`, in `DesqueezeJob.plan(folder:)` or in
/// `DesqueezeOperations.run`, every other test passes, because every caller
/// in the code states the value. The break shows only in a caller that
/// leaves the value out, and that caller would be new code. So this test
/// reads the source: the Swift files of the core, the command line tool,
/// the window and the MCP server.
///
/// Two rules:
///
/// - A parameter named `trashOriginals` has no default value, also not
///   `false`. This holds for a function, an initializer, a closure and the
///   value of an enum case.
/// - A property or a constant named `trashOriginals` that has a start value
///   starts as `false`, written as the word `false`. `RunSummary` and the
///   window's model each have one: the option is off until someone turns
///   it on.
final class NoDefaultForTheOptionTests: XCTestCase {
    /// Tests/DesqueezeCoreTests/NoDefaultForTheOptionTests.swift -> repo root.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The folders that hold the product's Swift code.
    static let sourceFolders = ["Sources", "App", "MCPServer/Sources"]

    /// One declaration that breaks a rule.
    struct Finding: Equatable, CustomStringConvertible {
        let line: Int
        let text: String
        var description: String { "line \(line): \(text)" }
    }

    /// A parameter with a default: the name, an optional second name, a
    /// colon, a type on that line, and one `=`. Spaces and line breaks can
    /// stand between the type and the `=`: a default on the next line is a
    /// default. A call such as `trashOriginals: false` has no `=` after its
    /// value, and `==`, `!=`, `<=` and `>=` are comparisons.
    static let parameterWithADefault = try! NSRegularExpression(
        pattern: #"\btrashOriginals(?:\s+[A-Za-z_]\w*)?\s*:[^,)=\n{}]*?\s*(?<![!<>=])=(?!=)"#)

    /// A stored property or a constant with a start value. The first group
    /// is the value, to the end of the line.
    static let propertyWithAStartValue = try! NSRegularExpression(
        pattern: #"\b(?:var|let)\s+trashOriginals\b(?:\s*:[^=\n{}]*)?\s*=(?!=)\s*([^\n]*)"#)

    /// The declarations in `source` that break a rule. Comments are not
    /// read: a comment can show a default to say that there is none.
    static func findings(in source: String) -> [Finding] {
        let code = source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            guard let comment = line.range(of: "//") else { return String(line) }
            return String(line[..<comment.lowerBound])
        }.joined(separator: "\n")
        let whole = NSRange(code.startIndex..., in: code)
        func line(of match: NSTextCheckingResult) -> Int {
            code[..<Range(match.range, in: code)!.lowerBound].filter { $0 == "\n" }.count + 1
        }
        func text(of match: NSTextCheckingResult) -> String {
            String(code[Range(match.range, in: code)!]).trimmingCharacters(in: .whitespaces)
        }
        var found: [Finding] = []
        let properties = propertyWithAStartValue.matches(in: code, range: whole)
        for match in properties {
            let value = String(code[Range(match.range(at: 1), in: code)!]).trimmingCharacters(in: .whitespaces)
            if value != "false" { found.append(Finding(line: line(of: match), text: text(of: match))) }
        }
        // `var trashOriginals: Bool = false` has the form of a parameter
        // with a default too. It is a property, and the rule above judged it.
        for match in parameterWithADefault.matches(in: code, range: whole)
        where !properties.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
            found.append(Finding(line: line(of: match), text: text(of: match)))
        }
        return found.sorted { $0.line < $1.line }
    }

    /// Each Swift file under the three folders, with its path from the
    /// root. Build folders are not read.
    static func sources() throws -> [(path: String, text: String)] {
        var files: [(String, String)] = []
        for folder in sourceFolders {
            let start = root.appendingPathComponent(folder)
            let walker = try XCTUnwrap(FileManager.default.enumerator(at: start, includingPropertiesForKeys: nil),
                                       "\(folder) is not there")
            for case let file as URL in walker where file.pathExtension == "swift" {
                guard !file.pathComponents.contains(".build") else { continue }
                let path = String(file.path.dropFirst(root.path.count + 1))
                files.append((path, try String(contentsOf: file, encoding: .utf8)))
            }
        }
        return files.sorted { $0.0 < $1.0 }
    }

    // MARK: The source of the product

    func testNoDeclarationGivesTheOptionADefaultValue() throws {
        for (path, text) in try Self.sources() {
            XCTAssertEqual(Self.findings(in: text), [],
                           "\(path): a parameter named `trashOriginals` has no default value, and a property starts as false.")
        }
    }

    // The test above says nothing when it reads nothing. It must read the
    // files that declare the option, and find the declarations there.
    func testTheReaderFindsTheDeclarationsOfTheOption() throws {
        let sources = try Self.sources()
        let paths = sources.map(\.path)
        for needed in ["Sources/DesqueezeCore/DesqueezeJob.swift", "Sources/DesqueezeCore/Operations.swift",
                       "Sources/DesqueezeCore/RunSummary.swift", "Sources/DesqueezeCLI/Arguments.swift",
                       "App/PlateworksDesqueeze/AppModel.swift",
                       "MCPServer/Sources/desqueeze-mcp/ToolEnvironment.swift"] {
            XCTAssertTrue(paths.contains(needed), "\(needed) was not read")
        }
        func count(_ pattern: String, in path: String) throws -> Int {
            let text = try XCTUnwrap(sources.first { $0.path == path }?.text)
            return try NSRegularExpression(pattern: pattern)
                .numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        }
        // `run(folder:)`, `plan(folder:)`, and the two that take a snapshot.
        XCTAssertGreaterThanOrEqual(try count(#"\btrashOriginals: Bool[,)]"#,
                                              in: "Sources/DesqueezeCore/DesqueezeJob.swift"), 4)
        // `DesqueezeOperations.run`, and the one function behind it.
        XCTAssertGreaterThanOrEqual(try count(#"\btrashOriginals: Bool[,)]"#,
                                              in: "Sources/DesqueezeCore/Operations.swift"), 2)
        XCTAssertEqual(try count(#"var trashOriginals = false"#, in: "Sources/DesqueezeCore/RunSummary.swift"), 1)
        XCTAssertEqual(try count(#"var trashOriginals = false"#, in: "App/PlateworksDesqueeze/AppModel.swift"), 1)
    }

    // MARK: The reader itself

    func testAParameterWithADefaultIsFound() {
        for source in [
            "func run(folder: URL, trashOriginals: Bool = true, remove: Bool = false) {}",
            // A default of false is a default too: a caller can leave it out.
            "func run(folder: URL, trashOriginals: Bool = false) {}",
            "func run(\n    folder: URL,\n    trashOriginals: Bool = true,\n    remove: Bool\n) {}",
            "func run(trashOriginals:Bool=true) {}",
            // The default is on the next line.
            "func run(\n    folder: URL,\n    trashOriginals: Bool\n        = true,\n    remove: Bool\n) {}",
            "func run(trashOriginals: Bool\n= true) {}",
            "func run(trashOriginals: Bool   \n\n   = true) {}",
            "func run(trashOriginals: Swift.Bool = true) {}",
            "func run(trashOriginals: Bool? = nil) {}",
            "func run(trashOriginals: Optional<Bool> = nil) {}",
            "func run(_ trashOriginals: Bool = true) {}",
            "func run(trashOriginals move: Bool = true) {}",
            "init(trashOriginals: Bool = true) {}",
            "case run(folder: String, trashOriginals: Bool = true, dryRun: Bool)",
            "let start: (Bool) -> Void = { (trashOriginals: Bool = true) in }",
        ] {
            XCTAssertEqual(Self.findings(in: source).count, 1, source)
        }
    }

    func testAParameterWithNoDefaultAndACallAreNotFound() {
        for source in [
            "func run(folder: URL, trashOriginals: Bool, remove: Bool = false) {}",
            "func run(\n    folder: URL,\n    trashOriginals: Bool,\n    remove: Bool = false\n) {}",
            "func movesOriginals(_ trashOriginals: Bool, remove: Bool) -> Bool { trashOriginals && !remove }",
            "case run(folder: String, factor: SqueezeFactor, convert: Bool, trashOriginals: Bool, dryRun: Bool)",
            "try operations.run(folder, factor: factor, convert: convert, trashOriginals: false, dryRun: dryRun)",
            "try job.run(folder: folder, trashOriginals: trashOriginals, remove: remove)",
            "start(trashOriginals: given.contains(\"--trash-originals\"), dryRun: dryRun)",
            "label(originalsToTrash: trashOriginals ? originalsCount : 0)",
            "start(trashOriginals: count == 1, remove: false)",
            "start(trashOriginals: count != 1, remove: false)",
            "start(trashOriginals: count >= 1, remove: false)",
            "start(trashOriginals: count <= 1, remove: false)",
            "summary.trashOriginals = movesOriginals",
            "self.trashOriginals = false",
            "if trashOriginals, !showsTrashOriginals { trashOriginals = false }",
            "public let trashOriginals: Bool",
            "public let trashOriginals: Bool\n    public let other = 5",
            "func run(trashOriginals: Bool,\n         remove: Bool = false) {}",
            "start(trashOriginals: on\n)\nlet x = 1",
            "case .run(let folder, let factor, let convert, let trashOriginals, let dryRun):",
            "public static let trashOriginalsLabel = \"Move the original ARW files to the Trash\"",
            "public static func trashOriginalsLine(count: Int = 1) -> String { \"\" }",
            "// func run(trashOriginals: Bool = true) {}",
            "    /// With `trashOriginals: Bool = true`, every test passes.",
        ] {
            XCTAssertEqual(Self.findings(in: source), [], source)
        }
    }

    func testAPropertyStartsAsFalseOrHasNoStartValue() {
        for source in ["public var trashOriginals = false", "@Published private(set) var trashOriginals = false",
                       "var trashOriginals: Bool = false", "let trashOriginals: Bool", "var trashOriginals: Bool"] {
            XCTAssertEqual(Self.findings(in: source), [], source)
        }
        for source in ["public var trashOriginals = true", "@Published private(set) var trashOriginals = true",
                       "var trashOriginals: Bool = true", "var trashOriginals = !false",
                       "let trashOriginals = UserDefaults.standard.bool(forKey: \"trashOriginals\")",
                       "var trashOriginals = Defaults.on", "var trashOriginals: Bool = { true }()"] {
            XCTAssertEqual(Self.findings(in: source).count, 1, source)
        }
    }

    func testAFindingNamesItsLine() {
        let source = "struct Job {\n    func run(\n        folder: URL,\n        trashOriginals: Bool = true\n    ) {}\n}\n"
        XCTAssertEqual(Self.findings(in: source), [Finding(line: 4, text: "trashOriginals: Bool =")])
    }
}
