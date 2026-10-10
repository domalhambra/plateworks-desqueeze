import Foundation

/// The two converters, by the names that the JSON gives them (design 13.6).
public enum ConverterKind: String, Codable, Sendable, CaseIterable {
    case dnglab
    case adobe

    /// The converter as a sentence names it: `dnglab`, `Adobe DNG Converter`.
    public var name: String {
        switch self {
        case .dnglab: return "dnglab"
        case .adobe: return "Adobe DNG Converter"
        }
    }
}

/// Which converters get one ARW, and in which order (design 13.4). Pure: the
/// run and the dry run both ask here, so the two cannot disagree.
///
/// | The ARW | dnglab and Adobe | Only dnglab | Only Adobe | Neither |
/// |---|---|---|---|---|
/// | Full match | dnglab, then Adobe | dnglab | Adobe | none |
/// | No full match | Adobe | dnglab | Adobe | none |
///
/// The run gives the ARW to the first converter. When that one fails, the
/// next one gets it. The ARW is failed when the last one failed.
public enum ConverterChoice {
    /// - Parameter fullMatch: the five rules of design 13.4 hold for the ARW,
    ///   so a dnglab DNG with the match tags renders as Adobe's does.
    /// - Returns: the converters to try, in order. Empty when none is
    ///   installed: the ARW is not converted.
    public static func order(fullMatch: Bool, dnglabInstalled: Bool, adobeInstalled: Bool) -> [ConverterKind] {
        switch (dnglabInstalled, adobeInstalled) {
        // Without a full match, Adobe gives the file that Lightroom makes.
        // dnglab is not asked, also not after Adobe failed.
        case (true, true): return fullMatch ? [.dnglab, .adobe] : [.adobe]
        // "Matched as far as the table goes", with a note, when it is no
        // full match.
        case (true, false): return [.dnglab]
        case (false, true): return [.adobe]
        case (false, false): return []
        }
    }

    /// The order for an ARW with these facts. `AdobeMatch` says what a full
    /// match is.
    public static func order(for facts: ARWFacts, dnglabInstalled: Bool, adobeInstalled: Bool) -> [ConverterKind] {
        order(fullMatch: AdobeMatch.match(facts).isFull, dnglabInstalled: dnglabInstalled,
              adobeInstalled: adobeInstalled)
    }
}
