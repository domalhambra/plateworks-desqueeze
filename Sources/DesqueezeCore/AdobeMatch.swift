import Foundation

/// The tags that make a dnglab DNG render as Adobe DNG Converter's does, and
/// the rule for when they can (design 13.2 to 13.4). Pure: no file access.
///
/// The numbers are what Adobe DNG Converter 18.7 writes. They are a copy of
/// the data file `docs/superpowers/specs/2026-10-09-ilce-7sm3-adobe-values.json`,
/// and a unit test fails when the copy and the file differ.
public enum AdobeMatch {
    /// The five rules of a full match, with the numbers of design 13.4.
    public enum Rule: Int, Equatable, Sendable, CaseIterable {
        /// 1. The model has a row in the table.
        case model = 1
        /// 2. The ISO has a row.
        case iso
        /// 3. The daylight levels are there, with the green of the table.
        case daylightLevels
        /// 4. The ARW says that it has no lens-correction data.
        case noLensCorrection
        /// 5. The ARW is compressed raw, the only kind that was measured.
        case compressedRaw
    }

    /// One tag to write.
    public struct Tag: Equatable, Sendable {
        /// The group and the name, as exiftool takes them: `SubIFD:WhiteLevel`.
        public let name: String
        /// The value as text. The numbers of a list have one space between them.
        public let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    /// What the table gives for one ARW.
    public struct Match: Equatable, Sendable {
        /// The tags to write, in the order of design 13.2. All of them when
        /// rules 1, 2, 3 and 5 hold, also when rule 4 does not: "matched as
        /// far as the table goes". None when rule 1, 2, 3 or 5 failed: the
        /// levels of the DNG are then dnglab's own.
        public let tags: [Tag]
        /// The rule that failed. Nil for a full match. When more than one
        /// failed, it is the first of 1, 2, 3 and 5: each of them leaves the
        /// DNG with no tag of the table. Rule 4 is named only when it alone
        /// failed.
        public let failed: Rule?

        /// True when all five rules hold.
        public var isFull: Bool { failed == nil }

        public init(tags: [Tag], failed: Rule?) {
            self.tags = tags
            self.failed = failed
        }
    }

    /// The tags for an ARW with these facts, or the reason it has no full
    /// match.
    public static func match(_ facts: ARWFacts) -> Match {
        guard let camera = cameras.first(where: { $0.model == facts.model }) else {
            return Match(tags: [], failed: .model)
        }
        guard let row = facts.iso.flatMap({ camera.byISO[$0] }) else {
            return Match(tags: [], failed: .iso)
        }
        // The rule divides by red and by blue, so each must be above 0.
        guard let levels = facts.daylightLevels, levels.green == camera.daylightReference.green,
              levels.red > 0, levels.blue > 0 else {
            return Match(tags: [], failed: .daylightLevels)
        }
        // The values of the table are those of compressed raw. Another
        // kind, or no word about the kind, gets none of them.
        guard facts.isCompressedRaw else {
            return Match(tags: [], failed: .compressedRaw)
        }
        let calibration = calibration(red: levels.red, blue: levels.blue, reference: camera.daylightReference)
        let tags = [
            Tag(name: "SubIFD:WhiteLevel", value: camera.whiteLevel),
            Tag(name: "IFD0:BaselineExposure", value: row.baselineExposure),
            Tag(name: "IFD0:CameraCalibration1", value: calibration),
            Tag(name: "IFD0:CameraCalibration2", value: calibration),
            Tag(name: "IFD0:NoiseProfile", value: row.noiseProfile.joined(separator: " ")),
            Tag(name: "IFD0:BaselineNoise", value: camera.baselineNoise),
            Tag(name: "IFD0:BaselineSharpness", value: camera.baselineSharpness),
            Tag(name: "SubIFD:AntiAliasStrength", value: camera.antiAliasStrength),
            Tag(name: "SubIFD:BayerGreenSplit", value: camera.bayerGreenSplit),
        ]
        return Match(tags: tags, failed: facts.saysNoLensCorrection ? nil : .noLensCorrection)
    }

    // MARK: The camera calibration

    /// The diagonal `r 0 0 0 1 0 0 0 b` (design 13.2): r is the reference red
    /// over the red of the ARW's daylight levels, and b the same for blue,
    /// each rounded to 4 decimal places. A lens that reports itself changes
    /// the daylight levels, so the value varies with the lens.
    ///
    /// - Parameter reference: the daylight reference of the camera of this
    ///   ARW. There is no default, so a second camera cannot take the
    ///   values of the first by accident.
    static func calibration(red: Int, blue: Int, reference: ARWFacts.DaylightLevels) -> String {
        "\(ratio(reference.red, over: red)) 0 0 0 1 0 0 0 \(ratio(reference.blue, over: blue))"
    }

    /// `reference / level`, rounded to the nearest ten-thousandth, a half up,
    /// with four decimal places. Whole-number arithmetic: no value passes
    /// through a `Double`, so the rounding is exact.
    ///
    /// - Precondition: both numbers are above 0.
    static func ratio(_ reference: Int, over level: Int) -> String {
        let tenThousandths = (reference * 20_000 + level) / (2 * level)
        let fraction = String(tenThousandths % 10_000)
        return "\(tenThousandths / 10_000)." + String(repeating: "0", count: 4 - fraction.count) + fraction
    }

    // MARK: The read-back compare

    /// How far a number that was read back may be from the number that was
    /// written, as a part of the larger of the two. exiftool keeps some of
    /// these tags as fractions and prints 15 digits, so the text can differ
    /// in a last digit. Two values that this table can give differ by one
    /// part in ten thousand or more, so the tolerance cannot take one row,
    /// or one calibration, for another.
    static let tolerance = 1e-6

    /// True when the two texts hold the same count of numbers, at least one,
    /// and each pair is the same number within `tolerance`. Text that is no
    /// finite number is never the same, so exiftool's `-` for "no value"
    /// matches nothing.
    static func sameNumbers(_ written: String, _ read: String) -> Bool {
        let expected = numbers(written)
        let found = numbers(read)
        guard let expected, let found, !expected.isEmpty, expected.count == found.count else { return false }
        return zip(expected, found).allSatisfy { abs($0 - $1) <= tolerance * max(abs($0), abs($1)) }
    }

    /// Nil when one part is no finite number. `Double` parses "inf" and "nan".
    private static func numbers(_ text: String) -> [Double]? {
        var numbers: [Double] = []
        for part in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            guard let number = Double(part), number.isFinite else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    // MARK: The table

    /// One ISO setting of one camera.
    struct ISORow: Equatable, Sendable {
        let baselineExposure: String
        /// Six numbers, as text: the digits of the data file. They go to
        /// exiftool as they are and never pass through a `Double`.
        let noiseProfile: [String]
    }

    /// Everything the table holds for one camera model. Each value is the
    /// text that exiftool gets.
    struct Camera: Equatable, Sendable {
        let model: String
        let whiteLevel: String
        let baselineNoise: String
        let baselineSharpness: String
        let antiAliasStrength: String
        let bayerGreenSplit: String
        /// The daylight levels at which the calibration is the identity.
        let daylightReference: ARWFacts.DaylightLevels
        let byISO: [Int: ISORow]
    }

    /// Version 1 has one camera.
    static let cameras = [ilce7SM3]

    /// The Sony A7S III, firmware 5.00, compressed raw: one ARW at each of
    /// 23 ISO settings, 50 and 80 to 12800 with no file at 1250.
    static let ilce7SM3 = Camera(
        model: "ILCE-7SM3",
        whiteLevel: "16383",
        baselineNoise: "0.6",
        baselineSharpness: "1.25",
        antiAliasStrength: "1",
        bayerGreenSplit: "250",
        daylightReference: ARWFacts.DaylightLevels(red: 2568, green: 1024, blue: 1549),
        byISO: [
            50: ISORow(baselineExposure: "-0.85", noiseProfile: [
                "4.21530479896239e-06", "1.74264502949702e-09",
                "5.01258869306477e-06", "1.72900219262726e-09",
                "3.51529716945144e-06", "1.67897845743815e-09",
            ]),
            80: ISORow(baselineExposure: "0.15", noiseProfile: [
                "6.74448767833982e-06", "4.46117127551237e-09",
                "8.02014190890364e-06", "4.4262456131258e-09",
                "5.6244754711223e-06", "4.29818485104167e-09",
            ]),
            100: ISORow(baselineExposure: "0.15", noiseProfile: [
                "4.63385976958877e-05", "5.90010856583943e-09",
                "8.38315403982605e-05", "5.87216803593017e-09",
                "2.52826733806363e-05", "5.71150998895191e-09",
            ]),
            125: ISORow(baselineExposure: "0.15", noiseProfile: [
                "4.76523994811933e-05", "7.84918868780582e-09",
                "8.49431601434348e-05", "7.82043754271273e-09",
                "2.63630121309224e-05", "7.63975122686065e-09",
            ]),
            160: ISORow(baselineExposure: "0.15", noiseProfile: [
                "4.9491721980621e-05", "1.10444384381522e-08",
                "8.64994277866789e-05", "1.10161122665055e-08",
                "2.7875486381323e-05", "1.08096077187344e-08",
            ]),
            200: ISORow(baselineExposure: "0.15", noiseProfile: [
                "5.15938048371099e-05", "1.53626346951099e-08",
                "8.82780193789578e-05", "1.53370225426931e-08",
                "2.96040283817807e-05", "1.51041847934493e-08",
            ]),
            250: ISORow(baselineExposure: "0.15", noiseProfile: [
                "5.53181506065461e-05", "2.21413883778054e-08",
                "9.24856946669718e-05", "2.23875011516746e-08",
                "3.30640115968566e-05", "2.19495539439711e-08",
            ]),
            320: ISORow(baselineExposure: "0.15", noiseProfile: [
                "6.05322346837568e-05", "3.37071421628643e-08",
                "9.83764400701915e-05", "3.44915674158926e-08",
                "3.79079880979629e-05", "3.36760842221599e-08",
            ]),
            400: ISORow(baselineExposure: "0.15", noiseProfile: [
                "6.64911879148547e-05", "4.98901445304821e-08",
                "0.000105108720531014", "5.15153520202042e-08",
                "4.34439612420844e-05", "5.0139280922173e-08",
            ]),
            500: ISORow(baselineExposure: "0.15", noiseProfile: [
                "7.27962157625696e-05", "7.50049807242534e-08",
                "0.000112037842374304", "7.73419036065003e-08",
                "4.98039215686275e-05", "7.47312141546533e-08",
            ]),
            640: ISORow(baselineExposure: "0.15", noiseProfile: [
                "8.16232547493706e-05", "1.18737765975124e-07",
                "0.00012173861295491", "1.22284484998996e-07",
                "5.87078660257878e-05", "1.17376828934318e-07",
            ]),
            800: ISORow(baselineExposure: "0.15", noiseProfile: [
                "9.17112993057145e-05", "1.80963827089821e-07",
                "0.000132825207904173", "1.86198019692823e-07",
                "6.88838025482567e-05", "1.77853114759923e-07",
            ]),
            1000: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.000103510719462882", "1.20790950328907e-07",
                "0.000143669413290608", "1.23496147882678e-07",
                "7.99893186846723e-05", "1.18982548854e-07",
            ]),
            1600: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.000138908979934386", "1.29970031627923e-08",
                "0.000176202029449912", "1.23566993523717e-08",
                "0.000113305867093919", "1.31273923023689e-08",
            ]),
            2000: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.000167415503166247", "1.90222434766632e-08",
                "0.000193534370946822", "1.78580926127529e-08",
                "0.00012750667582208", "1.85592679108502e-08",
            ]),
            2500: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.000203048657206073", "2.8162574575984e-08",
                "0.00021519979781796", "2.61553082317443e-08",
                "0.00014525768673228", "2.66683166538119e-08",
            ]),
            3200: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.00025293507286183", "4.39620954347334e-08",
                "0.000245531395437552", "4.04229616462267e-08",
                "0.000170109102006561", "4.04834994610301e-08",
            ]),
            4000: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.000302214465552758", "5.74653674363738e-08",
                "0.000303097962920577", "5.40776800188555e-08",
                "0.000212717250324254", "5.38420712648735e-08",
            ]),
            5000: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.000363813706416419", "7.68838059232711e-08",
                "0.000375056172274357", "7.3935267771586e-08",
                "0.00026597743572137", "7.32141995130096e-08",
            ]),
            6400: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.000450052643625544", "1.08809736976641e-07",
                "0.00047579766536965", "1.06942378227705e-07",
                "0.000340541695277333", "1.05326484247953e-07",
            ]),
            8000: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.000526329823758297", "1.6625018866968e-07",
                "0.000548108262760357", "1.63115210111989e-07",
                "0.000406923399710079", "1.62886046607501e-07",
            ]),
            10000: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.000621676298924239", "2.55107064457157e-07",
                "0.000638496509498741", "2.49943725706132e-07",
                "0.000489900530251011", "2.5241098925512e-07",
            ]),
            12800: ISORow(baselineExposure: "0.15", noiseProfile: [
                "0.000755161364156558", "4.11345138079159e-07",
                "0.000765040054932479", "4.0251360225034e-07",
                "0.000606068513008316", "4.1055348973173e-07",
            ]),
        ])
}
