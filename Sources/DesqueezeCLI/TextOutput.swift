import DesqueezeCore

/// The output for a person. Each function is pure: a report in, lines out.
public enum TextOutput {
    static let readOnlyFolder = "This folder is read-only. Desqueeze cannot change its files."
    static let lightroomHint = "Photos already in Lightroom: Metadata › Read Metadata from File."

    /// A short table of the DNG files, then the ARW files with no DNG, then
    /// the messages about the folder, then where the two tools are.
    public static func scan(_ report: ScanReport) -> [String] {
        var lines = [report.folder, ""]
        if report.isEmpty {
            lines.append("No DNG or ARW files in this folder.")
        } else {
            lines.append("DNG files: \(report.dngs.count)")
            if !report.dngs.isEmpty {
                let width = max(report.dngs.map(\.name.count).max() ?? 0, "Name".count)
                func row(_ name: String, _ rest: String) -> String {
                    "  " + name.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + rest
                }
                lines.append(row("Name", "Scale"))
                for dng in report.dngs {
                    let scale = dng.scale ?? "unknown"
                    lines.append(row(dng.name, dng.hasBackup ? "\(scale)  (a backup is beside it)" : scale))
                }
            }
            lines.append("")
            lines.append("ARW files with no DNG: \(report.pendingARWs.count)")
            lines += report.pendingARWs.map { "  \($0)" }
        }
        lines.append("")

        var messages = report.orphanBackups.map { line(for: .orphanBackup(named: $0)) }
        if !report.writable { messages.append(readOnlyFolder) }
        if !messages.isEmpty { lines += messages + [""] }

        lines.append("exiftool: \(report.exiftool)")
        lines.append("Adobe DNG Converter: "
            + (report.dngConverter ?? "not installed. ARW files cannot be converted."))
        return lines
    }

    /// The window's line of counts, then one line for each note, with the
    /// tool's own words below it. A dry run shows its steps first.
    ///
    /// - Parameter converterInstalled: false adds the reason to the line
    ///   about the ARW files that the run left.
    public static func run(_ report: RunReport, converterInstalled: Bool) -> [String] {
        var lines: [String] = []
        if let steps = report.steps {
            lines.append("Dry run. No file was changed.")
            lines += steps.map {
                "  " + $0.action.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0) + "  " + $0.name
            }
            lines.append("A run would give: \(report.countsLine)")
        } else {
            lines.append(report.countsLine)
        }
        for note in report.notes {
            lines.append(line(for: note))
            // The detail of a failed restore has two lines.
            lines += (note.detail ?? "").split(separator: "\n").map { "    \($0)" }
        }
        if report.unconvertedARWs > 0 {
            let count = report.unconvertedARWs == 1 ? "1 ARW file" : "\(report.unconvertedARWs) ARW files"
            let verb = report.dryRun ? "would not be" : (report.unconvertedARWs == 1 ? "was not" : "were not")
            lines.append("\(count) \(verb) converted."
                + (converterInstalled ? "" : " Adobe DNG Converter is not installed."))
        }
        // Lightroom reads the tag at import, and keeps what it read.
        if !report.dryRun, report.set > 0 { lines.append(lightroomHint) }
        return lines
    }

    private static func line(for note: FileNote) -> String { "\(note.name): \(note.message)" }
}
