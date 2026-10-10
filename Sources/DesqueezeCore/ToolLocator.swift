import Foundation

/// Finds the three external tools: exiftool, dnglab, and Adobe DNG Converter.
/// Holds no path that is specific to one Mac.
///
/// A Mac app started from Finder gets a short `PATH` with no Homebrew folder,
/// so the two fixed Homebrew locations come first.
public struct ToolLocator: Sendable {
    public static let converterBundleID = "com.adobe.DNGConverter"
    public static let converterBinary = "/Contents/MacOS/Adobe DNG Converter"
    public static let standardConverterApp = "/Applications/Adobe DNG Converter.app"

    /// What a front end says when `exiftool()` gives nil (design, sections 6
    /// and 8). The window shows the sentence, and the command on a line of
    /// its own, from these two.
    public static let exiftoolMissing = "Desqueeze needs exiftool, and it is not installed."
    public static let exiftoolInstallCommand = "brew install exiftool"
    /// The sentence and the command on one line, as the command line tool
    /// and the MCP server say it. The only place that joins the two.
    public static let exiftoolMissingLine = "\(exiftoolMissing) Install it with: \(exiftoolInstallCommand)"
    /// For the advice about the converters (`FolderText.converterAdvice`,
    /// design 13.5).
    public static let dnglabInstallCommand = "brew install dnglab"
    /// The command as a line of advice. The only place that joins the two:
    /// the advice, the help of the tool and the MCP descriptions say it.
    public static let dnglabInstallLine = "Install dnglab with: \(dnglabInstallCommand)"

    public let exiftoolCandidates: [String]
    /// dnglab is looked for where exiftool is (design 13.5).
    public let dnglabCandidates: [String]
    public let converterApps: [String]
    private let isExecutable: @Sendable (String) -> Bool

    /// - Parameters:
    ///   - pathVariable: the value of `PATH`. Its folders are searched
    ///     after the two Homebrew folders.
    ///   - registeredConverterApp: the app that Launch Services returns for
    ///     `converterBundleID`. The app layer supplies it.
    ///   - isExecutable: true when the file at a path can be run. Tests
    ///     inject it.
    public init(
        pathVariable: String? = ProcessInfo.processInfo.environment["PATH"],
        registeredConverterApp: URL? = nil,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        // The two Homebrew folders, then each folder of `PATH`. A relative
        // entry would resolve against the app's working folder.
        var folders = ["/opt/homebrew/bin", "/usr/local/bin"]
        for folder in (pathVariable ?? "").split(separator: ":").map(String.init) where folder.hasPrefix("/") {
            if !folders.contains(folder) { folders.append(folder) }
        }
        exiftoolCandidates = folders.map { "\($0)/exiftool" }
        dnglabCandidates = folders.map { "\($0)/dnglab" }

        var apps: [String] = []
        if let registered = registeredConverterApp { apps.append(registered.path) }
        if !apps.contains(Self.standardConverterApp) { apps.append(Self.standardConverterApp) }
        converterApps = apps
        self.isExecutable = isExecutable
    }

    public func exiftool() -> URL? {
        exiftoolCandidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    public func dnglab() -> URL? {
        dnglabCandidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    public func dngConverter() -> URL? {
        converterApps.map { $0 + Self.converterBinary }
            .first(where: isExecutable)
            .map { URL(fileURLWithPath: $0) }
    }
}
