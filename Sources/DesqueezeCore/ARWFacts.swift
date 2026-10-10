import Foundation

/// The four facts about one ARW that decide which converter takes it, and
/// what the match writes (design 13.4).
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
    /// True only when the ARW says that it has no lens-correction data, as
    /// every frame from an adapted lens says. False for every other value,
    /// and when the ARW says nothing.
    public let saysNoLensCorrection: Bool

    public init(model: String?, iso: Int?, daylightLevels: DaylightLevels?, saysNoLensCorrection: Bool) {
        self.model = model
        self.iso = iso
        self.daylightLevels = daylightLevels
        self.saysNoLensCorrection = saysNoLensCorrection
    }

    /// The facts of a file that exiftool cannot read: none. Such a file has
    /// no full match. That is not an error.
    public static let none = ARWFacts(model: nil, iso: nil, daylightLevels: nil, saysNoLensCorrection: false)
}

/// Reads the facts. `DesqueezeJob` depends on this protocol, so its tests
/// need no exiftool.
public protocol ARWFactsReading: Sendable {
    /// The facts of each file, by file name, from one request for the whole
    /// list. A file with no entry has no facts (`ARWFacts.none`). The read
    /// changes no file, and it never throws: a read that fails gives no
    /// facts, and no facts is "no full match" (design 13.4).
    func read(_ arws: [URL]) -> [String: ARWFacts]
}

/// The exiftool implementation.
///
/// Each tag is read with its group named, and with `-n`: the value as the
/// file holds it, not as exiftool words it. So the lens fact is the number
/// 255, which exiftool prints without `-n` as "No correction params
/// available". The number is the stable form: the words are exiftool's, and
/// a later exiftool can change them.
public struct ARWFactsReader: ARWFactsReading {
    /// The four tags, in the order of the columns that `parse` reads.
    static let tags = [
        "-IFD0:Model", "-ExifIFD:ISO", "-SR2SubIFD:WB_RGBLevelsDaylight", "-SubIFD:DistortionCorrection",
    ]
    /// `SubIFD:DistortionCorrection` when the ARW has no lens-correction
    /// data. A lens that reports itself gives 17 ("Auto fixed by lens").
    static let noCorrectionData = "255"
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
    public func read(_ arws: [URL]) -> [String: ARWFacts] {
        var facts: [String: ARWFacts] = [:]
        for start in stride(from: 0, to: arws.count, by: Self.batchSize) {
            let batch = arws[start..<min(start + Self.batchSize, arws.count)]
            guard let result = try? runner.run(
                exiftool, ["-m", "-n", "-T", "-filename"] + Self.tags + batch.map(\.path))
            else { continue }
            facts.merge(Self.parse(result.stdout)) { _, new in new }
        }
        return facts
    }

    /// Parses the tab-separated read: the file name, then the four tags.
    /// exiftool prints `-` for a tag that a file does not have, and a row of
    /// them for a file that it cannot read. A line that is no such row is
    /// dropped.
    static func parse(_ text: String) -> [String: ARWFacts] {
        var facts: [String: ARWFacts] = [:]
        for line in text.split(separator: "\n") {
            let cells = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cells.count == 1 + tags.count else { continue }
            facts[cells[0]] = ARWFacts(
                model: cells[1] == "-" || cells[1].isEmpty ? nil : cells[1],
                iso: wholeNumber(cells[2]).flatMap { $0 > 0 ? $0 : nil },
                daylightLevels: daylightLevels(cells[3]),
                saysNoLensCorrection: cells[4] == noCorrectionData)
        }
        return facts
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
