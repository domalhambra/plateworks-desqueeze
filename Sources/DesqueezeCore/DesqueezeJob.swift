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
/// (`discard`). A failed conversion never touches the ARW.
///
/// **When the next converter is not tried.** A converter can say that its
/// failure holds for every converter (`ConvertError.failedForAll`): another
/// program took the name `<base>.dng` while the converter worked, or a
/// leftover file is in the way: `<base>.dng_exiftool_tmp`, a work file that
/// the Trash refused, or a folder or a link at the name of the work file.
/// Or a name that the conversion needs would be longer than a file name can
/// be (design 13.9).
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
/// folder, so every front end reports them. Only the note of a volume that
/// gives no folder lock stands before them (`noFolderLock`).
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
///
/// **The originals, on request** (design 14). A caller can ask a run to
/// move each original ARW to the Trash. `run` and `plan` take the request as
/// `trashOriginals`, with no default value, so every caller states it.
/// Remove never moves an original, whatever it is given. With the request,
/// the run has a fifth step, after the tag of the last DNG: for each ARW
/// that this run converted, `OriginalDecision.decide` says "move" or "keep".
/// For that, the run records each ARW before its conversion, and each new
/// DNG after its conversion and after its tag step: an ARW moves only when
/// it is the file that was converted, and its DNG is the file that this run
/// made (lines 4 and 6). A DNG that is not the run's own is still tagged.
/// The ARW moves through `BackupHandling.trashFile`, the function that takes
/// a backup, so no test reaches the Trash. An ARW that stays gets an
/// `originalKept` note. A refusal of the Trash keeps the ARW with that note:
/// the job never deletes one, and it tries no second way. The step does not
/// start after a cancel, and it reads the cancel flag between two ARW
/// files. `RunSummary.originalsInTrash` counts the files that moved.
///
/// **One run in a folder at a time.** `run(folder:)` takes the lock of
/// `FolderLock` on the folder before its scan, and holds it until it returns
/// or throws (design 13.9). When another run holds the lock, it throws
/// `FolderLock.Busy` and has read and changed nothing. On a volume that has
/// no such lock, the run goes on without one, and its summary starts with a
/// `noFolderLock` note. When the lock call fails for any other reason, it
/// throws `FolderLock.Failed` and has read and changed nothing. The dry run
/// takes no lock.
public struct DesqueezeJob: Sendable {
    private let tag: ScaleTagging
    private let converters: RawConverters
    private let backups: BackupHandling
    private let lock: FolderLock
    private let fileRecord: @Sendable (String) -> FileRecord?
    private let verbose: @Sendable (String) -> Void

    /// - Parameter tag: reads and writes the `DefaultScale` tag.
    /// - Parameter converters: dnglab and Adobe DNG Converter, each nil when
    ///   it is not installed, and the reader of the ARW facts. With neither
    ///   converter the ARW files wait, and the DNG files still run.
    /// - Parameter backups: where a backup goes after a write that passed its
    ///   check, and where the partial output of a failed conversion goes. There
    ///   is no default, so no caller reaches the Trash by
    ///   leaving it out. Each of the three front ends names the Trash
    ///   itself.
    /// - Parameter lock: the lock that keeps a second run out of the folder.
    ///   The default is the system's. It makes no file and reaches nothing
    ///   outside the folder, so every front end takes it by leaving it out.
    /// - Parameter fileRecord: what the disk says about the file at a path,
    ///   read without following a link. The run asks it about an ARW before
    ///   the conversion and before the move (design 14.2, line 4). It asks
    ///   it about the DNG of that ARW six times at most: after the
    ///   conversion, before the tag step, after a tag step that wrote, and
    ///   three times before the move (line 6, line 5, and line 6 again). It asks only when it was asked to move the originals. The
    ///   default is `FileRecord.read`, which changes no file. Tests inject
    ///   it to drive each outcome.
    /// - Parameter verbose: gets one line when the volume gave no lock for
    ///   the folder, with the number of the error
    ///   (`FolderLock.noLockLine`). Give it the sink of the
    ///   `LoggingProcessRunner`: the line then stands before the first
    ///   command of the run. The default says nothing.
    public init(tag: ScaleTagging, converters: RawConverters, backups: BackupHandling, lock: FolderLock = .system,
                fileRecord: @escaping @Sendable (String) -> FileRecord? = { FileRecord.read(atPath: $0) },
                verbose: @escaping @Sendable (String) -> Void = { _ in }) {
        self.tag = tag
        self.converters = converters
        self.backups = backups
        self.lock = lock
        self.fileRecord = fileRecord
        self.verbose = verbose
    }

    /// Scans `folder`, then runs on what that scan found.
    ///
    /// This is the only public way to run. Each skip is decided on what the
    /// folder holds at the call, never on what a front end read earlier.
    ///
    /// - Parameters:
    ///   - folder: the folder to scan and to run on. Its top level only.
    ///   - factor: the stretch to set.
    ///   - convert: false leaves the ARW files alone.
    ///   - trashOriginals: true moves each ARW that this run converted to
    ///     the Trash, when every line of design 14.2 holds for it. There is
    ///     no default, so no caller moves an original by leaving it out, and
    ///     none forgets to say that it does not.
    ///   - remove: true for Remove. Remove writes `.noStretch` whatever
    ///     `factor` says, so a factor given beside it never reaches a file.
    ///     It never converts, whatever `convert` says, it never moves an
    ///     original, whatever `trashOriginals` says, and it reports no ARW
    ///     files left.
    ///   - cancel: stops the run after its current file, when it is set.
    ///   - progress: called after each step: one for each conversion, one
    ///     for each DNG, and one for each original that the fifth step
    ///     handles.
    /// - Throws: `FolderLock.Busy` when another run works in the folder,
    ///   `FolderLock.Failed` when the lock call failed, and any other error
    ///   only when the scan fails. No file is changed then. A file that
    ///   fails during the run is a note in the summary, not an error.
    public func run(
        folder: URL,
        factor: SqueezeFactor,
        convert: Bool,
        trashOriginals: Bool,
        remove: Bool = false,
        cancel: CancelFlag = CancelFlag(),
        progress: (RunProgress) -> Void = { _ in }
    ) throws -> RunSummary {
        // Before the scan, so nothing is read for a run that does not start.
        let held = try takeLock(on: folder)
        // Also when the scan throws. The lock is not left to the end of
        // `held`: the run must hold it to its last file, and the last file
        // can be an original on its way to the Trash (design 14.2).
        defer { held?.release() }
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        var summary = run(snapshot, factor: factor, convert: convert, trashOriginals: trashOriginals, remove: remove,
                          cancel: cancel, progress: progress)
        // The run worked with no lock: the volume gives none. The note is
        // about the folder, so it is the first one (design 13.9).
        if held == nil { summary.notes.insert(.noFolderLock(snapshot.folder), at: 0) }
        return summary
    }

    /// The lock on `folder` for one run (design 13.9).
    ///
    /// - Returns: the lock, or nil when the volume has none for a folder. The
    ///   run then goes on without one, and `verbose` has got the number of
    ///   the error.
    /// - Throws: `FolderLock.Busy` when another run holds the lock, and
    ///   `FolderLock.Failed` when the lock call failed for a reason that
    ///   says nothing about the lock. When the folder could not be opened,
    ///   the error of the scan: that is the path of a folder that could not
    ///   be read, with the words it has always had. If that scan passes all
    ///   the same, the error of the open.
    private func takeLock(on folder: URL) throws -> FolderLock.Held? {
        switch lock.take(folder) {
        case .held(let held):
            return held
        case .busy:
            throw FolderLock.Busy()
        case .noLockOnThisVolume(let code):
            verbose(FolderLock.noLockLine(code: code))
            return nil
        case .failed(let code):
            throw FolderLock.Failed(code: code)
        case .unreadable(let code):
            _ = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// Scans `folder`, and returns what a run would do. Changes no file.
    ///
    /// The tool calls are reads: the scan's one read of the folder, and the
    /// read of the ARW facts when dnglab is installed and an ARW would
    /// convert. No converter starts.
    ///
    /// `convert`, `trashOriginals` and `remove` mean what they mean for
    /// `run`. With `trashOriginals`, the plan has one `trashOriginal` step
    /// for each ARW that the run would move, after the steps of the DNG
    /// files. It reads no ARW and no DNG for them: it plans a run in which
    /// every step passes.
    ///
    /// - Throws: only when the scan fails.
    public func plan(folder: URL, factor: SqueezeFactor, convert: Bool, trashOriginals: Bool,
                     remove: Bool = false) throws -> RunPlan {
        let snapshot = try FolderScanner(tag: tag, backups: backups).snapshot(of: folder)
        return plan(snapshot, factor: factor, convert: convert, trashOriginals: trashOriginals, remove: remove)
    }

    // MARK: What the run and the dry run share

    /// The summary before the first file: the ARW files to account for,
    /// whether the run moves the originals, and the notes about the folder
    /// itself.
    private func opening(_ snapshot: FolderSnapshot, remove: Bool, movesOriginals: Bool) -> RunSummary {
        var summary = RunSummary()
        summary.folderIsEmpty = snapshot.isEmpty
        summary.trashOriginals = movesOriginals
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

    /// Whether this run has the fifth step (design 14.2). Remove never has
    /// it. The run and the dry run both ask here.
    private static func movesOriginals(_ trashOriginals: Bool, remove: Bool) -> Bool {
        trashOriginals && !remove
    }

    /// One ARW that this run converted, with what the fifth step needs to
    /// know about it (design 14.2).
    private struct Original {
        let arw: URL
        let dng: URL
        /// Line 2: false when the conversion has a `convertedUnmatched`
        /// note.
        let hasFullMatch: Bool
        /// Line 4: the record from before the conversion. Nil when the disk
        /// gave none, and in a plan, which reads no ARW.
        let recorded: FileRecord?
        /// Line 6, the first record: the DNG directly after the conversion
        /// passed. Nil when the disk gave none, and in a plan, which reads
        /// no DNG.
        let dngAsMade: FileRecord?
        /// Line 6: true when the DNG was the file of `dngAsMade` directly
        /// before its tag step. False until the tag loop asks, so a DNG
        /// that the loop never reached is not this run's.
        var dngHeldUntilItsTagStep = false
        /// Line 6, the second record: the DNG directly after its tag step
        /// ended. exiftool writes a new file, so it differs from
        /// `dngAsMade` after a write. After a tag step that skipped, it is
        /// `dngAsMade` itself, with no new read. Nil until the tag step
        /// has ended.
        var dngAsTagged: FileRecord?
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
    /// with the first converter of its list. One conversion is known to
    /// fail before any program starts: an ARW whose name is too long for
    /// the files that a conversion makes (design 13.9). The plan gives it
    /// no `convert` step, and the note of the run.
    func plan(_ snapshot: FolderSnapshot, factor: SqueezeFactor, convert: Bool, trashOriginals: Bool,
              remove: Bool = false) -> RunPlan {
        let factor = Self.factor(factor, remove: remove)
        let movesOriginals = Self.movesOriginals(trashOriginals, remove: remove)
        var plan = RunPlan(steps: [], summary: opening(snapshot, remove: remove, movesOriginals: movesOriginals))
        guard snapshot.isWritable else { return plan }

        var dngs = snapshot.dngs
        var originals: [Original] = []
        for pending in arwsToConvert(snapshot, convert: convert && !remove) {
            // The rule of `ConverterRules`, rule 0, which every converter
            // follows: no program starts, and the ARW is failed.
            guard !ConverterOutput.nameIsTooLong(for: pending.arw) else {
                plan.summary.failed += 1
                plan.summary.notes.append(.notConverted(pending.arw.lastPathComponent,
                                                        detail: ConverterRules.nameTooLong))
                continue
            }
            let first = pending.order[0]
            plan.steps.append(RunPlan.Step(name: pending.arw.lastPathComponent, action: .convert, converter: first))
            // The DNG is not there yet. The run will tag it, so the plan
            // must decide for it too. Only dnglab makes a DNG with no full
            // match, and it says the rule that `AdobeMatch` says here.
            let dng = ConverterOutput.url(for: pending.arw)
            let unmatched = first == .dnglab ? AdobeMatch.match(pending.facts).failed : nil
            Self.count(pending, to: dng, by: first, unmatched: unmatched, &plan.summary, &dngs)
            originals.append(Original(arw: pending.arw, dng: dng, hasFullMatch: unmatched == nil, recorded: nil,
                                      dngAsMade: nil))
        }
        // The path of each DNG whose tag step ends with the DNG at the
        // factor: a write that passes, or a skip.
        var atTheFactor = Set<String>()
        for dng in dngs {
            let (decision, hasBackup) = decide(dng, factor)
            plan.steps.append(RunPlan.Step(name: dng.name, action: RunPlan.Action(decision)))
            plan.summary.count(decision, for: dng.name, hasBackup: hasBackup)
            if decision == .write { plan.summary.set += 1 }
            if decision != .blocked { atTheFactor.insert(dng.url.path) }
        }
        guard movesOriginals else { return plan }
        for original in originals {
            // The function of the run. The plan reads no file for lines 6,
            // 5 and 4: it plans a run in which they hold.
            let decision = OriginalDecision.decide(
                hasFullMatch: original.hasFullMatch, dngIsAtTheFactor: atTheFactor.contains(original.dng.path),
                dngIsThisRuns: { true }, dng: { .passed }, dngIsStillThisRuns: { true }, original: { .same })
            switch decision {
            case .move:
                plan.steps.append(RunPlan.Step(name: original.arw.lastPathComponent, action: .trashOriginal))
                plan.summary.originalsInTrash += 1
            case .keep(let reason):
                plan.summary.notes.append(.originalKept(original.arw.lastPathComponent, because: reason))
            }
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
        trashOriginals: Bool,
        remove: Bool = false,
        cancel: CancelFlag = CancelFlag(),
        progress: (RunProgress) -> Void = { _ in }
    ) -> RunSummary {
        let factor = Self.factor(factor, remove: remove)
        let movesOriginals = Self.movesOriginals(trashOriginals, remove: remove)
        var summary = opening(snapshot, remove: remove, movesOriginals: movesOriginals)
        guard snapshot.isWritable else { return summary }

        let arws = arwsToConvert(snapshot, convert: convert && !remove)
        var dngs = snapshot.dngs
        // An ARW that converts has a conversion, the tag of its DNG, and,
        // when the run moves the originals, the step of its original.
        let stepsOfAnARW = movesOriginals ? 3 : 2
        var total = arws.count * stepsOfAnARW + dngs.count
        var completed = 0
        // Only a run that moves the originals fills this list. With the
        // option off it stays empty, so the fifth step has no file.
        var originals: [Original] = []
        // The place in `originals` of each ARW, by the path of its DNG. The
        // tag loop finds the DNG files of this run with it (line 6).
        var originalOfDNG: [String: Int] = [:]

        for pending in arws {
            if cancel.isCancelled {
                summary.cancelled = true
                return summary
            }
            // Line 4 of design 14.2: the ARW as it is before any converter
            // starts. Not asked when the originals stay.
            let recorded = movesOriginals ? fileRecord(pending.arw.path) : nil
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
                // Line 6 of design 14.2, the first record: the DNG directly
                // after its conversion passed, before anything else is
                // done. Not asked when the originals stay.
                let dngAsMade = movesOriginals ? fileRecord(made.conversion.dng.path) : nil
                Self.count(pending, to: made.conversion.dng, by: made.converter,
                           unmatched: made.conversion.unmatched, &summary, &dngs)
                if movesOriginals {
                    originalOfDNG[made.conversion.dng.path] = originals.count
                    originals.append(Original(arw: pending.arw, dng: made.conversion.dng,
                                              hasFullMatch: made.conversion.unmatched == nil, recorded: recorded,
                                              dngAsMade: dngAsMade))
                }
            } else {
                summary.failed += 1
                // This ARW made no DNG, so its tag step will not happen, and
                // its original has no step: it stays, and its note says why.
                total -= stepsOfAnARW - 1
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

        // The path of each DNG whose tag step ended with the DNG at the
        // factor (design 14.2, line 3).
        var atTheFactor = Set<String>()
        for dng in dngs {
            if cancel.isCancelled {
                summary.cancelled = true
                return summary
            }
            // Line 6 of design 14.2, for a DNG that this run made and whose
            // original can move. Directly before the tag step reads or
            // writes the DNG, it must be the file of the first record. The
            // answer changes nothing here: the DNG is tagged as any DNG in
            // the folder is. Only its ARW stays, at the fifth step.
            let own = originalOfDNG[dng.url.path]
            if let own {
                originals[own].dngHeldUntilItsTagStep = FileRecord.isTheSameFile(
                    recorded: originals[own].dngAsMade, now: fileRecord(dng.url.path))
            }
            let tagged = tagOne(dng, factor, &summary)
            if tagged != .notAtTheFactor { atTheFactor.insert(dng.url.path) }
            if let own {
                // The second record. After a write, exiftool's new file is
                // at the name, so the run reads its record, directly after
                // the tag step ended. A tag step that skipped wrote
                // nothing: the DNG must still be the file of the first
                // record, so that record is the second one too. A new read
                // here would take a file that arrived since the check
                // above as the run's own.
                originals[own].dngAsTagged = tagged == .skipped
                    ? originals[own].dngAsMade : fileRecord(dng.url.path)
            }
            completed += 1
            progress(RunProgress(completed: completed, total: total, name: dng.name))
        }

        // The fifth step (design 14.2): the originals. It comes after the
        // tag of the last DNG, so no ARW moves while a DNG still waits for
        // its tag. A cancel before an ARW leaves that ARW, and every one
        // after it, where it is, with no note: the result says "stopped".
        for original in originals {
            if cancel.isCancelled {
                summary.cancelled = true
                return summary
            }
            moveOne(original, factor, dngIsAtTheFactor: atTheFactor.contains(original.dng.path), &summary)
            completed += 1
            progress(RunProgress(completed: completed, total: total, name: original.arw.lastPathComponent))
        }
        return summary
    }

    /// The fifth step for one ARW (design 14.2): the ARW goes to the Trash
    /// when `OriginalDecision.decide` says so, and it stays with an
    /// `originalKept` note in every other case.
    ///
    /// The reads of lines 6, 5, 6 again and 4 happen here, directly before
    /// the move, in that order, and each one only when the lines before it
    /// hold. The second read of the ARW is the last thing before the move.
    ///
    /// Line 6 has two parts. The first was answered before the tag step of
    /// the DNG (`Original.dngHeldUntilItsTagStep`). The second is asked
    /// here, two times: the DNG must be the file that the tag step left,
    /// before the check of line 5, and again after its exiftool read. So a
    /// file that takes the name while line 5 works does not pass for the
    /// run's own.
    ///
    /// The move is `BackupHandling.trashFile`, once. When it throws, the ARW
    /// is where it was: it is not deleted, and no other way is tried.
    private func moveOne(_ original: Original, _ factor: SqueezeFactor, dngIsAtTheFactor: Bool,
                         _ summary: inout RunSummary) {
        let name = original.arw.lastPathComponent
        let decision = OriginalDecision.decide(
            hasFullMatch: original.hasFullMatch, dngIsAtTheFactor: dngIsAtTheFactor,
            dngIsThisRuns: {
                original.dngHeldUntilItsTagStep
                    && FileRecord.isTheSameFile(recorded: original.dngAsTagged, now: fileRecord(original.dng.path))
            },
            dng: {
                DNGCheck.check(original.dng.lastPathComponent, record: fileRecord(original.dng.path), arw: name,
                               factor: factor, tags: { try tag.readOriginalCheck(original.dng) })
            },
            dngIsStillThisRuns: {
                FileRecord.isTheSameFile(recorded: original.dngAsTagged, now: fileRecord(original.dng.path))
            },
            original: { OriginalState(recorded: original.recorded, now: fileRecord(original.arw.path)) })
        switch decision {
        case .keep(let reason):
            summary.notes.append(.originalKept(name, because: reason))
        case .move:
            do {
                try backups.trashFile(original.arw)
                summary.originalsInTrash += 1
            } catch {
                summary.notes.append(.originalKept(name, because: .trashRefused(detail: error.localizedDescription)))
            }
        }
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

    /// The tag step for one DNG (design 4.3, steps 2 to 4).
    ///
    /// - Returns: how the step ended. `.wrote` and `.skipped` both end
    ///   with the DNG at the factor (design 14.2, line 3). The fifth step
    ///   must tell them apart: only a write puts a new file at the name
    ///   (line 6).
    private func tagOne(_ dng: DNGFile, _ factor: SqueezeFactor, _ summary: inout RunSummary) -> Tagged {
        let (decision, hasBackup) = decide(dng, factor)
        summary.count(decision, for: dng.name, hasBackup: hasBackup)
        guard decision == .write else { return decision == .skip ? .skipped : .notAtTheFactor }

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
            return .notAtTheFactor
        }

        summary.set += 1
        do {
            try backups.trashBackup(for: dng.url)
        } catch {
            // The tag is set and read back. Only the backup stayed.
            summary.notes.append(.backupKept(dng.name, detail: error.localizedDescription))
        }
        return .wrote
    }

    /// How the tag step of one DNG ended.
    private enum Tagged {
        /// The tag was set and read back. exiftool wrote a new file.
        case wrote
        /// The DNG was at the factor already. Nothing was written.
        case skipped
        /// The DNG was blocked, or its write or check failed.
        case notAtTheFactor
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case TagError.toolFailed(let text): return text
        case let error as ConvertError: return error.text
        default: return error.localizedDescription
        }
    }
}
