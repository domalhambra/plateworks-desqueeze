import DesqueezeCore

/// The fixed text of the tool: the version line, the help, and how a usage
/// error is shown. Sentence case, and no exclamation mark.
public enum Usage {
    /// `desqueeze 0.1.0`. The number is `DesqueezeVersion.current`.
    public static let version = "desqueeze \(DesqueezeVersion.current)"

    public static let help = """
        Sets the stretch of anamorphic DNG photos, so Lightroom shows them at
        the correct shape. Works on the top level of one folder.

        Usage:
          desqueeze scan <folder> [--json]
          desqueeze run <folder> --factor <number> [--no-convert] [--trash-originals]
                        [--dry-run] [--json]
          desqueeze remove <folder> [--dry-run] [--json]
          desqueeze --version
          desqueeze --help

        Commands:
          scan     Shows each DNG with its current scale, the ARW files that have
                   no DNG, each backup that has lost its DNG, and where exiftool,
                   dnglab and Adobe DNG Converter are. Changes no file.
          run      Converts each ARW that has no DNG, then sets the stretch on
                   every DNG.
          remove   Sets every DNG back to no stretch. Converts nothing.

        Options:
          --factor <number>  The squeeze factor of the lens:
                             \(SqueezeFactor.ruleText).
                             For run only, and run needs it. There is no default.
          --no-convert       For run: leaves the ARW files alone.
          --trash-originals  For run: moves each original ARW to the Trash after
                             its DNG passes the check. Off unless given. Does not
                             go with --no-convert.
          --dry-run          For run and remove: shows what the run would do, file
                             by file, and which converter gets each ARW. Changes
                             no file, and moves none.
          --json             Prints one JSON object on standard output, and
                             nothing else there.
          --verbose          Prints each exiftool and converter command, its exit
                             code, and its output on standard error. Also says
                             when it removed a leftover work file, and the error
                             number when the volume gave no folder lock.

        \(wrapped("\(ConverterText.whoConverts) \(ConverterText.matchedValues) "
            + "With no converter, run still sets the stretch on the DNG files."))
        \(ToolLocator.dnglabInstallLine)

        \(wrapped("Progress goes to standard error. Control-C, or a closed Terminal window, stops a run "
            + "after the current file, and the result so far is still printed."))
        While a run works, a scan or a dry run can show a folder in change.

        A change is reversible: remove sets each DNG back. No pixel changes.
        An ARW stays where it is, unless run has --trash-originals. An ARW in
        the Trash can be put back until the Trash is emptied.
        \(RunSummary.lightroomHint)

        Exit codes:
          0  The command completed, no file failed, and no file was blocked. A
             scan that completed gives 0, also for a read-only folder.
          1  A file failed or was blocked, the run was stopped, the folder could
             not be read, a run or a dry run met a read-only folder, another run
             works in the folder, or exiftool is missing.
          2  The command line was wrong.
        """

    /// The widest line of the help. The rule is under 80 columns.
    static let helpWidth = 79

    /// `text` broken at spaces into lines of at most `helpWidth` columns. A
    /// word is never cut, and a line has no space at either end. The core
    /// makes a sentence that more than one front end says as one line, and
    /// the help is the front end that must wrap it.
    static func wrapped(_ text: String) -> String {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if line.isEmpty {
                line = String(word)
            } else if line.count + 1 + word.count <= helpWidth {
                line += " " + word
            } else {
                lines.append(line)
                line = String(word)
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines.joined(separator: "\n")
    }

    /// What standard error gets for a usage error: the reason, and one line
    /// that points to the help.
    public static func error(_ error: UsageError) -> [String] {
        ["desqueeze: \(error.message)", "See desqueeze --help."]
    }
}
