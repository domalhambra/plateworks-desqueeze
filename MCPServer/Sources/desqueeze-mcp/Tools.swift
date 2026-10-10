import DesqueezeCore
import MCP

/// One argument of a tool. The JSON schema and the check of a call are both
/// made from this, so the two cannot disagree.
struct ToolArgument: Sendable {
    enum Kind: Sendable {
        /// A JSON string. Required.
        case text
        /// A JSON number, under the rule of `SqueezeFactor`. Required.
        case factor
        /// A JSON boolean. Not required: it has a default.
        case flag(default: Bool)
    }

    let name: String
    let kind: Kind
    let description: String

    var isRequired: Bool {
        if case .flag = kind { return false }
        return true
    }

    var schema: Value {
        switch kind {
        case .text:
            return ["type": "string", "description": .string(description)]
        case .factor:
            return ["type": "number", "minimum": .double(SqueezeFactor.range.lowerBound),
                    "maximum": .double(SqueezeFactor.range.upperBound), "description": .string(description)]
        case .flag(let value):
            return ["type": "boolean", "default": .bool(value), "description": .string(description)]
        }
    }
}

/// One tool as the client sees it: the name, what the model reads, and the
/// arguments.
struct ToolDefinition: Sendable {
    let name: String
    let title: String
    let description: String
    let arguments: [ToolArgument]
    let annotations: Tool.Annotations

    /// The tool for `tools/list`. The schema refuses an argument that the
    /// tool does not have, and so does `ToolCall`.
    var tool: Tool {
        var properties: [String: Value] = [:]
        for argument in arguments { properties[argument.name] = argument.schema }
        return Tool(
            name: name, title: title, description: description,
            inputSchema: [
                "type": "object",
                "properties": .object(properties),
                "required": .array(arguments.filter(\.isRequired).map { .string($0.name) }),
                "additionalProperties": false,
            ],
            annotations: annotations)
    }
}

/// The three tools of design 12.2.
///
/// Each description tells the model what the tool changes, that the change
/// is reversible with `desqueeze_remove`, and to call `desqueeze_scan`
/// first. Short, plain sentences: a model reads them before every call.
///
/// No tool has an argument that moves an original ARW to the Trash (design
/// 14.1), and `ToolCall` refuses an argument that a tool does not have. The
/// descriptions of the two tools that change files say so, with one
/// sentence (`neverMovesAnOriginal`), and so do the instructions.
///
/// The descriptions name dnglab first (design 13.6), and say who converts the
/// long way, with the core's sentence (`ConverterText.whoConverts`): "dnglab
/// converts first" is not the rule. Every sentence that the tool also says is
/// the core's, so the two cannot differ. They name the keys of the reports as
/// `ScanReport` and `RunReport` write them.
enum ToolCatalog {
    static let all = [scan, run, remove]

    static func definition(named name: String) -> ToolDefinition? {
        all.first { $0.name == name }
    }

    private static let folder = ToolArgument(
        name: "folder", kind: .text,
        description: "The absolute path of the folder. It starts with /. A link to a folder counts as that folder.")

    private static let dryRun = ToolArgument(
        name: "dry_run", kind: .flag(default: false),
        description: "True changes no file. The result lists what each file would get, in \"steps\".")

    /// Only a run converts, so only its dry run has `convert` steps.
    private static let dryRunOfARun = ToolArgument(
        name: dryRun.name, kind: dryRun.kind,
        description: dryRun.description
            + " A \"convert\" step names its converter in \"converter\": \"dnglab\" or \"adobe\".")

    /// When the model gives the user the Lightroom line: the rule of design
    /// 4.4, which `RunSummary.lightroomLine` holds for the window and the
    /// command line tool. The server prints JSON only, so the model applies
    /// the rule, with the counts of the result. Run and remove both say it.
    private static let lightroomRule = "When \"set\" is above 0 and dry_run was false, tell the user this line: "
        + "\(RunSummary.lightroomHint) Do not say it after a dry run, or when \"set\" is 0."

    /// What run, remove and the instructions say about the originals
    /// (design 12.2 and 14.1). Two other front ends can move an original
    /// to the Trash, on the user's request for one run. This server cannot.
    ///
    /// The sentence does not say where the option is (design 14.7). A model
    /// that has a shell could start the other front end, so the text gives
    /// it no name of a flag and no place to look.
    static let neverMovesAnOriginal = "This server never moves an original ARW file to the Trash, and it has "
        + "no argument for that. Only the user can ask for it."

    /// What run and remove say about the note of a volume that gives no
    /// lock for a folder (design 13.9). The run went on without the lock,
    /// and its result is a good one. The note itself is the core's.
    static let noFolderLockIsNoFailure = "A note of the kind \"\(FileNote.Kind.noFolderLock.rawValue)\" is no "
        + "failure: the volume gives no lock for a folder, so nothing kept a second run out of the folder while "
        + "this run worked."

    /// Run and remove change files and destroy nothing: a change is
    /// reversible, and the original is kept until the check passes. A second
    /// call with the same arguments changes nothing more.
    private static let changesFiles = Tool.Annotations(
        readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)

    static let scan = ToolDefinition(
        name: "desqueeze_scan",
        title: "Scan a photo folder",
        description: """
            Reads one folder of photos and reports what it holds. Changes no file. Call this first, \
            before desqueeze_run or desqueeze_remove.

            It reads the top level of the folder only. Subfolders are not read.

            The result is one JSON object:
            - "dngs": each DNG file, with its DefaultScale tag in "scale". "1.5 1" is a horizontal \
            stretch of 1.5. "1 1" is no stretch. null is a value that could not be read.
            - "pendingARWs": each Sony ARW file that has no DNG yet. desqueeze_run converts these.
            - "orphanBackups": each backup file (name_original) that has lost its DNG.
            - "writable": false means that desqueeze_run and desqueeze_remove can change nothing here.
            - "exiftool", "dnglab" and "dngConverter": where the three programs are. "dngConverter" is \
            the path of Adobe DNG Converter. null means that the program is not installed.

            ARW files are converted when "dnglab" or "dngConverter" has a path. \(ConverterText.whoConverts) \
            When both are null, ARW files stay as they are, and desqueeze_run still sets the stretch of \
            the DNG files. To make the ARW files convert, tell the user: \(ToolLocator.dnglabInstallLine)
            """,
        arguments: [folder],
        annotations: Tool.Annotations(readOnlyHint: true, openWorldHint: false))

    static let run = ToolDefinition(
        name: "desqueeze_run",
        title: "Set the stretch of anamorphic photos",
        description: """
            Sets the horizontal stretch of the anamorphic photos in one folder, so Lightroom shows \
            them at the correct shape.

            What it changes:
            1. It converts each Sony ARW file that has no DNG to a new DNG beside it. \
            \(ConverterText.whoConverts) \(ConverterText.matchedValues) \
            When neither is installed, ARW files stay as they are. To make them convert, tell the user: \
            \(ToolLocator.dnglabInstallLine)
            2. It sets the DefaultScale tag of every DNG to "<factor> 1". A DNG that has this value \
            already is skipped.

            It works on the top level of the folder only. Subfolders are not read. ARW files are never \
            changed. \(neverMovesAnOriginal) No pixel changes: the tag is metadata.

            The change is reversible: desqueeze_remove sets every DNG back to no stretch. It does not \
            delete a DNG that this tool converted. Each DNG is written with a backup beside it. The \
            backup goes to the Trash only after the new tag reads back correctly. A write that fails \
            puts the backup back.

            The safe path: call desqueeze_scan first. Then call this tool with dry_run true, and read \
            the steps. Then call it with dry_run false.

            The result is one JSON object with the counts "converted", "set", "skipped", "blocked" and \
            "failed", and a note for each file that has something to say. "convertedByDnglab" and \
            "convertedByAdobe" say how many ARW files each converter converted. Their sum is \
            "converted". A file that failed or was blocked is in the notes. It does not make the call \
            an error. A note of the kind "convertedUnmatched" is no failure: dnglab converted the \
            file, Adobe DNG Converter is not installed, and the note says what the DNG lacks. \
            \(noFolderLockIsNoFailure) \
            "stopped" true means that the run was cancelled and left work undone. "trashOriginals" is \
            always false and "originalsInTrash" is always 0 in a result of this server.

            \(lightroomRule)
            """,
        arguments: [
            folder,
            ToolArgument(
                name: "factor", kind: .factor,
                description: "The squeeze factor of the lens: 1.33, 1.5, 1.8 or 2 for most lenses. It is "
                    + "\(SqueezeFactor.ruleText). There is no default. Ask the user."),
            ToolArgument(
                name: "convert", kind: .flag(default: true),
                description: "False leaves the ARW files alone. Only the DNG files that exist get the tag."),
            dryRunOfARun,
        ],
        annotations: changesFiles)

    static let remove = ToolDefinition(
        name: "desqueeze_remove",
        title: "Remove the stretch",
        description: """
            Sets every DNG in one folder back to no stretch: the DefaultScale tag becomes "1 1". This \
            reverses desqueeze_run.

            What it changes: one metadata tag in each DNG that has a stretch. It converts nothing and \
            deletes nothing. ARW files are never changed. \(neverMovesAnOriginal) It works on the top \
            level of the folder only.

            The change is reversible: desqueeze_run with the factor sets the stretch again. Each DNG is \
            written with a backup beside it. The backup goes to the Trash only after the new tag reads \
            back correctly.

            The safe path: call desqueeze_scan first. Then call this tool with dry_run true, and read \
            the steps. Then call it with dry_run false.

            The result is the same JSON object as the result of desqueeze_run, with "factor" "1". \
            \(noFolderLockIsNoFailure)

            \(lightroomRule)
            """,
        arguments: [folder, dryRun],
        annotations: changesFiles)

    /// What the client can show the model at the start of a session.
    static let instructions = """
        Plateworks Desqueeze sets the DefaultScale tag of DNG photos, so Lightroom shows anamorphic \
        photos at the correct shape. Call desqueeze_scan first. Use dry_run true before a run that \
        changes files. desqueeze_remove reverses desqueeze_run. The server runs one tool call at a time. \
        \(neverMovesAnOriginal)
        """
}
