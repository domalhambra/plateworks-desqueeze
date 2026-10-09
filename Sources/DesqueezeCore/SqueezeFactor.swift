import Foundation

/// A horizontal stretch factor for the DNG `DefaultScale` tag.
///
/// The tag holds two numbers: horizontal stretch, then vertical stretch. This
/// app writes `<factor> 1`. A factor of 1 is no stretch.
public struct SqueezeFactor: Equatable, Hashable, Sendable {
    public static let range: ClosedRange<Double> = 1...4
    /// How close a read-back value must be to count as this factor.
    public static let tolerance = 0.0001
    public static let presets: [SqueezeFactor] = [1.33, 1.5, 1.8, 2].compactMap { SqueezeFactor($0) }
    /// No stretch. Remove writes this.
    public static let none = SqueezeFactor(1)!

    public let value: Double

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
        abs(horizontal - value) <= Self.tolerance && abs(vertical - 1) <= Self.tolerance
    }
}
