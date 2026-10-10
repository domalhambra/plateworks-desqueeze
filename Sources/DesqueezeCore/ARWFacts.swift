import Foundation

/// The five facts about one ARW that decide which converter takes it, and
/// what the match writes (design 13.4).
///
/// The last two are the numbers that the file holds, not a yes or a no: a
/// note can then say "the ARW says another kind" or "the ARW does not say".
public struct ARWFacts: Equatable, Sendable {
    /// `WB_RGBLevelsDaylight`: what the camera says daylight is, for the lens
    /// on it.
    public struct DaylightLevels: Equatable, Sendable {
        public let red: Int
        public let green: Int
        public let blue: Int

        public init(red: Int, green: Int, blue: Int) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// The camera model, for example `ILCE-7SM3`. Nil when the ARW gives none.
    public let model: String?
    /// Nil when the ARW gives no ISO, or one that is no whole number above 0.
    public let iso: Int?
    /// Nil when the ARW gives no three whole numbers, each 0 or more.
    public let daylightLevels: DaylightLevels?
    /// `SubIFD:DistortionCorrection`, as the file holds it. 255 says that
    /// the ARW has no lens-correction data (`noCorrectionData`). A lens that
    /// reports itself gives 17. Nil when the ARW has no such tag, or a value
    /// that is no whole number.
    public let distortionCorrection: Int?
    /// `SubIFD:SonyRawFileType`, as the file holds it: how the raw data is
    /// stored. 2 is Sony compressed raw (`compressedRaw`), the only kind
    /// that was measured. Nil when the ARW has no such tag, or a value that
    /// is no whole number.
    public let rawFileType: Int?

    /// `distortionCorrection` when the ARW has no lens-correction data.
    /// exiftool prints it without `-n` as "No correction params available".
    public static let noCorrectionData = 255
    /// `rawFileType` for Sony compressed raw. exiftool prints it without
    /// `-n` as "Sony Compressed RAW". The camera's other setting,
    /// uncompressed raw, gives another number.
    public static let compressedRaw = 2

    /// True only when the ARW says that it has no lens-correction data, as
    /// every frame from an adapted lens says. False for every other value,
    /// and when the ARW says nothing.
    public var saysNoLensCorrection: Bool { distortionCorrection == Self.noCorrectionData }

    /// True only when the ARW says that it is compressed raw. False for
    /// every other value, and when the ARW says nothing.
    public var isCompressedRaw: Bool { rawFileType == Self.compressedRaw }

    public init(model: String?, iso: Int?, daylightLevels: DaylightLevels?, distortionCorrection: Int?,
                rawFileType: Int?) {
        self.model = model
        self.iso = iso
        self.daylightLevels = daylightLevels
        self.distortionCorrection = distortionCorrection
        self.rawFileType = rawFileType
    }

    /// The facts of a file that exiftool cannot read: none. Such a file has
    /// no full match. That is not an error.
    public static let none = ARWFacts(model: nil, iso: nil, daylightLevels: nil, distortionCorrection: nil,
                                      rawFileType: nil)
}

/// Reads the facts. `DesqueezeJob` depends on this protocol, so its tests
/// need no exiftool.
public protocol ARWFactsReading: Sendable {
    /// The facts of each file of the list, by its file name, from one
    /// request for the whole list. A file with no entry has no facts
    /// (`ARWFacts.none`). The read changes no file, and it never throws: a
    /// read that fails gives no facts, and no facts is "no full match"
    /// (design 13.4).
    func read(_ arws: [URL]) -> [String: ARWFacts]
}

/// How exiftool prints text in a row of its output.
enum ExiftoolText {
    /// `text` as exiftool prints it: each control character, U+0001 to
    /// U+001F and U+007F, is a period. So a file name with a tab or a line
    /// end in it stays one cell of one row.
    ///
    /// Two names can then print as one: `a<tab>b.ARW` and `a.b.ARW` are
    /// both `a.b.ARW`. A caller that finds a file by its printed name must
    /// know that (`ARWFactsReader.read`).
    ///
    /// Checked with exiftool 13.55 on 2026-10-09, for a tab, a line end,
    /// U+0001 and U+007F, in a file name and in `OriginalRawFileName`.
    static func printed(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let isControl = (0x01...0x1F).contains(scalar.value) || scalar.value == 0x7F
            scalars.append(isControl ? "." : scalar)
        }
        return String(scalars)
    }

    /// The row of each file, found by the name that exiftool printed. A file
    /// takes a row only when exactly one row, and exactly one file of
    /// `names`, have its printed name. When two rows or two files share a
    /// printed name, no one can say which row is whose: those files get no
    /// row. The facts of the ARW files (`ARWFactsReader.read`) and the scale
    /// of the DNG files (`FolderScanner`) are both read by this rule.
    ///
    /// - Parameters:
    ///   - names: the file names of the files, as the disk has them.
    ///   - rows: the rows by the file name that exiftool printed.
    /// - Returns: the row of each file that has one, by its file name.
    static func pair<Row>(files names: [String], rows: [String: [Row]]) -> [String: Row] {
        var files: [String: [String]] = [:]
        for name in names { files[printed(name), default: []].append(name) }
        var paired: [String: Row] = [:]
        for (printedName, same) in files where same.count == 1 {
            if let found = rows[printedName], found.count == 1 { paired[same[0]] = found[0] }
        }
        return paired
    }
}

/// The exiftool implementation.
///
/// Each tag is read with its group named, and with `-n`: the value as the
/// file holds it, not as exiftool words it. So the lens fact is the number
/// 255, which exiftool prints without `-n` as "No correction params
/// available", and the raw kind is the number 2, which it prints as "Sony
/// Compressed RAW". The number is the stable form: the words are exiftool's,
/// and a later exiftool can change them.
public struct ARWFactsReader: ARWFactsReading {
    /// The five tags, in the order of the columns that `rows` reads.
    static let tags = [
        "-IFD0:Model", "-ExifIFD:ISO", "-SR2SubIFD:WB_RGBLevelsDaylight", "-SubIFD:DistortionCorrection",
        "-SubIFD:SonyRawFileType",
    ]
    /// The most files on one exiftool command line. The list is the command
    /// line, and the system refuses a command line above about one megabyte.
    /// 200 paths of the longest length that a path can have (1024 bytes)
    /// stay far below that.
    static let batchSize = 200

    private let exiftool: URL
    private let runner: ProcessRunner

    public init(exiftool: URL, runner: ProcessRunner = SystemProcessRunner()) {
        self.exiftool = exiftool
        self.runner = runner
    }

    /// One exiftool call for each `batchSize` files of the list, in the
    /// order of the list. An empty list starts nothing.
    ///
    /// exiftool exits 1 when one file is unreadable, and the other rows are
    /// still valid, so the exit code is not read. A call that fails gives
    /// its files no facts. The other calls are still made.
    ///
    /// **A row is found by the name that exiftool prints,** and exiftool
    /// prints a control character as a period (`ExiftoolText.printed`). A
    /// file gets facts only when exactly one row has its printed name, and
    /// no other file of the list prints as that name. When two rows, or two
    /// files, share a printed name, no one can say which row is whose: those
    /// files get no facts, which is "no full match". The same holds for two
    /// files of the list that have one name in two folders.
    public func read(_ arws: [URL]) -> [String: ARWFacts] {
        var rows: [String: [ARWFacts]] = [:]
        for start in stride(from: 0, to: arws.count, by: Self.batchSize) {
            let batch = arws[start..<min(start + Self.batchSize, arws.count)]
            guard let result = try? runner.run(
                exiftool, ["-m", "-n", "-T", "-filename"] + Self.tags + batch.map(\.path))
            else { continue }
            for row in Self.rows(result.stdout) { rows[row.name, default: []].append(row.facts) }
        }
        return ExiftoolText.pair(files: arws.map(\.lastPathComponent), rows: rows)
    }

    /// Parses the tab-separated read: the file name, then the five tags, one
    /// row for each file, in the order of the output. exiftool prints `-`
    /// for a tag that a file does not have, and a row of them for a file
    /// that it cannot read. A line that is no such row is dropped.
    static func rows(_ text: String) -> [(name: String, facts: ARWFacts)] {
        var rows: [(name: String, facts: ARWFacts)] = []
        for line in text.split(separator: "\n") {
            let cells = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cells.count == 1 + tags.count else { continue }
            rows.append((cells[0], ARWFacts(
                model: cells[1] == "-" || cells[1].isEmpty ? nil : cells[1],
                iso: wholeNumber(cells[2]).flatMap { $0 > 0 ? $0 : nil },
                daylightLevels: daylightLevels(cells[3]),
                distortionCorrection: wholeNumber(cells[4]),
                rawFileType: wholeNumber(cells[5]))))
        }
        return rows
    }

    private static func daylightLevels(_ text: String) -> ARWFacts.DaylightLevels? {
        let numbers = text.split(separator: " ", omittingEmptySubsequences: false).map { wholeNumber(String($0)) }
        guard numbers.count == 3, let red = numbers[0], let green = numbers[1], let blue = numbers[2] else {
            return nil
        }
        return ARWFacts.DaylightLevels(red: red, green: green, blue: blue)
    }

    /// Digits only. `Int` alone also takes a sign.
    private static func wholeNumber(_ text: String) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}
