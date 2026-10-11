import Foundation

/// Finds the three external tools: exiftool, dnglab, and Adobe DNG Converter.
/// Holds no path that is specific to one Mac.
///
/// A Mac app started from Finder gets a short `PATH` with no Homebrew folder,
/// so the two fixed Homebrew locations come first.
///
/// The downloaded app has exiftool and dnglab inside (design 15). The app
/// layer gives the two places in its bundle, and a copy there comes before
/// every other copy. The command line tool and the MCP server give no
/// place, so they look on the Mac only.
public struct ToolLocator: Sendable {
    /// The Perl of macOS. The exiftool inside the app is a Perl script, and
    /// its first line names this path (design 15.3).
    public static let systemPerl = "/usr/bin/perl"

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
    /// The exiftool inside the app's bundle. Nil when the caller gave none.
    public let bundledExiftool: String?
    /// The dnglab inside the app's bundle. Nil when the caller gave none.
    public let bundledDnglab: String?
    private let isExecutable: @Sendable (String) -> Bool

    /// - Parameters:
    ///   - pathVariable: the value of `PATH`. Its folders are searched
    ///     after the two Homebrew folders.
    ///   - registeredConverterApp: the app that Launch Services returns for
    ///     `converterBundleID`. The app layer supplies it.
    ///   - bundledExiftool: the place of exiftool inside the app's bundle.
    ///     The app layer supplies it. It comes first, when it can be run
    ///     and `systemPerl` can be run. Nil: only the Mac is searched.
    ///   - bundledDnglab: the place of dnglab inside the app's bundle. The
    ///     app layer supplies it. It comes first, when it can be run. Nil:
    ///     only the Mac is searched.
    ///   - isExecutable: true when the file at a path can be run. Tests
    ///     inject it.
    public init(
        pathVariable: String? = ProcessInfo.processInfo.environment["PATH"],
        registeredConverterApp: URL? = nil,
        bundledExiftool: URL? = nil,
        bundledDnglab: URL? = nil,
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
        self.bundledExiftool = bundledExiftool?.path
        self.bundledDnglab = bundledDnglab?.path
        self.isExecutable = isExecutable
    }

    /// The copy in the bundle, when it can be run and the Perl of macOS can
    /// be run. Then the first candidate that can be run (design 15.4).
    public func exiftool() -> URL? {
        if let bundledExiftool, isExecutable(bundledExiftool), isExecutable(Self.systemPerl) {
            return URL(fileURLWithPath: bundledExiftool)
        }
        return exiftoolCandidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    /// The copy in the bundle, when it can be run. Then the first candidate
    /// that can be run (design 15.4).
    public func dnglab() -> URL? {
        if let bundledDnglab, isExecutable(bundledDnglab) { return URL(fileURLWithPath: bundledDnglab) }
        return dnglabCandidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    public func dngConverter() -> URL? {
        converterApps.map { $0 + Self.converterBinary }
            .first(where: isExecutable)
            .map { URL(fileURLWithPath: $0) }
    }
}
