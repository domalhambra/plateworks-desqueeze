import DesqueezeCore

/// What the command line asked for.
public enum Command: Equatable, Sendable {
    case scan(folder: String)
    case run(folder: String, factor: SqueezeFactor, convert: Bool, dryRun: Bool)
    case remove(folder: String, dryRun: Bool)
    case version
    case help
}

public struct Invocation: Equatable, Sendable {
    public let command: Command
    public let json: Bool
    public let verbose: Bool

    public init(command: Command, json: Bool = false, verbose: Bool = false) {
        self.command = command
        self.json = json
        self.verbose = verbose
    }
}

/// A command line that the tool cannot act on. Exit code 2.
public struct UsageError: Error, Equatable, Sendable {
    /// One plain sentence, or two.
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// The parser of design 12.1. Hand-written: the tool links no other package.
///
/// ```
/// desqueeze scan <folder> [--json]
/// desqueeze run <folder> --factor <number> [--no-convert] [--dry-run] [--json]
/// desqueeze remove <folder> [--dry-run] [--json]
/// desqueeze --version
/// desqueeze --help
/// ```
///
/// `--verbose` goes with every command. An option can stand before or after
/// the command and the folder. `--` ends the options, so a folder whose name
/// starts with a dash can be given.
public enum Arguments {
    /// - Parameter arguments: the command line with no program name.
    /// - Throws: `UsageError`. No command runs on a line that has an error.
    public static func parse(_ arguments: [String]) throws -> Invocation {
        // Help first: a person who asks for help gets it, whatever else is
        // wrong on the line. Then the version.
        let options = arguments.prefix { $0 != "--" }
        if options.contains("--help") || options.contains("-h") { return Invocation(command: .help) }
        if options.contains("--version") { return Invocation(command: .version) }

        var words: [String] = []
        var factorText: String?
        var given = Set<String>()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            switch argument {
            case "--":
                words += arguments[index...]
                index = arguments.count
            case "--json", "--verbose", "--dry-run", "--no-convert":
                given.insert(argument)
            case "--factor":
                // The next word is the value, unless it is another option.
                let value = index < arguments.count && !arguments[index].hasPrefix("--") ? arguments[index] : nil
                if value != nil { index += 1 }
                try setFactor(&factorText, to: value)
            case _ where argument.hasPrefix("--factor="):
                try setFactor(&factorText, to: String(argument.dropFirst("--factor=".count)))
            case _ where argument.hasPrefix("-") && argument != "-":
                throw UsageError("Unknown option: \(argument)")
            default:
                words.append(argument)
            }
        }

        guard let name = words.first else { throw UsageError("No command was given.") }
        guard ["scan", "run", "remove"].contains(name) else {
            throw UsageError("Unknown command: \(name). The commands are scan, run and remove.")
        }
        // The options of the wrong command come before the folder check, so
        // the message names the real mistake.
        if name != "run", factorText != nil {
            throw UsageError(doesNotGo("--factor", with: name, why: "Remove always sets no stretch."))
        }
        if name != "run", given.contains("--no-convert") {
            throw UsageError(doesNotGo("--no-convert", with: name, why: "Remove never converts."))
        }
        if name == "scan", given.contains("--dry-run") {
            throw UsageError(doesNotGo("--dry-run", with: name, why: ""))
        }
        guard words.count >= 2, !words[1].isEmpty else { throw UsageError("\(name) needs a folder.") }
        guard words.count == 2 else {
            throw UsageError("Too many arguments: \(words[2...].joined(separator: " ")). Give one folder.")
        }
        let folder = words[1]
        let dryRun = given.contains("--dry-run")

        let command: Command
        switch name {
        case "scan":
            command = .scan(folder: folder)
        case "remove":
            command = .remove(folder: folder, dryRun: dryRun)
        default:
            guard let factorText else { throw UsageError("run needs --factor <number>. There is no default.") }
            guard let factor = SqueezeFactor(text: factorText) else {
                throw UsageError("The factor must be \(SqueezeFactor.ruleText). Got: \(factorText)")
            }
            command = .run(folder: folder, factor: factor, convert: !given.contains("--no-convert"), dryRun: dryRun)
        }
        return Invocation(command: command, json: given.contains("--json"), verbose: given.contains("--verbose"))
    }

    private static func setFactor(_ factorText: inout String?, to value: String?) throws {
        guard let value, !value.isEmpty else { throw UsageError("--factor needs a number.") }
        guard factorText == nil else { throw UsageError("--factor was given more than once.") }
        factorText = value
    }

    private static func doesNotGo(_ option: String, with command: String, why: String) -> String {
        let sentence = "\(option) does not go with \(command)."
        return command == "remove" && !why.isEmpty ? "\(sentence) \(why)" : sentence
    }
}
