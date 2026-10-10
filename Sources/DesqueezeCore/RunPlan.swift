import Foundation

/// What a run does with one DNG.
///
/// The run and the dry run both ask `decide`, and both count the answer with
/// `RunSummary.count`. So the two cannot disagree.
public enum TagDecision: String, Equatable, Sendable, CaseIterable {
    /// The scale is known and equals the factor. Nothing is written.
    case skip
    /// An older backup is beside the file. The run holds the file back.
    case blocked
    /// The run writes the tag.
    case write

    /// The rule of design 4.3, step 2. Pure: it reads no file.
    ///
    /// The order matters. A file at the factor is skipped also when a backup
    /// is beside it. An unknown scale matches no factor, so such a file is
    /// never skipped.
    public static func decide(scale: Scale?, hasBackup: Bool, factor: SqueezeFactor) -> TagDecision {
        if factor.matches(scale) { return .skip }
        // exiftool never replaces an existing `_original`. A write over one
        // would leave a backup of the wrong state, and this app must not
        // discard a backup that it did not make.
        if hasBackup { return .blocked }
        return .write
    }
}

extension RunSummary {
    /// Counts a file that the run does not write, and adds its note. A write
    /// is counted by its caller: as `set` or `failed` by the run, on the
    /// result, and as `set` by the dry run.
    mutating func count(_ decision: TagDecision, for dng: String, hasBackup: Bool) {
        switch decision {
        case .skip:
            skipped += 1
            // A run that died after its write leaves this. The backup is the
            // file as it was before, so the user must know that it is there.
            if hasBackup { notes.append(.leftoverBackup(dng)) }
        case .blocked:
            blocked += 1
            notes.append(.blockedByBackup(dng))
        case .write:
            break
        }
    }
}

/// What a run would do, file by file. Made by `DesqueezeJob.plan`.
public struct RunPlan: Equatable, Sendable {
    public enum Action: String, Codable, Sendable, CaseIterable {
        case convert, write, skip, blocked
        /// The run would move this ARW to the Trash (design 14.3). The name
        /// of the step is the ARW's. Only a plan that was asked to move the
        /// originals has such a step.
        case trashOriginal
    }

    public struct Step: Equatable, Sendable, Codable {
        public let name: String
        public let action: Action
        /// The converter that gets the ARW first (design 13.6). Only a
        /// `convert` step has it. In the JSON, every other step has no
        /// `converter` key.
        public let converter: ConverterKind?

        public init(name: String, action: Action, converter: ConverterKind? = nil) {
            self.name = name
            self.action = action
            self.converter = converter
        }
    }

    /// In run order: each conversion, then each DNG, the new ones last,
    /// then each original that the run would move to the Trash.
    public var steps: [Step]
    /// The counts and the notes that a real run gives when every step
    /// passes, each conversion with the first converter of its list.
    public var summary: RunSummary

    public init(steps: [Step], summary: RunSummary) {
        self.steps = steps
        self.summary = summary
    }
}

extension RunPlan.Action {
    init(_ decision: TagDecision) {
        switch decision {
        case .skip: self = .skip
        case .blocked: self = .blocked
        case .write: self = .write
        }
    }
}
