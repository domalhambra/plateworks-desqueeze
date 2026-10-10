import Foundation

/// One run over a folder (design, section 4.3).
///
/// Order: scan the folder, convert every pending ARW, then tag every DNG, the
/// new ones last. One file at a time. Cancel is honored between files.
///
/// **Which converter.** Before the first conversion, the run asks once for
/// the facts of every pending ARW, and `ConverterChoice` gives each ARW its
/// list of converters (design 13.4). `ARWFactsReader` answers with one
/// exiftool call for each 200 files. The run tries them in order. The
/// dry run asks the same function, and names the first one.
///
/// **A failed conversion.** When a converter fails, the next one in the list
/// gets the ARW. The ARW is listed as failed only when the last one failed,
/// and the run goes on. The note's detail has one line for each converter
/// that was tried, with that converter's own words.
/// A cancel between two converters stops the run there: the next converter
/// does not start for that ARW. The ARW is listed as failed, with the words
/// of the converters that were tried, and the run is stopped.
/// When a converter left a partial output, the job moves it to the Trash
/// through `BackupHandling.trashFile` and says so on that converter's line,
/// or names the file to delete when the Trash refuses (design 4.3). For
/// either converter that file is the hidden work file of the ARW (design
/// 13.3). The job moves only that file, and never a `<base>.dng`
/// (`discard`). The ARW is never touched.
///
/// **When the next converter is not tried.** A converter can say that its
/// failure holds for every converter (`ConvertError.failedForAll`): another
/// program took the name `<base>.dng` while the converter worked, or a
/// leftover file is in the way: `<base>.dng_exiftool_tmp`, a work file that
/// the Trash refused, or a folder or a link at the name of the work file.
/// The ARW is then failed with that converter's words, and the next
/// converter does not start. The same holds when the Trash refuses the work
/// file of a failed conversion: a work file that cannot be removed stops
/// the ARW, in this run as in the next one, and the note names it.
///
/// **A DNG with no full match.** With dnglab alone, an ARW that the table
/// does not cover still converts. It counts as converted, and it gets a
/// `convertedUnmatched` note. It is not failed and not blocked.
///
/// The notes of a run start with one note for each orphan backup in the
/// folder, so every front end reports them.
///
/// **The ARW files a run left.** `RunSummary.unconvertedARWs` is the number of
/// pending ARW files in the run's own scan, minus the ones this run converted.
/// So it counts every pending ARW when no converter is installed or `convert`
/// is false, an ARW whose conversion failed (that one is in `failed` too), and
/// the ARW files that a stopped run did not reach. Remove is the exception:
/// it has no ARW work, so it reports 0. A caller says that it means Remove
/// with `remove: true`. The job never guesses it from the factor and
/// `convert`: `run` at factor 1 with `convert` false is not Remove, and it
/// reports the ARW files it left (design 12.1).
public struct DesqueezeJob: Sendable {
    private let tag: ScaleTagging
    private let converters: RawConverters
    private let backups: BackupHandling

    /// - Parameter converters: dnglab and Adobe DNG Converter, each nil when
    ///   it is not installed, and the reader of the ARW facts. With neither
    ///   converter the ARW files wait, and the DNG files still run.
    /// - Parameter backups: where a backup goes after a write that passed its
    ///   check, and where the partial output of a failed conversion goes. There
    ///   is no default, so no caller reaches the Trash by
    ///   leaving it out. The window and the tool name the Trash themselves.
    public init(tag: ScaleTagging, converters: RawConverters, backups: BackupHandling) {
        self.tag = tag
        self.converters = converters
        self.backups = backups
    }

    /// Scans `folder`, then runs on what that scan found.
    ///
    /// This is the only public way to run. Each skip is decided on what the
    /// folder holds at the call, never on what a front end read earlier.
    ///
    /// - Parameters:
    ///   - convert: false leaves the ARW files alone.
    ///   - remove: true for Remove. Remove writes `.noStretch` whatever
    ///     `factor` says, so a factor given beside it never reaches a file.
    ///     It never converts, whatever `convert` says, and it reports no ARW
    ///     files left.
    /// - Throws: only when the scan fails. No file is changed then. A file
    ///   that fails during the run is a note in the summary, not an error.
    public func run(
        folder: URL,
        factor: SqueezeFactor,
        convert: Bool,
        remove: Bool = false,
        cancel: CancelFlag = CancelFlag(),
        progress: (RunProgress) -> Void = { _ in }
    ) throws -> RunSummary {
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        return run(snapshot, factor: factor, convert: convert, remove: remove, cancel: cancel, progress: progress)
    }

    /// Scans `folder`, and returns what a run would do. Changes no file.
    ///
    /// The tool calls are reads: the scan's one read of the folder, and the
    /// read of the ARW facts when dnglab is installed and an ARW would
    /// convert. No converter starts.
    ///
    /// `convert` and `remove` mean what they mean for `run`.
    ///
    /// - Throws: only when the scan fails.
    public func plan(folder: URL, factor: SqueezeFactor, convert: Bool, remove: Bool = false) throws -> RunPlan {
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        return plan(snapshot, factor: factor, convert: convert, remove: remove)
    }

    // MARK: What the run and the dry run share

    /// The summary before the first file: the ARW files to account for, and
    /// the notes about the folder itself.
    private func opening(_ snapshot: FolderSnapshot, remove: Bool) -> RunSummary {
        var summary = RunSummary()
        summary.folderIsEmpty = snapshot.isEmpty
        summary.unconvertedARWs = remove ? 0 : snapshot.pendingARWs.count
        guard snapshot.isWritable else {
            summary.notes = [.folderReadOnly(snapshot.folder)]
            return summary
        }
        // An orphan backup may be the only copy of a photo, and it is in no
        // count. The run does not touch it. The run names it first, before
        // any file, so a cancelled run names it too.
        summary.notes = snapshot.orphanBackups.map { .orphanBackup(named: $0.lastPathComponent) }
        return summary
    }

    /// One pending ARW that goes to a converter, with what the run knows
    /// about it before the first program starts.
    private struct Pending {
        let arw: URL
        /// `ARWFacts.none` when exiftool could not read them, and when no
        /// one asked: with no dnglab, no fact changes anything.
        let facts: ARWFacts
        /// The converters to try, in order. Never empty.
        let order: [ConverterKind]
    }

    /// The ARW files that go to a converter, each with its facts and its
    /// list of converters. Remove never converts. With neither converter the
    /// ARW files wait.
    ///
    /// The facts come from one request for all the files. The read changes
    /// no file, so the dry run makes it too.
    private func arwsToConvert(_ snapshot: FolderSnapshot, convert: Bool) -> [Pending] {
        guard convert, converters.canConvert, !snapshot.pendingARWs.isEmpty else { return [] }
        let facts = converters.dnglab == nil ? [:] : converters.facts?.read(snapshot.pendingARWs) ?? [:]
        return snapshot.pendingARWs.map { arw in
            let known = facts[arw.lastPathComponent] ?? .none
            return Pending(arw: arw, facts: known, order: ConverterChoice.order(
                for: known, dnglabInstalled: converters.dnglab != nil, adobeInstalled: converters.adobe != nil))
        }
    }

    /// Counts one conversion, and adds the DNG to the files to tag.
    ///
    /// - Parameter unmatched: the rule that kept a dnglab DNG from a full
    ///   match. The note is made here, so the run and the dry run say the
    ///   same words.
    private static func count(
        _ pending: Pending, to dng: URL, by converter: ConverterKind, unmatched: AdobeMatch.Rule?,
        _ summary: inout RunSummary, _ dngs: inout [DNGFile]
    ) {
        switch converter {
        case .dnglab: summary.convertedByDnglab += 1
        case .adobe: summary.convertedByAdobe += 1
        }
        summary.unconvertedARWs -= 1
        if let unmatched {
            summary.notes.append(.convertedUnmatched(dng.lastPathComponent, rule: unmatched, facts: pending.facts))
        }
        dngs.append(Self.converted(pending.arw, to: dng))
    }

    /// Remove writes `.noStretch` and nothing else. The wrong state, Remove
    /// with a stretch, cannot reach a file.
    private static func factor(_ factor: SqueezeFactor, remove: Bool) -> SqueezeFactor {
        remove ? .noStretch : factor
    }

    /// The DNG of a conversion. Neither converter writes a stretch, so the
    /// scale is known, and the job does not read the new file.
    private static func converted(_ arw: URL, to dng: URL) -> DNGFile {
        DNGFile(url: dng, scale: .noStretch, originalRawFileName: arw.lastPathComponent, hasBackup: false)
    }

    /// Asked at the moment of each file, not taken from the scan.
    private func decide(_ dng: DNGFile, _ factor: SqueezeFactor) -> (decision: TagDecision, hasBackup: Bool) {
        let hasBackup = backups.backupExists(for: dng.url)
        return (TagDecision.decide(scale: dng.scale, hasBackup: hasBackup, factor: factor), hasBackup)
    }

    // MARK: The dry run

    /// The plan itself, on a snapshot. Not public, for the reason at `run`.
    ///
    /// It walks the files in the order of `run`, and asks the same questions.
    /// It assumes that each write passes, and that each conversion passes
    /// with the first converter of its list.
    func plan(_ snapshot: FolderSnapshot, factor: SqueezeFactor, convert: Bool, remove: Bool = false) -> RunPlan {
        let factor = Self.factor(factor, remove: remove)
        var plan = RunPlan(steps: [], summary: opening(snapshot, remove: remove))
        guard snapshot.isWritable else { return plan }

        var dngs = snapshot.dngs
        for pending in arwsToConvert(snapshot, convert: convert && !remove) {
            let first = pending.order[0]
            plan.steps.append(RunPlan.Step(name: pending.arw.lastPathComponent, action: .convert, converter: first))
            // The DNG is not there yet. The run will tag it, so the plan
            // must decide for it too. Only dnglab makes a DNG with no full
            // match, and it says the rule that `AdobeMatch` says here.
            Self.count(pending, to: ConverterOutput.url(for: pending.arw), by: first,
                       unmatched: first == .dnglab ? AdobeMatch.match(pending.facts).failed : nil,
                       &plan.summary, &dngs)
        }
        for dng in dngs {
            let (decision, hasBackup) = decide(dng, factor)
            plan.steps.append(RunPlan.Step(name: dng.name, action: RunPlan.Action(decision)))
            plan.summary.count(decision, for: dng.name, hasBackup: hasBackup)
            if decision == .write { plan.summary.set += 1 }
        }
        return plan
    }

    // MARK: The run

    /// The run itself, on a snapshot.
    ///
    /// Not public, on purpose. A snapshot is true only at the moment of its
    /// scan. A window that kept one across a run made Remove report "skipped"
    /// for files that the run had just stretched. Tests reach this method
    /// with `@testable`, to give the job a folder state without a folder.
    func run(
        _ snapshot: FolderSnapshot,
        factor: SqueezeFactor,
        convert: Bool,
        remove: Bool = false,
        cancel: CancelFlag = CancelFlag(),
        progress: (RunProgress) -> Void = { _ in }
    ) -> RunSummary {
        let factor = Self.factor(factor, remove: remove)
        var summary = opening(snapshot, remove: remove)
        guard snapshot.isWritable else { return summary }

        let arws = arwsToConvert(snapshot, convert: convert && !remove)
        var dngs = snapshot.dngs
        var total = arws.count * 2 + dngs.count
        var completed = 0

        for pending in arws {
            if cancel.isCancelled {
                summary.cancelled = true
                return summary
            }
            // Each converter's own words, in the order of the tries.
            var words: [String] = []
            var made: (conversion: Conversion, converter: ConverterKind)?
            var tried = 0
            var leftAConverterUntried = false
            for kind in pending.order {
                guard let converter = converters[kind] else { continue }
                // A cancel that came while the converter before this one
                // worked. This one does not start.
                if tried > 0, cancel.isCancelled {
                    leftAConverterUntried = true
                    break
                }
                tried += 1
                do {
                    made = (try converter.convert(pending.arw, facts: pending.facts), kind)
                    break
                } catch {
                    var text = Self.describe(error)
                    // The failure holds for every converter.
                    var stop = false
                    if case ConvertError.failedForAll = error { stop = true }
                    if let partial = (error as? ConvertError)?.partial {
                        switch discard(partial: partial, of: pending.arw) {
                        case .moved:
                            // After "A DNG with this name exists already",
                            // these words would read as if that DNG moved.
                            if !stop { text += " The partial DNG was moved to the Trash." }
                        case .refused:
                            text += " A partial DNG, \(partial.lastPathComponent), is beside the ARW."
                                + ConverterOutput.hint(forFileNamed: partial.lastPathComponent)
                                + " Delete it, then run again."
                            // The work file is still there. The next
                            // converter, and the next run, would stop at it
                            // too (design 13.3, step 1), so this one stops
                            // here.
                            stop = true
                        case .notThisRuns:
                            text += " A file, \(partial.lastPathComponent), was reported as the partial DNG. "
                                + "It is not this run's file, and it was not moved."
                        }
                    }
                    // Both converters refuse a name that is taken, with
                    // the same sentence. One line says it.
                    if !words.contains(text) { words.append(text) }
                    if stop { break }
                }
            }
            if let made {
                Self.count(pending, to: made.conversion.dng, by: made.converter,
                           unmatched: made.conversion.unmatched, &summary, &dngs)
            } else {
                summary.failed += 1
                // This ARW made no DNG, so its tag step will not happen.
                total -= 1
                summary.notes.append(.notConverted(pending.arw.lastPathComponent,
                                                   detail: words.joined(separator: "\n")))
            }
            completed += 1
            progress(RunProgress(completed: completed, total: total, name: pending.arw.lastPathComponent))
            // Also for the last file of the run: the ARW could still have
            // converted, so work is left undone.
            if leftAConverterUntried {
                summary.cancelled = true
                return summary
            }
        }

        for dng in dngs {
            if cancel.isCancelled {
                summary.cancelled = true
                return summary
            }
            tagOne(dng, factor, &summary)
            completed += 1
            progress(RunProgress(completed: completed, total: total, name: dng.name))
        }
        return summary
    }

    /// What `discard` did with a partial output.
    private enum Discarded {
        case moved
        /// The Trash refused the file. It is where it was.
        case refused
        /// The second lock held: the file is not this run's, and it is
        /// where it was.
        case notThisRuns
    }

    /// Moves the partial output of a failed conversion to the Trash. The ARW
    /// is never touched.
    ///
    /// A converter reports only its work file (`ConverterRules`). This is a
    /// second lock, and it does not take the converter's word. One rule
    /// holds for both converters: a file moves only when its path is exactly
    /// the work file of this ARW (`ConverterOutput.workURL`). The name is
    /// this app's own, and the scan never lists it.
    ///
    /// Any other file stays where it is. So a `<base>.dng` never moves: no
    /// converter writes to that name, and a file there is someone else's.
    private func discard(partial: URL, of arw: URL) -> Discarded {
        guard partial.path == ConverterOutput.workURL(for: arw).path else { return .notThisRuns }
        do {
            try backups.trashFile(partial)
            return .moved
        } catch {
            return .refused
        }
    }

    private func tagOne(_ dng: DNGFile, _ factor: SqueezeFactor, _ summary: inout RunSummary) {
        let (decision, hasBackup) = decide(dng, factor)
        summary.count(decision, for: dng.name, hasBackup: hasBackup)
        guard decision == .write else { return }

        do {
            try tag.write(factor, to: dng.url)
            guard factor.matches(try tag.read(dng.url)) else {
                throw TagError.toolFailed("The tag did not read back as \(factor.tagValue).")
            }
        } catch {
            // A failed write makes no backup and leaves the file unchanged.
            // Restore only when a backup exists.
            var message = "Not changed."
            var detail = Self.describe(error)
            if backups.backupExists(for: dng.url) {
                do {
                    try backups.restoreBackup(for: dng.url)
                    message = "Not changed. The backup was restored."
                } catch let restoreError {
                    // The write may have passed and the check failed, so the
                    // file may be changed. "The write failed" would be wrong.
                    message = "The change failed, and the backup could not be restored. The backup is \(dng.name)_original."
                    detail += "\nRestore: " + Self.describe(restoreError)
                }
            }
            summary.failed += 1
            summary.notes.append(.failed(dng.name, message: message, detail: detail))
            return
        }

        summary.set += 1
        do {
            try backups.trashBackup(for: dng.url)
        } catch {
            summary.notes.append(.backupKept(dng.name, detail: error.localizedDescription))
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case TagError.toolFailed(let text): return text
        case let error as ConvertError: return error.text
        default: return error.localizedDescription
        }
    }
}
