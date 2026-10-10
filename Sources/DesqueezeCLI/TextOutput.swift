import DesqueezeCore

/// The output for a person. Each function is pure: a report in, lines out.
///
/// Every sentence that the window also shows is made in `DesqueezeCore`
/// (`FolderText`, `FileNote`, `RunSummary`, `RunReport`). This type only
/// lays them out.
public enum TextOutput {
    /// A short table of the DNG files, then the ARW files with no DNG, then
    /// the messages about the folder, then where the three tools are:
    /// exiftool, dnglab, and Adobe DNG Converter, in this order. The line
    /// of advice about the converters is last, when there is one
    /// (`FolderText.converterAdvice`, design 13.5). With neither converter, a
    /// line before it says that the ARW files cannot be converted.
    public static func scan(_ report: ScanReport) -> [String] {
        var lines = [report.folder, ""]
        if report.isEmpty {
            lines.append(FolderText.noPhotos)
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

        // The window names five orphan backups. This is a list, so it names
        // every one.
        let messages = FolderText.messages(isWritable: report.writable, orphanBackups: report.orphanBackups,
                                           namedOrphanLimit: nil)
        if !messages.isEmpty { lines += messages + [""] }

        lines.append("exiftool: \(report.exiftool)")
        lines.append("\(ConverterKind.dnglab.name): \(report.dnglab ?? "not installed")")
        // The advice line says what a missing converter means, so this one
        // says only that it is missing.
        lines.append("\(ConverterKind.adobe.name): \(report.dngConverter ?? "not installed")")
        // With neither converter: that the ARW files cannot convert, then
        // what to do about it.
        if let cannot = report.arwsCannotConvertLine { lines.append(cannot) }
        if let advice = report.converterAdvice { lines.append(advice) }
        return lines
    }

    /// The window's line of counts, then one line for each note, with the
    /// tool's own words below it. A dry run shows its steps first, and a
    /// convert step names the converter that gets the ARW first. When both
    /// converters did work in a run, one line after the counts says how
    /// many ARW files each converted. After a run that was asked to move the
    /// originals, the next line says how many moved (design 14.3). After a
    /// run that set at least one photo, the Lightroom line is last. The
    /// note of a volume that gives no folder lock (design 13.9) is a note
    /// as any other, and the core puts it first.
    ///
    /// In a dry run, the step of an original that the run would move reads
    /// `  trash    frame.ARW` (design 14.5).
    ///
    /// - Parameter converterInstalled: true when one converter or the other
    ///   is installed. False adds the reason to the line about the ARW files
    ///   that the run left: no converter is installed.
    public static func run(_ report: RunReport, converterInstalled: Bool) -> [String] {
        var lines: [String] = []
        if let steps = report.steps {
            lines.append("Dry run. No file was changed.")
            lines += steps.map {
                "  " + word(for: $0.action).padding(toLength: 7, withPad: " ", startingAt: 0) + "  " + $0.name
                    + ($0.converter.map { "  with \($0.name)" } ?? "")
            }
            lines.append(report.folderIsEmpty ? FolderText.noPhotos : "A run would give: \(report.countsLine)")
        } else {
            // A folder with nothing in it has no counts worth a line.
            lines.append(report.folderIsEmpty ? FolderText.noPhotos : report.countsLine)
        }
        // Nil for a dry run: its steps name the converters.
        if let converters = report.convertersLine { lines.append(converters) }
        // Only after a run that was asked to move the originals. Nil for a
        // dry run: its steps name each ARW that a run would move.
        if let originals = report.originalsLine { lines.append(originals) }
        for note in report.notes {
            lines.append(note.line)
            // The detail of a failed restore has two lines.
            lines += (note.detail ?? "").split(separator: "\n").map { "    \($0)" }
        }
        if let left = report.unconvertedARWsLine(converterAvailable: converterInstalled) { lines.append(left) }
        // Lightroom reads the tag at import, and keeps what it read. The
        // core decides when the line shows, so the window shows it for the
        // same runs.
        if let lightroom = report.lightroomLine { lines.append(lightroom) }
        return lines
    }

    /// The word of a step in the text of a dry run. It is the name of the
    /// action in the JSON, but for `trashOriginal`, which is `trash`.
    static func word(for action: RunPlan.Action) -> String {
        action == .trashOriginal ? "trash" : action.rawValue
    }
}
