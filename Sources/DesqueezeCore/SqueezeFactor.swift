import Foundation

/// A horizontal stretch factor for the DNG `DefaultScale` tag.
///
/// The tag holds two numbers: horizontal stretch, then vertical stretch. This
/// app writes `<factor> 1`. A factor of 1 is no stretch.
public struct SqueezeFactor: Equatable, Hashable, Sendable {
    public static let range: ClosedRange<Double> = 1...4
    /// How close a read-back value must be to count as this factor: less than
    /// half of the smallest step between two factors, so neighbors never match.
    public static let tolerance = 0.00005
    public static let presets: [SqueezeFactor] = [1.33, 1.5, 1.8, 2].compactMap { SqueezeFactor($0) }
    /// No stretch. Remove writes this. Not named `none`: on a `SqueezeFactor?`,
    /// `.none` would mean nil.
    public static let noStretch = SqueezeFactor(1)!

    public let value: Double

    /// Rounds to four decimal places, then checks the range.
    public init?(_ value: Double) {
        let rounded = (value * 10_000).rounded() / 10_000
        guard Self.range.contains(rounded) else { return nil }
        self.value = rounded
    }

    /// Parses what the user typed: digits, and at most four decimal places.
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^[0-9]+(\.[0-9]{1,4})?$"#, options: .regularExpression) != nil,
              let number = Double(trimmed) else { return nil }
        self.init(number)
    }

    /// The factor with no trailing zeros: `1.5`, `2`, `1.3333`.
    public var label: String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The value exiftool writes: `<factor> 1`.
    public var tagValue: String { "\(label) 1" }

    public func matches(horizontal: Double, vertical: Double) -> Bool {
        abs(horizontal - value) < Self.tolerance && abs(vertical - 1) < Self.tolerance
    }

    /// An unknown scale matches no factor. So a file that gave no value is
    /// never counted as "already set", for Apply or for Remove.
    public func matches(_ scale: Scale?) -> Bool {
        guard let scale else { return false }
        return matches(horizontal: scale.horizontal, vertical: scale.vertical)
    }
}
