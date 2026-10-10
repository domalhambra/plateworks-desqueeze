import Foundation
@testable import DesqueezeCore

/// A `ProcessRunner` that records each call and answers from a closure.
final class FakeRunner: ProcessRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    var calls: [Call] = []
    var handler: (Call) -> ProcessResult = { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "") }
    /// Thrown after the handler ran, as when a signal ends a program that
    /// has already written part of its output.
    var failure: Error?

    func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        let call = Call(executable: executable.path, arguments: arguments)
        calls.append(call)
        let result = handler(call)
        if let failure { throw failure }
        return result
    }
}

/// What a note says after it names a hidden file (design 13.3). The tests
/// hold the text here, not through the core's constant, so a change of the
/// constant fails them.
let hiddenFileSentence = "It is a hidden file: in Finder, press Command-Shift-Period to see it."

/// Makes an empty temporary folder inside a new `desqueeze-tests-<id>` folder.
/// The test removes it in `tearDown` with `removeTemporaryFolder`.
func makeTemporaryFolder(named name: String = "Shoot 1") throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("desqueeze-tests-\(UUID().uuidString)")
    let folder = base.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Removes the `desqueeze-tests-<id>` folder that holds `folder`. Does nothing
/// for any other URL, so a wrong argument cannot remove a real folder.
func removeTemporaryFolder(_ folder: URL) {
    let base = folder.deletingLastPathComponent()
    guard base.lastPathComponent.hasPrefix("desqueeze-tests-") else { return }
    try? FileManager.default.removeItem(at: base)
}

/// An error with a fixed description, so a test can assert the exact text.
struct NamedError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

/// An ordered record of what the fakes were asked to do.
final class CallLog: @unchecked Sendable {
    var entries: [String] = []
}

final class FakeBackups: BackupHandling, @unchecked Sendable {
    let log: CallLog
    var existing: Set<String> = []
    var trashError: Error?
    var restoreError: Error?
    /// Set when `trashFile` must fail, as when the Trash refuses.
    var trashFileError: Error?
    /// Each file that `trashFile` got, in order, also the ones it refused.
    var filesGiven: [URL] = []
    var onTrashFile: (() -> Void)?

    init(log: CallLog) { self.log = log }

    func backupExists(for dng: URL) -> Bool { existing.contains(dng.lastPathComponent) }

    func trashBackup(for dng: URL) throws {
        log.entries.append("trash \(dng.lastPathComponent)")
        if let trashError { throw trashError }
        existing.remove(dng.lastPathComponent)
    }

    func trashFile(_ file: URL) throws {
        log.entries.append("trashFile \(file.lastPathComponent)")
        filesGiven.append(file)
        onTrashFile?()
        if let trashFileError { throw trashFileError }
    }

    func restoreBackup(for dng: URL) throws {
        log.entries.append("restore \(dng.lastPathComponent)")
        if let restoreError { throw restoreError }
        existing.remove(dng.lastPathComponent)
    }
}

/// Acts like exiftool: a good write leaves a backup, a bad write leaves none.
final class FakeTag: ScaleTagging, @unchecked Sendable {
    let log: CallLog
    let backups: FakeBackups
    var rows: [TagRow] = []
    var readFolderError: Error?
    var failWrites: Set<String> = []
    /// File names whose read-back does not match what was written.
    var wrongReadBack: Set<String> = []
    /// File names whose read-back throws, as when exiftool cannot start.
    var failReads: Set<String> = []
    /// File names whose read-back finds no tag.
    var noReadBack: Set<String> = []
    var onWrite: (() -> Void)?
    /// What `readOriginalCheck` gives, by DNG name. A name with no entry
    /// gets the tags of a DNG that the run made and tagged: the name of an
    /// ARW with its base name, and the scale that was written, or no
    /// stretch when nothing was.
    var originalCheck: [String: OriginalCheckTags] = [:]
    /// DNG names for which `readOriginalCheck` throws, as when exiftool
    /// prints no row.
    var failOriginalChecks: Set<String> = []
    private var written: [String: SqueezeFactor] = [:]

    init(log: CallLog, backups: FakeBackups) {
        self.log = log
        self.backups = backups
    }

    func readFolder(_ folder: URL) throws -> [TagRow] {
        log.entries.append("readFolder")
        if let readFolderError { throw readFolderError }
        return rows
    }

    func write(_ factor: SqueezeFactor, to file: URL) throws {
        let name = file.lastPathComponent
        log.entries.append("write \(factor.tagValue) \(name)")
        onWrite?()
        if failWrites.contains(name) { throw TagError.toolFailed("Error: write failed") }
        written[name] = factor
        backups.existing.insert(name)
    }

    func read(_ file: URL) throws -> Scale? {
        let name = file.lastPathComponent
        log.entries.append("read \(name)")
        if failReads.contains(name) { throw TagError.toolFailed("Error: read failed") }
        if noReadBack.contains(name) { return nil }
        if wrongReadBack.contains(name) { return .noStretch }
        return written[name].map { Scale(horizontal: $0.value, vertical: 1) }
    }

    func readOriginalCheck(_ dng: URL) throws -> OriginalCheckTags {
        let name = dng.lastPathComponent
        log.entries.append("check \(name)")
        if failOriginalChecks.contains(name) { throw TagError.toolFailed("Error: File not found") }
        if let tags = originalCheck[name] { return tags }
        return OriginalCheckTags(
            originalRawFileName: dng.deletingPathExtension().lastPathComponent + ".ARW",
            scale: written[name].map { Scale(horizontal: $0.value, vertical: 1) } ?? .noStretch)
    }
}

/// What the disk says about each file, for the fifth step of a run (design
/// 14.2). It reads no disk.
final class FakeFiles: @unchecked Sendable {
    /// A regular file with bytes. Two calls give equal records.
    static func file(size: Int64 = 100, modified: Int = 1_000, nanoseconds: Int = 0,
                     number: UInt64 = 7) -> FileRecord {
        FileRecord(isRegularFile: true, size: size, modifiedSeconds: modified, modifiedNanoseconds: nanoseconds,
                   fileNumber: number)
    }

    /// A folder, or a link: anything that is no regular file.
    static let notAFile = FileRecord(isRegularFile: false, size: 64, modifiedSeconds: 1_000,
                                     modifiedNanoseconds: 0, fileNumber: 8)

    let log: CallLog
    /// The answers for one file name, in the order of the reads. The last
    /// one is given again for each later read. A name with no entry is a
    /// regular file with bytes that never changes. `nil` in the list says
    /// that nothing has the name.
    var records: [String: [FileRecord?]] = [:]
    private var reads: [String: Int] = [:]

    init(log: CallLog) { self.log = log }

    func record(atPath path: String) -> FileRecord? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        log.entries.append("record \(name)")
        guard let answers = records[name], !answers.isEmpty else { return Self.file() }
        let index = min(reads[name, default: 0], answers.count - 1)
        reads[name, default: 0] += 1
        return answers[index]
    }
}

/// What a runner that stands for Adobe DNG Converter must know about the
/// real program.
enum FakeAdobe {
    /// Where Adobe DNG Converter writes for these arguments: in the folder
    /// that follows `-d`, under the name that follows `-o`. With no `-o` the
    /// name is `<base>.dng`, and with no `-d` the folder is the ARW's. That
    /// is what the real converter does (18.7, tested 2026-10-09), so a
    /// converter that leaves `-o` out writes `<base>.dng` here too.
    static func output(of arguments: [String]) -> String {
        let arw = URL(fileURLWithPath: arguments.last ?? "")
        let folder = arguments.firstIndex(of: "-d").map { arguments[$0 + 1] } ?? arw.deletingLastPathComponent().path
        let name = arguments.firstIndex(of: "-o").map { arguments[$0 + 1] }
            ?? arw.deletingPathExtension().lastPathComponent + ".dng"
        return folder + "/" + name
    }
}

/// Either converter. `label` is the first word of its log entry: the fake
/// for Adobe DNG Converter says "convert", and the fake for dnglab "dnglab".
final class FakeConverter: RawConverter, @unchecked Sendable {
    let log: CallLog
    let label: String
    /// The converter, as its failure sentence names it.
    let name: String
    /// True for the dnglab fake: its result carries the rule that kept the
    /// DNG from a full match, as `DnglabConverter` gives it.
    let reportsTheMatch: Bool
    var fail: Set<String> = []
    /// ARW names whose failed conversion also left a partial output: the
    /// work file of the ARW, from either fake.
    var failWithPartial: Set<String> = []
    /// What a failed conversion names as its partial output, in place of
    /// the work file of the ARW. A correct converter never does this.
    var reportedPartial: URL?
    /// ARW names for which the rename of the work file finds the name
    /// `<base>.dng` taken, as each real converter reports it.
    var nameTakenAtRename: Set<String> = []
    /// ARW names that the converter refuses before it starts.
    var refuse: Set<String> = []
    /// The facts that each call got, by ARW name.
    var facts: [String: ARWFacts] = [:]
    var onConvert: (() -> Void)?

    init(log: CallLog, label: String = "convert", name: String = "Adobe DNG Converter",
         reportsTheMatch: Bool = false) {
        self.log = log
        self.label = label
        self.name = name
        self.reportsTheMatch = reportsTheMatch
    }

    func convert(_ arw: URL, facts: ARWFacts) throws -> Conversion {
        log.entries.append("\(label) \(arw.lastPathComponent)")
        self.facts[arw.lastPathComponent] = facts
        onConvert?()
        if refuse.contains(arw.lastPathComponent) {
            throw ConvertError.failed("A DNG with this name exists already. Not converted.")
        }
        if fail.contains(arw.lastPathComponent) { throw ConvertError.failed("made no DNG") }
        // Each converter writes the hidden work file of the ARW, and never
        // `<base>.dng` (design 13.3).
        let ownFile = ConverterOutput.workURL(for: arw)
        if nameTakenAtRename.contains(arw.lastPathComponent) {
            throw ConvertError.failedForAll("A DNG with this name exists already. Not converted.",
                                            partial: reportedPartial ?? ownFile)
        }
        if failWithPartial.contains(arw.lastPathComponent) {
            throw ConvertError.failed("\(name) returned 1.", partial: reportedPartial ?? ownFile)
        }
        return Conversion(dng: ConverterOutput.url(for: arw),
                          unmatched: reportsTheMatch ? AdobeMatch.match(facts).failed : nil)
    }
}

/// The three programs on real files, with no program started: a runner that
/// acts like dnglab, like Adobe DNG Converter, and like exiftool for the
/// facts read and for the match. A test gives it to the public
/// `RawConverters(exiftool:dnglab:adobe:runner:backups:)`, so the converters
/// are the real ones, wired as the app wires them.
final class ScriptedTools: @unchecked Sendable {
    static let exiftool = URL(fileURLWithPath: "/nonexistent/exiftool")
    static let dnglab = URL(fileURLWithPath: "/nonexistent/dnglab")
    static let adobe = URL(fileURLWithPath: "/nonexistent/Adobe DNG Converter")
    /// What the scripted dnglab writes into its output.
    static let dnglabBytes = Data("dnglab's DNG".utf8)
    static let adobeBytes = Data("Adobe's DNG".utf8)

    let runner = FakeRunner()
    /// The row of the facts read for every ARW, after the file name.
    var factsRow = "ILCE-7SM3\t800\t2597 1024 1556\t255\t2"
    private var written: [String] = []

    init() {
        runner.handler = { [unowned self] call in
            func result(_ code: Int32 = 0, _ out: String = "", _ err: String = "") -> ProcessResult {
                ProcessResult(exitCode: code, stdout: out, stderr: err)
            }
            switch call.executable {
            case Self.dnglab.path:
                // dnglab 0.8.0 returns 6 for an output that exists, and does
                // not touch it.
                let output = call.arguments.last!
                guard !ConverterOutput.exists(atPath: output) else {
                    return result(6, "", "Error: Already exists: \(output)\n")
                }
                FileManager.default.createFile(atPath: output, contents: Self.dnglabBytes)
                return result()
            case Self.adobe.path:
                // Adobe DNG Converter 18.7 does not write over a file: with
                // the name taken it writes `<name>_1.dng`, leaves the first
                // file as it was, and returns 0 (tested 2026-10-09).
                var output = FakeAdobe.output(of: call.arguments)
                if ConverterOutput.exists(atPath: output) {
                    output = String(output.dropLast(".dng".count)) + "_1.dng"
                }
                FileManager.default.createFile(atPath: output, contents: Self.adobeBytes)
                return result()
            default:
                if call.arguments.contains("-IFD0:Model") {
                    let rows = call.arguments.filter { $0.hasPrefix("/") }
                        .map { "\(URL(fileURLWithPath: $0).lastPathComponent)\t\(self.factsRow)\n" }
                    return result(0, rows.joined())
                }
                if call.arguments.contains("-overwrite_original") {
                    self.written = call.arguments.filter { $0.contains("=") }
                        .map { String($0[$0.index(after: $0.firstIndex(of: "=")!)...]) }
                    return result(0, "    1 image files updated\n")
                }
                return result(0, self.written.joined(separator: "\t") + "\n")
            }
        }
    }

    /// The calls to one program, in order.
    func calls(to program: URL) -> [FakeRunner.Call] { runner.calls.filter { $0.executable == program.path } }

    /// The real converters on this runner. `backups` gets the leftover work
    /// file, as the job's backups get it in the app.
    ///
    /// - Parameter verbose: gets the lines that `--verbose` shows beside the
    ///   commands.
    func converters(backups: BackupHandling, withDnglab: Bool = true, withAdobe: Bool = true,
                    verbose: @escaping @Sendable (String) -> Void = { _ in }) -> RawConverters {
        RawConverters(exiftool: Self.exiftool, dnglab: withDnglab ? Self.dnglab : nil,
                      adobe: withAdobe ? Self.adobe : nil, runner: runner, backups: backups, verbose: verbose)
    }
}

/// Gives the facts that a test sets, and records each read.
final class FakeFacts: ARWFactsReading, @unchecked Sendable {
    let log: CallLog
    /// By ARW name. A name with no entry has no facts.
    var facts: [String: ARWFacts] = [:]

    init(log: CallLog) { self.log = log }

    func read(_ arws: [URL]) -> [String: ARWFacts] {
        log.entries.append("facts " + arws.map(\.lastPathComponent).joined(separator: " "))
        return facts
    }
}

extension ARWFacts {
    /// The facts of a frame of compressed raw, as every measured frame is,
    /// with the lens fact as a yes or a no.
    ///
    /// - Parameter saysNoLensCorrection: true gives 255, "no correction
    ///   data". False gives 17, the value of a lens that reports itself.
    init(model: String?, iso: Int?, daylightLevels: DaylightLevels?, saysNoLensCorrection: Bool,
         rawFileType: Int? = ARWFacts.compressedRaw) {
        self.init(model: model, iso: iso, daylightLevels: daylightLevels,
                  distortionCorrection: saysNoLensCorrection ? ARWFacts.noCorrectionData : 17,
                  rawFileType: rawFileType)
    }

    /// A frame from an adapted lens at ISO 800, as every anamorphic frame
    /// is: a full match.
    static let adapted = ARWFacts(model: "ILCE-7SM3", iso: 800,
                                  daylightLevels: DaylightLevels(red: 2597, green: 1024, blue: 1556),
                                  saysNoLensCorrection: true)
    /// A frame from a lens that reports itself: only rule 4 fails.
    static let lens = ARWFacts(model: "ILCE-7SM3", iso: 80,
                               daylightLevels: DaylightLevels(red: 2496, green: 1024, blue: 1617),
                               saysNoLensCorrection: false)
    /// An adapted lens at an ISO with no row in the table: rule 2 fails.
    static let iso1250 = ARWFacts(model: "ILCE-7SM3", iso: 1250,
                                  daylightLevels: DaylightLevels(red: 2597, green: 1024, blue: 1556),
                                  saysNoLensCorrection: true)
    /// An adapted lens at ISO 800, as uncompressed raw: only rule 5 fails.
    /// `SonyRawFileType` 0 is "Sony Uncompressed 14-bit RAW".
    static let uncompressed = ARWFacts(model: "ILCE-7SM3", iso: 800,
                                       daylightLevels: DaylightLevels(red: 2597, green: 1024, blue: 1556),
                                       saysNoLensCorrection: true, rawFileType: 0)
}
