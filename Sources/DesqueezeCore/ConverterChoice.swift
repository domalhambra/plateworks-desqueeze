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

/// The sentences about who converts, made once. The help of the tool and
/// the descriptions of the MCP server say them, so no front end words them
/// again (design 13.5). The advice line about a missing converter is made
/// at `FolderText.converterAdvice`.
///
/// "dnglab converts first" is short for the table of `ConverterChoice`, and
/// it is not the rule: with both installed, an ARW with no full match goes
/// to Adobe DNG Converter, and dnglab is not tried. So a text for a person
/// or a model says `whoConverts`.
public enum ConverterText {
    public static let whoConverts = "\(ConverterKind.dnglab.name) converts each photo that it can match. "
        + "\(ConverterKind.adobe.name), when it is installed, converts the others."
    /// Why a photo from dnglab shows in Lightroom as one from Adobe does.
    public static let matchedValues = "Each DNG that \(ConverterKind.dnglab.name) makes gets the values that "
        + "\(ConverterKind.adobe.name) writes, so Lightroom shows the same photo."
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
    /// - Parameters:
    ///   - fullMatch: the five rules of design 13.4 hold for the ARW, so a
    ///     dnglab DNG with the match tags renders as Adobe's does.
    ///   - dnglabInstalled: true when dnglab is installed.
    ///   - adobeInstalled: true when Adobe DNG Converter is installed.
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
