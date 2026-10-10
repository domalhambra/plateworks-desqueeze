import Foundation

/// What the disk says about one file: whether it is a regular file, its
/// size, its modification date, and its file number.
///
/// The run records this for an ARW before its conversion, and reads it again
/// directly before the ARW moves to the Trash (design 14.2, line 4). It
/// records it for the DNG of that ARW too, after the conversion and after
/// the tag step, and reads it again before the tag step and before the move
/// (line 6). The read is `lstat`, which does not follow a link: a link to
/// an ARW is a link, and never the ARW.
///
/// Two equal records do not prove equal bytes (design 14.7): a program that
/// writes a file in place, keeps its size, and puts the date back is not
/// seen.
public struct FileRecord: Equatable, Sendable {
    /// True only for a regular file. False for a folder and for a symbolic
    /// link, also a link that points at a regular file.
    public let isRegularFile: Bool
    /// The size in bytes.
    public let size: Int64
    /// The modification date: the whole seconds since 1970.
    public let modifiedSeconds: Int
    /// The modification date: the nanoseconds after `modifiedSeconds`.
    public let modifiedNanoseconds: Int
    /// The number of the file on its volume (the inode number). A file that
    /// replaces another under the same name has another number.
    public let fileNumber: UInt64

    public init(isRegularFile: Bool, size: Int64, modifiedSeconds: Int, modifiedNanoseconds: Int,
                fileNumber: UInt64) {
        self.isRegularFile = isRegularFile
        self.size = size
        self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
        self.fileNumber = fileNumber
    }

    /// The record of what has this name now. Nil when nothing has the name,
    /// or when the disk gave an error. It changes no file, and it does not
    /// follow a link.
    public static func read(atPath path: String) -> FileRecord? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return FileRecord(isRegularFile: info.st_mode & S_IFMT == S_IFREG, size: Int64(info.st_size),
                          modifiedSeconds: Int(info.st_mtimespec.tv_sec),
                          modifiedNanoseconds: Int(info.st_mtimespec.tv_nsec), fileNumber: UInt64(info.st_ino))
    }

    /// True when `now` is the file of `recorded`: both records are there,
    /// and all their facts are equal. Pure: it reads no file.
    ///
    /// A file with no record cannot be shown to be the same file. So nil on
    /// either side is false, also nil on both.
    public static func isTheSameFile(recorded: FileRecord?, now: FileRecord?) -> Bool {
        guard let recorded, let now else { return false }
        return recorded == now
    }
}

/// Whether an ARW is still the file that was converted (design 14.2, line
/// 4).
public enum OriginalState: Equatable, Sendable {
    /// A regular file with the size, the modification date and the file
    /// number that the run recorded before the conversion.
    case same
    /// One of the three differs, or the run has no record from before the
    /// conversion.
    case changed
    /// A folder or a link has the name now. It never goes to the Trash.
    case notARegularFile
    /// Nothing has the name now: the ARW is not in the folder. The run has
    /// nothing to move, and "it stays" would be false (design 14.3).
    case gone

    /// Compares the two records of one ARW. Pure: it reads no file.
    ///
    /// - Parameters:
    ///   - recorded: the record from before the conversion.
    ///   - now: the record from directly before the move.
    public init(recorded: FileRecord?, now: FileRecord?) {
        guard let now else {
            self = .gone
            return
        }
        guard now.isRegularFile else {
            self = .notARegularFile
            return
        }
        self = FileRecord.isTheSameFile(recorded: recorded, now: now) ? .same : .changed
    }
}

/// The two tags that the check of a DNG reads before its original moves
/// (design 14.2, line 5). `ScaleTagging.readOriginalCheck` gives them.
public struct OriginalCheckTags: Equatable, Sendable {
    /// `IFD0:OriginalRawFileName`, as exiftool prints it: a control
    /// character is a period. Nil when the DNG has no such tag.
    public let originalRawFileName: String?
    /// `SubIFD:DefaultScale`. Nil when the DNG gives no value.
    public let scale: Scale?

    public init(originalRawFileName: String?, scale: Scale?) {
        self.originalRawFileName = originalRawFileName
        self.scale = scale
    }
}

/// The check of a DNG, directly before its original moves to the Trash
/// (design 14.2, line 5): `<base>.dng` is a regular file with bytes, it
/// names the ARW in `OriginalRawFileName`, and its `DefaultScale` is the
/// chosen factor.
///
/// The check reads the structure and the two tags of the DNG. It does not
/// decode the picture (design 14.7).
public enum DNGCheck: Equatable, Sendable {
    case passed
    /// The check did not pass. `detail` has exiftool's words, or what
    /// differed.
    case failed(detail: String)

    /// The check of one DNG. It reads no file itself: its caller gives the
    /// record of the DNG, and the read of the two tags.
    ///
    /// The name is compared as exiftool prints it (design 13.9): a control
    /// character of the ARW's name is a period in both. The factor is
    /// compared as the tag step compares it (design 4.3, step 3).
    ///
    /// - Parameters:
    ///   - dng: the file name of the DNG, for the detail line.
    ///   - record: what the disk says about the DNG. Nil when nothing has
    ///     the name.
    ///   - arw: the file name of the ARW.
    ///   - factor: the chosen factor.
    ///   - tags: the one exiftool read. It is not called for a DNG that is
    ///     no regular file, or that has no bytes.
    public static func check(_ dng: String, record: FileRecord?, arw: String, factor: SqueezeFactor,
                             tags: () throws -> OriginalCheckTags) -> DNGCheck {
        guard let record, record.isRegularFile else { return .failed(detail: "\(dng) is not a regular file.") }
        guard record.size > 0 else { return .failed(detail: "\(dng) has no bytes.") }
        let read: OriginalCheckTags
        do {
            read = try tags()
        } catch {
            return .failed(detail: DesqueezeJob.describe(error))
        }
        let wanted = ExiftoolText.printed(arw)
        guard let name = read.originalRawFileName else {
            return .failed(detail: "\(dng) has no OriginalRawFileName.")
        }
        guard name == wanted else {
            return .failed(detail: "The OriginalRawFileName of \(dng) is \(name), not \(wanted).")
        }
        guard let scale = read.scale else { return .failed(detail: "\(dng) has no DefaultScale.") }
        guard factor.matches(scale) else {
            return .failed(detail: "The DefaultScale of \(dng) is \(scale.text), not \(factor.tagValue).")
        }
        return .passed
    }
}

/// What the run does with one original: the ARW of a conversion that this
/// run made (design 14.2).
///
/// The run and the dry run both ask `decide`, so one rule decides for both.
/// The dry run gives it the answers of a run in which every step passes. So
/// the two differ only where a step of the real run fails (design 14.7).
public enum OriginalDecision: Equatable, Sendable {
    /// Every line of design 14.2 holds. The ARW goes to the Trash.
    case move
    /// A line does not hold. The ARW stays, and a note says why.
    case keep(KeepReason)

    /// Why an original stays. Each case has one sentence of design 14.3.
    public enum KeepReason: Equatable, Sendable {
        /// Line 2: the conversion has a `convertedUnmatched` note.
        case noFullMatch
        /// Line 3: the tag step did not end with the DNG at the factor.
        case dngNotComplete
        /// Line 4: the ARW is not the file that was converted.
        case changed
        /// Line 4: a folder or a link has the name of the ARW.
        case notARegularFile
        /// Line 5: the check of the DNG did not pass.
        case dngNotChecked(detail: String)
        /// Line 6: `<base>.dng` is not the file that this run made.
        case dngChanged
        /// The ARW is not in the folder at the fifth step. The run did not
        /// move it, and the sentence does not say that it stays.
        case gone
        /// Every line held, and the Trash refused the ARW. `decide` never
        /// gives this one: the run knows it only after it tried the move.
        case trashRefused(detail: String)

        /// The plain sentence of design 14.3. The only place that makes
        /// these eight sentences.
        public var sentence: String {
            switch self {
            case .noFullMatch: return "The original stays, because its DNG has no full match."
            case .dngNotComplete: return "The original stays, because its DNG is not complete."
            case .changed: return "The original changed during the run, so it stays."
            case .notARegularFile: return "The original is not a regular file, so it stays."
            case .dngNotChecked: return "The original stays, because its DNG could not be checked."
            case .dngChanged: return "The original stays, because its DNG changed during the run."
            case .gone:
                return "The original was not in the folder at the end of the run. The app did not move it."
            case .trashRefused: return "The original could not go to the Trash, so it stays."
            }
        }

        /// The detail line: exiftool's words or what differed for the check
        /// of the DNG, and the system's words for a refusal of the Trash.
        /// Nil for every other reason.
        public var detail: String? {
            switch self {
            case .dngNotChecked(let detail), .trashRefused(let detail): return detail
            case .noFullMatch, .dngNotComplete, .changed, .notARegularFile, .dngChanged, .gone: return nil
            }
        }
    }

    /// The rule of design 14.2, for one ARW that this run converted (line
    /// 1). It reads no file: its caller gives what the run knows.
    ///
    /// The lines are asked in this order: 2, 3, 6, 5, 6 again, 4. The first
    /// one that does not hold decides, and the ones after it are not asked.
    /// So an ARW that stays for line 2 or 3 costs no read at the fifth
    /// step. Line 6 stands before line 5: the tags of a DNG say nothing
    /// until the DNG is known to be this run's file. Line 6 is asked again
    /// after line 5: the check of line 5 takes time, and another file can
    /// take the name before exiftool opens it. Line 4 is last, so nothing
    /// stands between the second read of the ARW and its move.
    ///
    /// The dry run gives `true`, `.passed`, `true` and `.same`: it plans a
    /// run in which every step passes.
    ///
    /// - Parameters:
    ///   - hasFullMatch: line 2. False when the conversion has a
    ///     `convertedUnmatched` note.
    ///   - dngIsAtTheFactor: line 3. True when the tag step set the tag and
    ///     read it back, or the DNG was at the factor already.
    ///   - dngIsThisRuns: line 6. True when `<base>.dng` is the file that
    ///     this run made: its record from after the conversion held before
    ///     the tag step, and its record from after the tag step holds now.
    ///   - dng: line 5, the check of the DNG.
    ///   - dngIsStillThisRuns: line 6 again, after the check of line 5 has
    ///     passed. True when `<base>.dng` is still the file that the tag
    ///     step left: the file that exiftool read for line 5 is this run's.
    ///   - original: line 4, the ARW now against its record from before the
    ///     conversion.
    public static func decide(hasFullMatch: Bool, dngIsAtTheFactor: Bool, dngIsThisRuns: () -> Bool,
                              dng: () -> DNGCheck, dngIsStillThisRuns: () -> Bool,
                              original: () -> OriginalState) -> OriginalDecision {
        guard hasFullMatch else { return .keep(.noFullMatch) }
        guard dngIsAtTheFactor else { return .keep(.dngNotComplete) }
        guard dngIsThisRuns() else { return .keep(.dngChanged) }
        if case .failed(let detail) = dng() { return .keep(.dngNotChecked(detail: detail)) }
        guard dngIsStillThisRuns() else { return .keep(.dngChanged) }
        switch original() {
        case .same: return .move
        case .changed: return .keep(.changed)
        case .notARegularFile: return .keep(.notARegularFile)
        case .gone: return .keep(.gone)
        }
    }
}
