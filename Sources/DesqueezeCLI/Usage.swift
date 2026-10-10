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
          desqueeze run <folder> --factor <number> [--no-convert] [--dry-run] [--json]
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
          --dry-run          For run and remove: shows what the run would do, file
                             by file, and which converter gets each ARW. Changes
                             no file.
          --json             Prints one JSON object on standard output, and
                             nothing else there.
          --verbose          Prints each exiftool and converter command, its exit
                             code, and its output on standard error.

        dnglab converts the ARW files. Each DNG that it makes gets the values that
        Adobe DNG Converter writes, so Lightroom shows the same photo. Adobe DNG
        Converter is the optional backup, for a photo that dnglab cannot match.
        With no converter, run still sets the stretch on the DNG files.
        Install dnglab with: \(ToolLocator.dnglabInstallCommand)

        Progress goes to standard error. Control-C stops a run after the current
        file, and the result so far is still printed.

        A change is reversible: remove sets each DNG back. No pixel changes.
        \(RunSummary.lightroomHint)

        Exit codes:
          0  The command completed, no file failed, and no file was blocked. A
             scan that completed gives 0, also for a read-only folder.
          1  A file failed or was blocked, the run was stopped, the folder could
             not be read, a run or a dry run met a read-only folder, or exiftool
             is missing.
          2  The command line was wrong.
        """

    /// What standard error gets for a usage error: the reason, and one line
    /// that points to the help.
    public static func error(_ error: UsageError) -> [String] {
        ["desqueeze: \(error.message)", "See desqueeze --help."]
    }
}
