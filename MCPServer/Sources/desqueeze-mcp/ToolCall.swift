import DesqueezeCore
import MCP

/// Why a tool call was refused: one plain sentence, or two, for the model.
/// It becomes a tool result with `isError` true. No file changed.
struct ToolFailure: Error, Equatable, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// What a `tools/call` asked for, with every argument checked.
enum ToolCall: Equatable, Sendable {
    case scan(folder: String)
    case run(folder: String, factor: SqueezeFactor, convert: Bool, dryRun: Bool)
    case remove(folder: String, dryRun: Bool)

    /// The folder as the client gave it: an absolute path. What is at the
    /// path is not known yet.
    var folder: String {
        switch self {
        case .scan(let folder), .run(let folder, _, _, _), .remove(let folder, _): return folder
        }
    }

    /// Checks the arguments of a call against the tool's definition. Reads no
    /// file.
    ///
    /// - Throws: `ToolFailure` for an argument that the tool does not have, a
    ///   value of the wrong type, a required argument that is absent, a
    ///   folder that is not an absolute path, and a factor outside the rule.
    init(_ tool: ToolDefinition, arguments: [String: Value]) throws {
        let known = tool.arguments.map(\.name)
        if let unknown = arguments.keys.sorted().first(where: { !known.contains($0) }) {
            throw ToolFailure(
                "\(tool.name) has no argument \"\(unknown)\". Its arguments are: \(known.joined(separator: ", ")).")
        }
        let reader = Reader(tool: tool, values: arguments)
        switch tool.name {
        case ToolCatalog.scan.name:
            self = .scan(folder: try reader.folder())
        case ToolCatalog.run.name:
            self = .run(folder: try reader.folder(), factor: try reader.factor(),
                        convert: try reader.flag("convert"), dryRun: try reader.flag("dry_run"))
        default:
            self = .remove(folder: try reader.folder(), dryRun: try reader.flag("dry_run"))
        }
    }

    private struct Reader {
        let tool: ToolDefinition
        let values: [String: Value]

        func folder() throws -> String {
            guard let value = values["folder"] else {
                throw ToolFailure("\(tool.name) needs the argument \"folder\": the absolute path of a folder.")
            }
            guard case .string(let path) = value else {
                throw ToolFailure("The argument \"folder\" must be text: the absolute path of a folder.")
            }
            // The server has no working folder that a client knows, and it
            // is not a shell, so `~` is only a character.
            guard path.hasPrefix("/") else {
                throw ToolFailure(
                    "The folder must be an absolute path, which starts with /. A relative path and ~ do not work. "
                        + "It was \"\(path)\".")
            }
            return path
        }

        /// A flag that is absent has the default of the tool's definition.
        func flag(_ name: String) throws -> Bool {
            guard let value = values[name] else {
                for argument in tool.arguments where argument.name == name {
                    if case .flag(let value) = argument.kind { return value }
                }
                return false
            }
            guard case .bool(let flag) = value else {
                throw ToolFailure("The argument \"\(name)\" must be true or false.")
            }
            return flag
        }

        /// The factor arrives as a JSON number, and a JSON number is a
        /// binary one here: 1.33 is 1.3300000000000000710542735760100…
        /// Swift prints a `Double` as the shortest text that reads back as
        /// the same number, and that text is `1.33` again. So the text goes
        /// to the rule of the command line tool, `SqueezeFactor(text:)`,
        /// which refuses more than four decimal places.
        func factor() throws -> SqueezeFactor {
            guard let value = values["factor"] else {
                throw ToolFailure(
                    "\(tool.name) needs the argument \"factor\": the squeeze factor of the lens, "
                        + "\(SqueezeFactor.ruleText). There is no default.")
            }
            let text: String
            switch value {
            case .int(let number): text = String(number)
            case .double(let number): text = number.description
            default:
                // A JSON number has no comma, so "1,5" can only come as
                // text. The core's hint then says what is wrong with it.
                var hint = ""
                if case .string(let given) = value { hint = SqueezeFactor.hint(for: given) }
                throw ToolFailure(
                    "The argument \"factor\" must be a number, such as 1.5. Text in quotes is not a number." + hint)
            }
            guard let factor = SqueezeFactor(text: text) else {
                throw ToolFailure(SqueezeFactor.errorMessage(got: text))
            }
            return factor
        }
    }
}
