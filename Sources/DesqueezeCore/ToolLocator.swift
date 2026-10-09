import Foundation

/// Finds the two external tools. Holds no path that is specific to one Mac.
///
/// A Mac app started from Finder gets a short `PATH` with no Homebrew folder,
/// so the two fixed Homebrew locations come first.
public struct ToolLocator: Sendable {
    public static let converterBundleID = "com.adobe.DNGConverter"
    public static let converterBinary = "/Contents/MacOS/Adobe DNG Converter"
    public static let standardConverterApp = "/Applications/Adobe DNG Converter.app"

    /// What a front end says when `exiftool()` gives nil (design, sections 6
    /// and 8). The install command follows it, in the front end's own layout.
    public static let exiftoolMissing = "Desqueeze needs exiftool, and it is not installed."
    public static let exiftoolInstallCommand = "brew install exiftool"

    public let exiftoolCandidates: [String]
    public let converterApps: [String]
    private let isExecutable: @Sendable (String) -> Bool

    /// - Parameter registeredConverterApp: the app that Launch Services
    ///   returns for `converterBundleID`. The app layer supplies it.
    public init(
        pathVariable: String? = ProcessInfo.processInfo.environment["PATH"],
        registeredConverterApp: URL? = nil,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        var tools = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"]
        // A relative entry would resolve against the app's working folder.
        for folder in (pathVariable ?? "").split(separator: ":") where folder.hasPrefix("/") {
            let candidate = "\(folder)/exiftool"
            if !tools.contains(candidate) { tools.append(candidate) }
        }
        exiftoolCandidates = tools

        var apps: [String] = []
        if let registered = registeredConverterApp { apps.append(registered.path) }
        if !apps.contains(Self.standardConverterApp) { apps.append(Self.standardConverterApp) }
        converterApps = apps
        self.isExecutable = isExecutable
    }

    public func exiftool() -> URL? {
        exiftoolCandidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    public func dngConverter() -> URL? {
        converterApps.map { $0 + Self.converterBinary }
            .first(where: isExecutable)
            .map { URL(fileURLWithPath: $0) }
    }
}
